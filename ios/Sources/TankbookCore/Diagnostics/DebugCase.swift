import Foundation

/// One part of a debug case as it goes on the wire: a name the server keeps
/// (`^[a-z0-9][a-z0-9._-]{0,63}$`), a content type from the server's allowed
/// set, and the bytes (docs/API.md -> Debug cases).
public struct DebugCasePart: Sendable, Equatable {
    public let name: String
    public let contentType: String
    public let data: Data

    public init(name: String, contentType: String, data: Data) {
        self.name = name
        self.contentType = contentType
        self.data = data
    }
}

/// What the user chose to send: the diagnostics text and the kept scans, as
/// the parts `POST /v1/cases` takes. Built on the device from what the user
/// previewed; the server stores it opaque (hard rule 9).
public enum DebugCase {
    /// The parts, in order: the manifest, the log, then each scan's photo,
    /// record and trace (`scan-1-...` is the oldest).
    public static func parts(log: String, scans: [ScanHistory.Entry], app: String, build: String?,
                             now: Date = Date()) -> [DebugCasePart] {
        var parts: [DebugCasePart] = []
        var scanNames: [[String]] = []
        var scanParts: [DebugCasePart] = []
        for (index, scan) in scans.enumerated() {
            var names: [String] = []
            for (file, contentType) in [(ScanHistory.photoFile, "image/jpeg"),
                                        (ScanHistory.recordFile, "application/json"),
                                        (ScanHistory.traceFile, "application/json")] {
                guard scan.files.contains(file),
                      let data = try? Data(contentsOf: scan.folder.appendingPathComponent(file)) else { continue }
                let name = "scan-\(index + 1)-\(file)"
                names.append(name)
                scanParts.append(DebugCasePart(name: name, contentType: contentType, data: data))
            }
            scanNames.append(names)
        }
        let manifest: [String: Any] = [
            "kind": "diagnostics", "app": app, "build": build ?? NSNull(), "platform": "ios",
            "generatedAt": LogRenderer.timestamp(now), "scans": scanNames
        ]
        let manifestData = (try? JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])) ?? Data()
        parts.append(DebugCasePart(name: "manifest.json", contentType: "application/json", data: manifestData))
        parts.append(DebugCasePart(name: "log.txt", contentType: "text/plain", data: Data(log.utf8)))
        parts.append(contentsOf: scanParts)
        return parts
    }

    /// The `multipart/form-data` body: one file field per part, named by the part.
    public static func multipartBody(_ parts: [DebugCasePart], boundary: String) -> Data {
        var body = Data()
        for part in parts {
            body.append(Data("--\(boundary)\r\n".utf8))
            body.append(Data("Content-Disposition: form-data; name=\"\(part.name)\"; filename=\"\(part.name)\"\r\n".utf8))
            body.append(Data("Content-Type: \(part.contentType)\r\n\r\n".utf8))
            body.append(part.data)
            body.append(Data("\r\n".utf8))
        }
        body.append(Data("--\(boundary)--\r\n".utf8))
        return body
    }
}

/// What the phone shows after a send: the id to paste, and until when it is kept.
public struct DebugCaseReceipt: Sendable, Equatable, Decodable {
    public let caseId: String
    public let expiresAt: Date

    public init(caseId: String, expiresAt: Date) {
        self.caseId = caseId
        self.expiresAt = expiresAt
    }
}

/// Why a send did not arrive, each with its own next step (docs/ERRORS.md ->
/// Send diagnostics).
public enum DebugCaseError: Error, Sendable, Equatable {
    /// No route to the server: try again with a connection.
    case offline
    /// `429`: sent too often; try again in a minute.
    case rateLimited
    /// `413`: the case is too large; send it without the scans.
    case tooLarge
    /// Anything else, including a response that was not the expected JSON.
    case failed(status: Int?)
}

/// The host-bound client for `POST /v1/cases`. Everything goes through
/// `TankbookHTTPClient`, so the host allowlist applies exactly as for sync; the
/// transport is injectable, so tests open no sockets.
public struct DebugCaseClient: Sendable {
    public let httpClient: TankbookHTTPClient
    public let director: ConfigTransportDirector
    public let deviceID: String?

    public init(httpClient: TankbookHTTPClient, director: ConfigTransportDirector, deviceID: String?) {
        self.httpClient = httpClient
        self.director = director
        self.deviceID = deviceID
    }

    public func send(_ parts: [DebugCasePart]) async throws -> DebugCaseReceipt {
        let url = director.baseURL().appendingPathComponent("v1").appendingPathComponent("cases")
        let boundary = "tankbook-case-\(UUID().uuidString)"
        var request = TankbookHTTPRequest(url: url, method: "POST",
                                          body: DebugCase.multipartBody(parts, boundary: boundary),
                                          timeoutInterval: TransportTimeouts.upload)
        request.headers["Content-Type"] = "multipart/form-data; boundary=\(boundary)"
        if let deviceID { request.headers["X-Device-Id"] = deviceID }
        let response: TankbookHTTPResponse
        do {
            response = try await httpClient.send(request)
        } catch TankbookHTTPClientError.httpError(let status, _, _, _, _) {
            await director.report(.response(status: status))
            switch status {
            case 429: throw DebugCaseError.rateLimited
            case 413: throw DebugCaseError.tooLarge
            default: throw DebugCaseError.failed(status: status)
            }
        } catch {
            if case .connectivity = TransportErrorClassifier.classify(error) {
                await director.report(.transportFailure)
                throw DebugCaseError.offline
            }
            throw DebugCaseError.failed(status: nil)
        }
        await director.report(.response(status: response.status))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard (200...299).contains(response.status), let body = response.body,
              let receipt = try? decoder.decode(DebugCaseReceipt.self, from: body) else {
            throw DebugCaseError.failed(status: response.status)
        }
        return receipt
    }
}

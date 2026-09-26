import Foundation
import os
import Testing
@testable import TankbookCore

/// The phone half of a debug case (docs/API.md -> Debug cases): the kept scans
/// stay bounded, the parts are what the server accepts, and each send failure
/// maps to its own next step.
@Suite("Debug cases, phone half (DC.2, AD.2)")
struct DebugCaseTests {
    private func tempDir() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("dc2-\(UUID().uuidString)")
    }

    @Test("the scan history keeps the newest scans only, oldest first")
    func historyIsBounded() {
        let directory = tempDir()
        defer { try? FileManager.default.removeItem(at: directory) }
        let history = ScanHistory(directory: directory)
        let start = Date()
        for index in 0..<(ScanHistory.capacity + 2) {
            history.record(photo: Data("photo-\(index)".utf8), record: Data("{}".utf8),
                           trace: index.isMultiple(of: 2) ? Data("{}".utf8) : nil,
                           at: start.addingTimeInterval(Double(index)))
        }
        let recent = history.recent()
        #expect(recent.count == ScanHistory.capacity)
        let photos = recent.compactMap { try? String(contentsOf: $0.folder.appendingPathComponent(ScanHistory.photoFile),
                                                     encoding: .utf8) }
        #expect(photos == (2..<(ScanHistory.capacity + 2)).map { "photo-\($0)" }, "the two oldest are gone")
        #expect(recent.last?.files == [ScanHistory.photoFile, ScanHistory.recordFile, ScanHistory.traceFile])
    }

    @Test("the parts carry names and types the server accepts, in manifest, log, scans order")
    func partsMatchTheServerEnvelope() throws {
        let directory = tempDir()
        defer { try? FileManager.default.removeItem(at: directory) }
        let history = ScanHistory(directory: directory)
        let first = Date(timeIntervalSince1970: 1_790_000_000)
        history.record(photo: Data([0xFF, 0xD8]), record: Data("{\"a\":1}".utf8), trace: Data("{}".utf8), at: first)
        history.record(photo: Data([0xFF, 0xD9]), record: Data("{\"b\":2}".utf8), trace: nil,
                       at: first.addingTimeInterval(20))

        let parts = DebugCase.parts(log: "line one", scans: history.recent(), app: "1.0.0", build: "abc1234")
        #expect(parts.map(\.name) == ["manifest.json", "log.txt",
                                      "scan-1-photo.jpg", "scan-1-record.json", "scan-1-trace.json",
                                      "scan-2-photo.jpg", "scan-2-record.json"])
        let allowed: Set<String> = ["text/plain", "application/json", "image/jpeg", "image/png", "image/heic"]
        let namePattern = try Regex("^[a-z0-9][a-z0-9._-]{0,63}$")
        for part in parts {
            #expect(allowed.contains(part.contentType), "\(part.name) has \(part.contentType)")
            #expect(part.name.wholeMatch(of: namePattern) != nil, "\(part.name) is not a server part name")
        }
        let manifest = try #require(JSONSerialization.jsonObject(with: parts[0].data) as? [String: Any])
        #expect(manifest["build"] as? String == "abc1234")
        #expect((manifest["scans"] as? [[String]])?.count == 2)
        #expect(String(data: parts[1].data, encoding: .utf8) == "line one")
    }

    @Test("the scan record carries the decision, the read fields and the text lines")
    func scanRecordContent() throws {
        var record = ScanRecord(capturedAt: Date(timeIntervalSince1970: 0), requestedSource: nil,
                                resolvedSource: .pump, provenance: "pumpPhoto", durationMs: 812,
                                extraction: FuelExtraction(liters: 24.77, total: Decimal(string: "50.38")))
        record.ocrLines = [OCRLine(text: "LIITRIT", confidence: 0.9, boundingBox: CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.05))]
        record.pumpRotationCW = 90
        let json = try #require(JSONSerialization.jsonObject(with: record.data) as? [String: Any])
        #expect(json["resolvedSource"] as? String == "pump")
        #expect(json["requestedSource"] is NSNull, "an auto capture requested no source")
        #expect(json["pumpRotationCW"] as? Int == 90)
        #expect((json["extraction"] as? [String: Any])?["liters"] as? Double == 24.77)
        #expect(((json["ocrLines"] as? [[String: Any]])?.first)?["text"] as? String == "LIITRIT")
    }

    @Test("the multipart body names each part as a file field")
    func multipartBody() {
        let body = DebugCase.multipartBody([DebugCasePart(name: "log.txt", contentType: "text/plain",
                                                          data: Data("hello".utf8))], boundary: "B")
        let text = String(decoding: body, as: UTF8.self)
        #expect(text == "--B\r\nContent-Disposition: form-data; name=\"log.txt\"; filename=\"log.txt\"\r\n"
                + "Content-Type: text/plain\r\n\r\nhello\r\n--B--\r\n")
    }

    @Test("progress counts a part as uploaded once every byte of it has been sent")
    func partsSentFollowsTheBody() {
        let parts = [DebugCasePart(name: "a.txt", contentType: "text/plain", data: Data(count: 100)),
                     DebugCasePart(name: "b.txt", contentType: "text/plain", data: Data(count: 1_000)),
                     DebugCasePart(name: "c.txt", contentType: "text/plain", data: Data(count: 10))]
        let multipart = DebugCase.multipart(parts, boundary: "B")
        #expect(multipart.partEnds.count == 3)
        #expect(multipart.partEnds.last! < Int64(multipart.body.count), "the closing boundary follows the last part")
        #expect(DebugCase.partsSent(0, partEnds: multipart.partEnds) == 0)
        #expect(DebugCase.partsSent(multipart.partEnds[0] - 1, partEnds: multipart.partEnds) == 0)
        #expect(DebugCase.partsSent(multipart.partEnds[0], partEnds: multipart.partEnds) == 1)
        #expect(DebugCase.partsSent(multipart.partEnds[1] + 5, partEnds: multipart.partEnds) == 2)
        #expect(DebugCase.partsSent(Int64(multipart.body.count), partEnds: multipart.partEnds) == 3)
    }

    @Test("the send hands the transport a progress handler that reports parts, not bytes")
    func progressReachesTheTransport() async throws {
        let transport = ProgressReportingTransport()
        let client = DebugCaseClient(
            httpClient: TankbookHTTPClient(transport: transport, tokenProvider: CaseTestTokens()),
            director: ConfigTransportDirector(baseURL: { URL(string: "https://api.tankbook.live")! }, report: { _ in }),
            deviceID: "device-1")
        let parts = [DebugCasePart(name: "log.txt", contentType: "text/plain", data: Data(count: 500)),
                     DebugCasePart(name: "scan-1-photo.jpg", contentType: "image/jpeg", data: Data(count: 5_000))]
        let seen = OSAllocatedUnfairLock(initialState: [(Int, Int)]())
        _ = try await client.send(parts) { uploaded, total in seen.withLock { $0.append((uploaded, total)) } }
        let reports = seen.withLock { $0 }
        #expect(reports.map(\.0) == [0, 1, 2], "half the body, then the first part's end, then all of it")
        #expect(reports.allSatisfy { $0.1 == 2 })
    }

    @Test("a 201 is the receipt; 429, 413 and no connection each map to their own error")
    func clientMapsEachOutcome() async throws {
        let transport = CaseTestTransport()
        let client = DebugCaseClient(
            httpClient: TankbookHTTPClient(transport: transport, tokenProvider: CaseTestTokens()),
            director: ConfigTransportDirector(baseURL: { URL(string: "https://api.tankbook.live")! }, report: { _ in }),
            deviceID: "device-1")
        let parts = [DebugCasePart(name: "log.txt", contentType: "text/plain", data: Data("x".utf8))]

        transport.script(TankbookHTTPResponse(status: 201, body: Data(
            #"{"caseId":"K7Q2M-9XDRA","expiresAt":"2026-10-26T12:00:00+00:00"}"#.utf8)))
        let receipt = try await client.send(parts)
        #expect(receipt.caseId == "K7Q2M-9XDRA")
        let request = try #require(transport.received().last)
        #expect(request.url.path == "/v1/cases")
        #expect(request.headers["X-Device-Id"] == "device-1")
        #expect(request.headers["Content-Type"]?.hasPrefix("multipart/form-data; boundary=") == true)

        transport.script(TankbookHTTPResponse(status: 429))
        await #expect(throws: DebugCaseError.rateLimited) { _ = try await client.send(parts) }
        transport.script(TankbookHTTPResponse(status: 413))
        await #expect(throws: DebugCaseError.tooLarge) { _ = try await client.send(parts) }
        transport.failWith(URLError(.notConnectedToInternet))
        await #expect(throws: DebugCaseError.offline) { _ = try await client.send(parts) }
    }
}

private final class CaseTestTransport: TankbookHTTPTransport, @unchecked Sendable {
    private struct State {
        var next: TankbookHTTPResponse?
        var error: Error?
        var received: [TankbookHTTPRequest] = []
    }
    private let lock = OSAllocatedUnfairLock(initialState: State())

    func script(_ response: TankbookHTTPResponse) { lock.withLock { $0.next = response; $0.error = nil } }
    func failWith(_ error: Error) { lock.withLock { $0.error = error } }
    func received() -> [TankbookHTTPRequest] { lock.withLock { $0.received } }

    func execute(_ request: TankbookHTTPRequest) async throws -> TankbookHTTPResponse {
        try lock.withLock { state in
            state.received.append(request)
            if let error = state.error { throw error }
            return state.next ?? TankbookHTTPResponse(status: 500)
        }
    }
}

/// Answers 201 after reporting three byte counts through the task-local handler,
/// as the URLSession transport does while the body leaves the device.
private final class ProgressReportingTransport: TankbookHTTPTransport, @unchecked Sendable {
    func execute(_ request: TankbookHTTPRequest) async throws -> TankbookHTTPResponse {
        let total = Int64(request.body?.count ?? 0)
        if let handler = UploadProgress.handler {
            let body = request.body ?? Data()
            let firstEnd = Int64((body.range(of: Data("--".utf8), in: 10..<body.count)?.lowerBound ?? 0))
            handler(firstEnd / 2)
            handler(firstEnd)
            handler(total)
        }
        return TankbookHTTPResponse(status: 201, body: Data(
            #"{"caseId":"K7Q2M-9XDRA","expiresAt":"2026-10-26T12:00:00+00:00"}"#.utf8))
    }
}

private final class CaseTestTokens: AuthorizationTokenProvider, @unchecked Sendable {
    func token() -> String? { nil }
}

/// `capture.pumpRead`: counts, field names and codes, each on its own key.
@Suite("capture.pumpRead line (DC.3)")
struct CapturePumpReadTests {
    @Test("the line names every stage's count and the stopping reason")
    func lineShape() {
        var summary = PumpReadSummary()
        summary.attempts = 2
        summary.chosen = nil
        summary.candidates = 5
        summary.kept = 1
        summary.dropReasons = ["tooShort", "atFrameEdge"]
        summary.verified = 1
        summary.roles = ["liters"]
        summary.lawReason = "missingTotal"
        let line = LogLine(timestamp: Date(), level: .info, category: .capture, event: "capture.pumpRead",
                           traceId: nil, deviceId: nil, appVersion: "t", platform: "ios",
                           fields: Redactor.shared.redact(CapturePumpRead(summary).fields))
        let text = LogRenderer.render(line, revealSensitive: false)
        #expect(text.contains("candidates=5"))
        #expect(text.contains("kept=1"))
        #expect(text.contains("dropReasons=tooShort,atFrameEdge"))
        #expect(text.contains("roles=liters"))
        #expect(text.contains("lawReason=missingTotal"))
        #expect(text.contains("chosen=none"))
        #expect(!text.contains("<redacted>"), "every field is Safe-class")
    }
}

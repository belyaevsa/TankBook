import Foundation
import os

/// The last few captures as the pipeline saw them - the photo, what was read
/// from it and the pump reader's trace - kept on the device so a debug case
/// the user chooses to send can carry them (hard rule 9's debug-cases
/// amendment). Nothing here leaves the device on its own.
///
/// Bounded: the newest `capacity` scans are kept and older folders deleted on
/// every record. The directory and every file carry the promised
/// file-protection class (docs/SECURITY.md).
public final class ScanHistory: Sendable {
    /// One kept scan: its folder and the files in it, by name.
    public struct Entry: Sendable, Equatable {
        public let folder: URL
        public let capturedAt: Date
        public let files: [String]
    }

    /// How many scans are kept. Compiled: it bounds what the device stores and
    /// what one case can carry.
    public static let capacity = 5

    public static let photoFile = "photo.jpg"
    public static let recordFile = "record.json"
    public static let traceFile = "trace.json"

    public let directory: URL
    private let lock = OSAllocatedUnfairLock()

    public init(directory: URL) {
        self.directory = directory
    }

    /// The production location: `Application Support/Scans`.
    public static func standard() -> ScanHistory? {
        guard let base = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                      appropriateFor: nil, create: true) else { return nil }
        return ScanHistory(directory: base.appendingPathComponent("Scans", isDirectory: true))
    }

    /// Keeps one scan and drops the oldest past `capacity`. A write that fails
    /// is dropped: recording never fails the capture.
    public func record(photo: Data, record: Data, trace: Data?, at date: Date = Date()) {
        lock.withLock {
            let manager = FileManager.default
            if !manager.fileExists(atPath: directory.path) {
                try? manager.createDirectory(at: directory, withIntermediateDirectories: true)
            }
            FileProtection.protect(directory)
            let stamp = LogRenderer.timestamp(date).replacingOccurrences(of: ":", with: "-")
            let folder = directory.appendingPathComponent("scan-\(stamp)-\(UUID().uuidString.prefix(8))",
                                                          isDirectory: true)
            guard (try? manager.createDirectory(at: folder, withIntermediateDirectories: true)) != nil else { return }
            FileProtection.protect(folder)
            var files: [(String, Data)] = [(Self.photoFile, photo), (Self.recordFile, record)]
            if let trace { files.append((Self.traceFile, trace)) }
            for (name, data) in files {
                let url = folder.appendingPathComponent(name)
                if (try? data.write(to: url, options: .atomic)) != nil {
                    FileProtection.protect(url)
                }
            }
            for old in folders().dropLast(Self.capacity) {
                try? manager.removeItem(at: old)
            }
        }
    }

    /// The kept scans, oldest first.
    public func recent() -> [Entry] {
        lock.withLock {
            folders().compactMap { folder in
                let files = ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).sorted()
                guard files.contains(Self.photoFile) else { return nil }
                let created = (try? FileManager.default.attributesOfItem(atPath: folder.path)[.creationDate]) as? Date
                return Entry(folder: folder, capturedAt: created ?? .distantPast, files: files)
            }
        }
    }

    /// Scan folders, oldest first: the folder name leads with its UTC stamp.
    private func folders() -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.filter { $0.hasPrefix("scan-") }.sorted()
            .map { directory.appendingPathComponent($0, isDirectory: true) }
    }
}

/// The record kept beside a scan's photo: what the pipeline decided and read.
/// It holds what the photo already shows (the read fields and the text lines),
/// so it is kept and sent exactly like the photo - on the device, and in a
/// case only by the user's tap.
public struct ScanRecord: Sendable {
    public var capturedAt: Date
    public var requestedSource: ExtractionSource?
    public var resolvedSource: ExtractionSource
    public var provenance: String
    public var durationMs: Int
    public var extraction: FuelExtraction
    public var ocrLines: [OCRLine] = []
    public var detection: PumpDisplayCapture.Detection?
    public var pumpRotationCW: Int?
    public var build: String?

    public init(capturedAt: Date, requestedSource: ExtractionSource?, resolvedSource: ExtractionSource,
                provenance: String, durationMs: Int, extraction: FuelExtraction) {
        self.capturedAt = capturedAt
        self.requestedSource = requestedSource
        self.resolvedSource = resolvedSource
        self.provenance = provenance
        self.durationMs = durationMs
        self.extraction = extraction
    }

    /// The record as JSON; `{}` if it cannot be serialised, never a failed capture.
    public var data: Data {
        var record: [String: Any] = [
            "capturedAt": LogRenderer.timestamp(capturedAt),
            "requestedSource": requestedSource?.rawValue ?? NSNull(),
            "resolvedSource": resolvedSource.rawValue,
            "provenance": provenance,
            "durationMs": durationMs,
            "build": build ?? NSNull(),
            "pumpRotationCW": pumpRotationCW ?? NSNull()
        ]
        if let detection {
            record["detection"] = ["display": detection.isPumpDisplay, "rows": detection.displayRows,
                                   "textLines": detection.textLines, "widestRow": Double(detection.widestRow),
                                   "tallestRow": Double(detection.tallestRow), "path": detection.path.rawValue]
        }
        if let extractionData = try? JSONEncoder().encode(extraction),
           let extractionJSON = try? JSONSerialization.jsonObject(with: extractionData) {
            record["extraction"] = extractionJSON
        }
        record["ocrLines"] = ocrLines.map { line -> [String: Any] in
            let box = line.boundingBox
            return ["text": line.text, "confidence": Double(line.confidence),
                    "box": [Double(box.minX), Double(box.minY), Double(box.width), Double(box.height)]]
        }
        guard JSONSerialization.isValidJSONObject(record) else { return Data("{}".utf8) }
        return (try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])) ?? Data("{}".utf8)
    }
}

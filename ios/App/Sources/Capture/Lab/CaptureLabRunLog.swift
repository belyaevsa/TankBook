#if EXPERIMENTS
import Foundation
import ImageIO
import TankbookCore

/// The Capture Lab's on-device log. Each run writes one folder under
/// `Documents/CaptureLab/<yyyy-MM-dd-HHmmss>/` holding every photo as the camera
/// delivered it minus its location (`<preset>.jpg`) and one `run.json`.
///
/// This is the owner's lab notebook on the owner's device, not telemetry: the
/// committed values are in the file because comparing them is the point. Hard
/// rule 12 governs the OSLog, which gets nothing from this screen beyond what
/// `CapturePipeline` already emits.

enum CaptureLabLogError: Error {
    case locationNotStripped
}

/// One preset's outcome. Every field the brief asks the table and the log to
/// carry: what applied, how long and how big the capture was, the camera's EXIF
/// when it has any, and what the reader made of the frame.
struct CaptureLabResult: Codable, Equatable {
    var preset: String
    var applied: CaptureLabApplied
    var captureMs: Int
    var bytes: Int
    var width: Int
    var height: Int
    var exif: CaptureLabExif?
    var classifyPath: String?
    var isDisplay: Bool
    var rows: Int
    var textLines: Int
    var committed: CaptureLabCommitted
    var pipelineMs: Int
    var resolvedFields: Int?
    var crossCheck: String?

    /// How many of the three committed values resolved - the count the table
    /// shows (the values themselves stay in the log).
    var committedCount: Int { committed.count }
}

/// The three values the reader committed, kept as the numbers they are. The
/// on-screen table shows only the count; this is what the log is for.
struct CaptureLabCommitted: Codable, Equatable {
    var liters: Double?
    var unitPrice: Decimal?
    var total: Decimal?

    var count: Int {
        [liters != nil, unitPrice != nil, total != nil].filter { $0 }.count
    }
}

/// The EXIF the camera carried, when `photo.metadata` has it. Absent on the
/// simulator's test frame, which is a plain image with no capture metadata.
struct CaptureLabExif: Codable, Equatable {
    var exposureTime: Double?
    var iso: Double?
    var focalLength: Double?
}

/// One run's whole record: when it started, which pipeline scored it, the
/// device, and one result per preset shot.
struct CaptureLabRunLog: Codable, Equatable {
    var startedAt: String
    var source: String
    var device: String
    var results: [CaptureLabResult]
}

/// The folder and file layout, and the JSON codec. A value with a root URL so
/// the unit test can write into a temp directory without touching Documents.
struct CaptureLabLogStore {
    var root: URL

    /// `Documents/CaptureLab` - where every session folder lives.
    static var defaultRoot: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CaptureLab", isDirectory: true)
    }

    static func sessionName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter.string(from: date)
    }

    /// Creates the session folder and returns it.
    func makeSessionDirectory(now: Date = Date()) throws -> URL {
        let url = root.appendingPathComponent(Self.sessionName(for: now), isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Writes one photo with its location removed and nothing else changed: the
    /// pixels are copied, not re-encoded, so the corpus intake can take it as
    /// the camera delivered it. A photo whose GPS cannot be removed is not
    /// written at all.
    static func writePhoto(_ data: Data, preset: CaptureLabPreset, to directory: URL) throws {
        guard let stripped = withoutLocation(data) else { throw CaptureLabLogError.locationNotStripped }
        let url = directory.appendingPathComponent("\(preset.id).jpg")
        try stripped.write(to: url, options: [.atomic])
        FileProtection.protect(url)
    }

    /// `data` re-containered by ImageIO without its GPS metadata
    /// (`kCGImageMetadataShouldExcludeGPS`); nil when ImageIO cannot read or
    /// copy it. The source's own metadata is handed back explicitly: without
    /// `kCGImageDestinationMetadata` the copy drops every EXIF field, not just
    /// the location (`CaptureLabTests` pins both).
    static func withoutLocation(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let type = CGImageSourceGetType(source) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, type, 1, nil) else { return nil }
        var options: [CFString: Any] = [kCGImageMetadataShouldExcludeGPS: true]
        // A photo with no metadata has no location to remove either.
        if let metadata = CGImageSourceCopyMetadataAtIndex(source, 0, nil) {
            options[kCGImageDestinationMetadata] = metadata
        }
        guard CGImageDestinationCopyImageSource(destination, source, options as CFDictionary, nil) else { return nil }
        return output as Data
    }

    /// The run log's bytes. Split out so a unit test can round-trip the JSON
    /// without a filesystem.
    static func encode(_ log: CaptureLabRunLog) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(log)
    }

    static func decode(_ data: Data) throws -> CaptureLabRunLog {
        try JSONDecoder().decode(CaptureLabRunLog.self, from: data)
    }

    @discardableResult
    func write(_ log: CaptureLabRunLog, to directory: URL) throws -> URL {
        let url = directory.appendingPathComponent("run.json")
        try Self.encode(log).write(to: url, options: [.atomic])
        FileProtection.protect(url)
        return url
    }
}
#endif

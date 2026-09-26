import Foundation
import os

/// The app's own log on disk (docs/LOGGING.md §5): every emitted line, already
/// redacted and rendered with Sensitive values masked in every build, appended
/// to one file per UTC day. It is what the diagnostics bundle reads. The unified
/// log cannot serve that purpose on iOS: `OSLogStore` opens only the current
/// process's entries, so a bundle built from it loses everything before the
/// last launch.
///
/// Bounded three ways, all compiled constants (`DiagnosticsLogConstants`): day
/// files older than the retention are deleted, a day file stops growing at its
/// byte cap, and a read returns at most the entry cap. The directory and every
/// file carry the promised file-protection class (docs/SECURITY.md).
public final class FileLogStore: Sendable {
    public let directory: URL
    private let lock = OSAllocatedUnfairLock(initialState: State())

    private struct State {
        var preparedDay: String?
        var dayBytes = 0
        var cappedDay: String?
    }

    public init(directory: URL) {
        self.directory = directory
    }

    /// The production location: `Application Support/Logs`.
    public static func standard() -> FileLogStore? {
        guard let base = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                      appropriateFor: nil, create: true) else { return nil }
        return FileLogStore(directory: base.appendingPathComponent("Logs", isDirectory: true))
    }

    /// Appends one rendered line dated `date`. A write that fails is dropped:
    /// logging never throws into the code that logs.
    public func append(_ text: String, at date: Date) {
        let day = Self.dayName(date)
        let data = Data((text.replacingOccurrences(of: "\n", with: " ") + "\n").utf8)
        lock.withLock { state in
            if state.preparedDay != day {
                prepare(day: day, now: date, state: &state)
            }
            guard state.cappedDay != day else { return }
            if state.dayBytes + data.count > DiagnosticsLogConstants.fileDayByteCap {
                state.cappedDay = day
                return
            }
            let url = fileURL(day: day)
            if let handle = try? FileHandle(forWritingTo: url) {
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
                try? handle.close()
                state.dayBytes += data.count
            }
        }
    }

    /// Deletes day files older than the retention window measured from `now`.
    public func prune(now: Date = Date()) {
        lock.withLock { _ in pruneLocked(now: now) }
    }

    private func prepare(day: String, now: Date, state: inout State) {
        let manager = FileManager.default
        if !manager.fileExists(atPath: directory.path) {
            try? manager.createDirectory(at: directory, withIntermediateDirectories: true)
            FileProtection.protect(directory)
        }
        let url = fileURL(day: day)
        if !manager.fileExists(atPath: url.path) {
            manager.createFile(atPath: url.path, contents: nil)
        }
        FileProtection.protect(url)
        state.preparedDay = day
        state.dayBytes = (try? manager.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        pruneLocked(now: now)
    }

    private func pruneLocked(now: Date) {
        let cutoff = Self.dayName(now.addingTimeInterval(-DiagnosticsLogConstants.fileRetention))
        for day in dayFiles() where day < cutoff {
            try? FileManager.default.removeItem(at: fileURL(day: day))
        }
    }

    private func dayFiles() -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.compactMap { name in
            guard name.hasPrefix(Self.prefix), name.hasSuffix(Self.suffix) else { return nil }
            return String(name.dropFirst(Self.prefix.count).dropLast(Self.suffix.count))
        }.sorted()
    }

    private func fileURL(day: String) -> URL {
        directory.appendingPathComponent(Self.prefix + day + Self.suffix)
    }

    private static let prefix = "tankbook-"
    private static let suffix = ".log"

    /// `yyyy-MM-dd` in UTC - the same clock as every line's timestamp, so a
    /// day file holds exactly the lines whose stamp starts with its name.
    static func dayName(_ date: Date) -> String {
        String(LogRenderer.timestamp(date).prefix(10))
    }
}

extension FileLogStore: OSLogEntryReading {
    /// The lines dated at or after `since`, newest-capped at `limit`, oldest
    /// first. The subsystem is implied - only this app writes here. Throws when
    /// the directory cannot be read, which the bundle reports as
    /// `logStore=unavailable`.
    public func readInfoPlus(subsystem: String, since: Date, limit: Int) throws -> [OSLogCollectedEntry] {
        let days = try lock.withLock { _ -> [String] in
            guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
            _ = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            return dayFiles()
        }
        let sinceStamp = LogRenderer.timestamp(since)
        var matched: [OSLogCollectedEntry] = []
        for day in days where day >= Self.dayName(since) {
            guard let text = try? String(contentsOf: fileURL(day: day), encoding: .utf8) else { continue }
            for line in text.split(separator: "\n") where line.count >= sinceStamp.count {
                let stamp = String(line.prefix(sinceStamp.count))
                guard stamp >= sinceStamp, let date = Self.parse(stamp) else { continue }
                matched.append(OSLogCollectedEntry(date: date, text: String(line)))
            }
        }
        matched.sort { $0.date < $1.date }
        return Array(matched.suffix(limit))
    }

    /// The inverse of `LogRenderer.timestamp`.
    private static func parse(_ stamp: String) -> Date? {
        try? Date.ISO8601FormatStyle.iso8601(timeZone: .gmt, includingFractionalSeconds: true).parse(stamp)
    }
}

/// Writes each line to the day file, rendered with Sensitive values masked in
/// every build (the file outlives the process, unlike a debug console).
/// Debug-level lines are not kept: the file serves the INFO+ bundle.
public struct FileLogSink: LogSink {
    public let store: FileLogStore

    public init(store: FileLogStore) {
        self.store = store
    }

    public func emit(_ line: LogLine) {
        guard line.level != .debug else { return }
        store.append(LogRenderer.render(line, revealSensitive: false), at: line.timestamp)
    }
}

/// Sends every line to each of its sinks in order.
public struct TeeSink: LogSink {
    public let sinks: [any LogSink]

    public init(_ sinks: [any LogSink]) {
        self.sinks = sinks
    }

    public func emit(_ line: LogLine) {
        for sink in sinks {
            sink.emit(line)
        }
    }
}

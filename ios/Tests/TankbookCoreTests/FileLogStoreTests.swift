import Foundation
import Testing
@testable import TankbookCore

/// The on-disk log behind the diagnostics bundle (docs/LOGGING.md §5): it
/// survives a relaunch, keeps a 24 h window, never holds a Sensitive value,
/// and the bundle shows each line once, in time order.
@Suite("On-disk log (DC.1)")
struct FileLogStoreTests {
    private func tempDir() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("dc1-\(UUID().uuidString)")
    }

    private let context = LogContext(deviceId: nil, appVersion: "1.0.0", platform: "ios")

    private func stamp(_ date: Date) -> String { LogRenderer.timestamp(date) }

    @Test("a line written before a relaunch is read after it")
    func linesSurviveARelaunch() throws {
        let directory = tempDir()
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date()
        FileLogStore(directory: directory).append("\(stamp(now.addingTimeInterval(-3600))) INFO [ui] event=first.launch",
                                                  at: now.addingTimeInterval(-3600))
        let relaunched = FileLogStore(directory: directory)
        relaunched.append("\(stamp(now)) INFO [ui] event=second.launch", at: now)

        let lines = try relaunched.readInfoPlus(subsystem: DiagnosticsLogConstants.subsystem,
                                                since: now.addingTimeInterval(-DiagnosticsLogConstants.logWindow),
                                                limit: 100).map(\.text)
        #expect(lines.count == 2)
        #expect(lines.first?.contains("event=first.launch") == true, "the earlier launch's line is kept, and first")
        #expect(lines.last?.contains("event=second.launch") == true)
    }

    @Test("the read is the 24 h window, and prune deletes day files past the retention")
    func windowAndRetention() throws {
        let directory = tempDir()
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date()
        let store = FileLogStore(directory: directory)
        let old = now.addingTimeInterval(-3 * 24 * 3600)
        let yesterdayEarly = now.addingTimeInterval(-30 * 3600)
        store.append("\(stamp(old)) INFO [ui] event=too.old", at: old)
        store.append("\(stamp(yesterdayEarly)) INFO [ui] event=outside.window", at: yesterdayEarly)
        store.append("\(stamp(now)) INFO [ui] event=inside.window", at: now)

        let lines = try store.readInfoPlus(subsystem: "", since: now.addingTimeInterval(-24 * 3600), limit: 100)
            .map(\.text)
        #expect(lines.count == 1)
        #expect(lines.first?.contains("event=inside.window") == true)

        store.prune(now: now)
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(!files.contains("tankbook-\(FileLogStore.dayName(old)).log"), "a day past the retention is deleted")
        #expect(files.contains("tankbook-\(FileLogStore.dayName(yesterdayEarly)).log"), "a day inside it is kept")
    }

    @Test("the read keeps the newest lines when the cap is reached")
    func capKeepsTheNewest() throws {
        let directory = tempDir()
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date()
        let store = FileLogStore(directory: directory)
        for index in 0..<5 {
            let date = now.addingTimeInterval(Double(index - 5))
            store.append("\(stamp(date)) INFO [ui] event=line.\(index)", at: date)
        }
        let lines = try store.readInfoPlus(subsystem: "", since: now.addingTimeInterval(-60), limit: 2).map(\.text)
        #expect(lines.count == 2)
        #expect(lines.first?.contains("event=line.3") == true)
        #expect(lines.last?.contains("event=line.4") == true)
    }

    @Test("the file sink never writes a Sensitive value, in any build")
    func sinkMasksSensitiveValues() throws {
        let directory = tempDir()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileLogStore(directory: directory)
        let log = TankbookLog(sink: FileLogSink(store: store), context: { context }, breadcrumbs: nil)
        log.emit(DC1SensitiveEvent())
        let text = try store.readInfoPlus(subsystem: "", since: Date().addingTimeInterval(-60), limit: 10)
            .map(\.text).joined()
        #expect(text.contains("event=dc1.sensitive"))
        #expect(text.contains("count=2"))
        #expect(!text.contains("Zvezda-Lubricants-77"))
        #expect(text.contains("stationName=<redacted>"))
    }

    @Test("a day file stops growing at its byte cap")
    func dayByteCap() throws {
        let directory = tempDir()
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date()
        let store = FileLogStore(directory: directory)
        let filler = String(repeating: "x", count: 64 * 1_024)
        for _ in 0..<(DiagnosticsLogConstants.fileDayByteCap / filler.count + 4) {
            store.append("\(stamp(now)) INFO [ui] event=filler pad=\(filler)", at: now)
        }
        let url = directory.appendingPathComponent("tankbook-\(FileLogStore.dayName(now)).log")
        let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int ?? 0
        #expect(size <= DiagnosticsLogConstants.fileDayByteCap)
        #expect(size > DiagnosticsLogConstants.fileDayByteCap / 2)
    }

    @Test("the bundle shows each line once, in time order, when the ring and the stored log overlap")
    func bundleMergesRingAndStoredLog() throws {
        let directory = tempDir()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileLogStore(directory: directory)
        let crumbs = Breadcrumbs()
        let log = TankbookLog(sink: FileLogSink(store: store), context: { context }, breadcrumbs: crumbs)
        let started = Date()
        log.emit(DC1Event(eventName: "dc1.first"))
        log.emit(DC1Event(eventName: "dc1.second"))
        log.emit(DC1Event(eventName: "dc1.third"))

        let text = DiagnosticsExport.collect(log: log, context: context, osLog: store,
                                             sync: nil, rowCounts: [:], now: started.addingTimeInterval(1))
            .rendered()
        let logSection = text.components(separatedBy: "--- log ---\n").last?
            .components(separatedBy: "\n").filter { $0.contains("event=dc1.") } ?? []
        #expect(logSection.count == 3, "each emitted line appears once, not once per source: \(logSection)")
        #expect(logSection.map { $0.contains("dc1.first") } == [true, false, false])
        #expect(logSection.last?.contains("dc1.third") == true, "oldest first")
    }
}

private struct DC1Event: LogEvent {
    let eventName: String
    let category = LogCategory.ui
    let level = LogLevel.info
    let fields: [LogField] = []
}

private struct DC1SensitiveEvent: LogEvent {
    let eventName = "dc1.sensitive"
    let category = LogCategory.capture
    let level = LogLevel.info
    let fields: [LogField] = [.sensitive("stationName", "Zvezda-Lubricants-77"), .safe("count", "2")]
}

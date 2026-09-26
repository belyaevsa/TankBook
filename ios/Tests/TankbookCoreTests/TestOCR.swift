import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import TankbookCore

/// Vision OCR for the tests: `VisionTextRecognizer`'s three entry points with a
/// retry on one failure only - the Core ML runtime's `e5rtError`, which the full
/// parallel suite provokes when many suites run Vision and Core ML models at
/// once (RV.306: every failing test passes run alone). Any other error is
/// rethrown at once, and the app's own path keeps its single attempt.
enum TestOCR {
    static let attempts = 3

    /// `VISION_SERIAL=1` - set by `scripts/vision-suites.sh` - runs one OCR at a
    /// time, the way a phone reads one photo. In the iOS simulator concurrent
    /// requests read some receipts differently from a lone one (`receipt-083`
    /// read alone is the same every time; inside the parallel suite it varied
    /// run to run), so the measured runtime's marks are taken one at a time.
    static let serial = ProcessInfo.processInfo.environment["VISION_SERIAL"] == "1"
    private static let lock = SerialLock()

    static func recognizeText(in url: URL, languages: [String]) async throws -> [OCRLine] {
        try await retrying { try await VisionTextRecognizer.recognizeText(in: url, languages: languages) }
    }

    static func recognizeText(image: CGImage, languages: [String]) async throws -> [OCRLine] {
        try await retrying { try await VisionTextRecognizer.recognizeText(image: image, languages: languages) }
    }

    static func recognizeText(image: CGImage, orientation: CGImagePropertyOrientation,
                              languages: [String]) async throws -> [OCRLine] {
        try await retrying {
            try await VisionTextRecognizer.recognizeText(image: image, orientation: orientation, languages: languages)
        }
    }

    static func isRuntimeContention(_ error: Error) -> Bool {
        String(describing: error).contains("e5rt")
    }

    static func retrying(_ body: () async throws -> [OCRLine]) async throws -> [OCRLine] {
        guard serial else { return try await retryingConcurrently(body) }
        await lock.acquire()
        do {
            let lines = try await retryingConcurrently(body)
            await lock.release()
            return lines
        } catch {
            await lock.release()
            throw error
        }
    }

    private static func retryingConcurrently(_ body: () async throws -> [OCRLine]) async throws -> [OCRLine] {
        var attempt = 1
        while true {
            do {
                return try await body()
            } catch where isRuntimeContention(error) && attempt < attempts {
                attempt += 1
                try await Task.sleep(for: .milliseconds(200 * attempt))
            }
        }
    }
}

@Suite("the tests' OCR retry")
struct TestOCRRetryTests {
    private struct RuntimeFailure: Error, CustomStringConvertible {
        var description: String { "e5rtError(\"e5rt_stream_completion_handler call failed\", 10)" }
    }
    private struct OtherFailure: Error {}

    @Test("a runtime contention failure is retried; any other error is not")
    func retriesOnlyRuntimeContention() async throws {
        var calls = 0
        let lines = try await TestOCR.retrying {
            calls += 1
            if calls < TestOCR.attempts { throw RuntimeFailure() }
            return [OCRLine(text: "ok")]
        }
        #expect(lines.map(\.text) == ["ok"] && calls == TestOCR.attempts)

        var otherCalls = 0
        await #expect(throws: OtherFailure.self) {
            _ = try await TestOCR.retrying { otherCalls += 1; throw OtherFailure() }
        }
        #expect(otherCalls == 1)

        var exhausted = 0
        await #expect(throws: RuntimeFailure.self) {
            _ = try await TestOCR.retrying { exhausted += 1; throw RuntimeFailure() }
        }
        #expect(exhausted == TestOCR.attempts)
    }
}

/// A one-holder async lock: `acquire` suspends until the holder releases.
private actor SerialLock {
    private var held = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        guard held else {
            held = true
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        if waiters.isEmpty {
            held = false
        } else {
            waiters.removeFirst().resume()
        }
    }
}

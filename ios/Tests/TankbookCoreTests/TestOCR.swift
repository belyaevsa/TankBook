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

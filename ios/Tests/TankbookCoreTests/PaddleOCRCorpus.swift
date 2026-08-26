import CoreGraphics
import Foundation
@testable import TankbookCore

// P4.13 - PaddleOCR coordinate normalisation and the raw/result file shapes the
// two PaddleOCR arms use. Kept in the test target next to `CorpusABScorer` for
// the same reason: the converter and the offline scoring live together, and CI
// never needs a container or a model to run any of it.

// MARK: - The coordinate conversion (the load-bearing part)

/// PaddleOCR returns boxes as `[x0, y0, x1, y1]` in **pixel** coordinates with a
/// **top-left origin** (y increases downward). `OCRLine` documents its bounding
/// box as Vision's **normalised** space with a **bottom-left origin** (y
/// increases upward), and `VisionTextRecognizer` sorts descending by `midY` to
/// read top-to-bottom.
///
/// A naive `y = y_px / height` inverts the page and silently breaks the parser's
/// geometric rules: `loneMarkers` finds the price "directly below its /L label"
/// via `line.midY - other.midY > 0`, the labelled-column rule compares `midX`
/// against a header's `midX`, and `OperandPair.first` takes the first operand
/// line in document order. The right mapping is `x/width` and
/// `y_norm = 1 - (y_px / height)` with the rect origin at its bottom edge, then
/// sort descending by `midY`. That is exactly what `receipt-001` calibration
/// asserts.
enum PaddleOCRCoordinate {
    static func visionBox(paddleBox: [Double], width: Double, height: Double) -> CGRect {
        guard paddleBox.count >= 4 else { return .zero }
        let minX = paddleBox[0]
        let minY = paddleBox[1]
        let maxX = paddleBox[2]
        let maxY = paddleBox[3]
        // The rect's origin in Vision space is its BOTTOM-left corner, so its
        // Vision y is the pixel maxY flipped: 1 - maxY/height.
        return CGRect(
            x: minX / width,
            y: 1.0 - maxY / height,
            width: (maxX - minX) / width,
            height: (maxY - minY) / height
        )
    }

    static func line(_ raw: PaddleOCRRawLine, width: Double, height: Double) -> OCRLine {
        OCRLine(
            text: raw.text,
            confidence: Float(raw.score ?? 0),
            boundingBox: visionBox(paddleBox: raw.box ?? [0, 0, 0, 0], width: width, height: height)
        )
    }

    /// Convert a run's lines to Vision-order `[OCRLine]`, sorted descending by
    /// `midY` exactly as `VisionTextRecognizer` sorts (top-to-bottom).
    static func lines(from raw: [PaddleOCRRawLine], width: Double, height: Double) -> [OCRLine] {
        raw.map { line($0, width: width, height: height) }
            .sorted { $0.boundingBox.midY > $1.boundingBox.midY }
    }
}

// MARK: - Raw sweep files (gitignored; the sweep writes them, the dump reads them)

/// One recognized line in PaddleOCR's output: text, confidence, pixel box.
struct PaddleOCRRawLine: Codable, Equatable {
    let text: String
    let score: Double?
    let box: [Double]?
}

/// One run over one image: latency plus the recognised lines (Arm A) or text
/// lines (Arm B). `width`/`height` are the pixel dimensions the boxes refer to.
struct PaddleOCRRawRun: Codable {
    let latencySeconds: Double?
    let width: Double?
    let height: Double?
    let lines: [PaddleOCRRawLine]?
    let textLines: [String]?
}

struct PaddleOCRRawEntry: Codable {
    let filename: String
    let runs: [PaddleOCRRawRun]
    let error: String?
}

struct PaddleOCRRawFile: Codable {
    let engine: String
    let className: String
    let generated: String
    let entries: [PaddleOCRRawEntry]

    var entriesByFilename: [String: PaddleOCRRawEntry] {
        Dictionary(entries.map { ($0.filename, $0) }, uniquingKeysWith: { first, _ in first })
    }
}

/// The committed calibration fixture for `receipt-001`: one image's Arm A lines,
/// so the coordinate conversion is proven against real PaddleOCR boxes without
/// a container.
struct PaddleOCRCalibrationFixture: Codable {
    let engine: String
    let className: String
    let generated: String
    let width: Double
    let height: Double
    let lines: [PaddleOCRRawLine]
}

// MARK: - The three-run variance files (committed)

/// One run's extracted fields plus its latency.
struct PaddleOCRRunRecord: Codable, Equatable {
    let liters: Double?
    let unitPrice: Double?
    let total: Double?
    let latencySeconds: Double?
}

/// Per-image three-run record. The three runs disagreeing for an image is
/// recorded here, not averaged away - exactly the trap the P4.12 cloud arm fell
/// into by sampling once.
struct PaddleOCRVarianceEntry: Codable {
    let filename: String
    let runs: [PaddleOCRRunRecord]
}

struct PaddleOCRVarianceFile: Codable {
    let engine: String
    let className: String
    let generated: String
    let entries: [PaddleOCRVarianceEntry]

    var entriesByFilename: [String: PaddleOCRVarianceEntry] {
        Dictionary(entries.map { ($0.filename, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// The filenames whose three runs disagree on at least one field (within the
    /// shared scorer tolerance). Empty means the arm is deterministic.
    func disagreeingFilenames(tolerance: Double) -> [String] {
        entries.compactMap { entry in
            guard entry.runs.count >= 2 else { return nil }
            let first = entry.runs[0]
            for run in entry.runs.dropFirst() {
                if !Self.agree(first.liters, run.liters, tolerance)
                    || !Self.agree(first.unitPrice, run.unitPrice, tolerance)
                    || !Self.agree(first.total, run.total, tolerance) {
                    return entry.filename
                }
            }
            return nil
        }
    }

    private static func agree(_ a: Double?, _ b: Double?, _ tolerance: Double) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case let (x?, y?): return abs(x - y) < tolerance
        default: return false
        }
    }
}

// MARK: - Shared helpers

enum PaddleOCRCorpus {
    static func repoRoot(from filePath: String = #filePath) -> URL {
        URL(fileURLWithPath: filePath).standardizedFileURL
            .deletingLastPathComponent() // TankbookCoreTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // ios
            .deletingLastPathComponent() // repo root
    }

    static var fixturesRoot: URL { repoRoot().appendingPathComponent("Spike/ReceiptSpike/fixtures") }
    static var abRoot: URL { fixturesRoot.appendingPathComponent("vision-ab") }

    /// Arm A: run the deterministic parser over PaddleOCR lines with the Vision
    /// coordinate conversion. The whole point of Arm A is this exact call path.
    static func extractArmA(_ run: PaddleOCRRawRun) -> FuelExtraction {
        guard let lines = run.lines, let width = run.width, let height = run.height else {
            return FuelExtraction()
        }
        let ocrLines = PaddleOCRCoordinate.lines(from: lines, width: width, height: height)
        return FuelExtractor().extract(lines: ocrLines)
    }

    /// Arm B: PaddleOCR-VL produces text (markdown), not boxes - feed its text
    /// lines through the parser's pure-text path (zero boxes, reading-order
    /// fallback). Same parser, same scorer, different reader.
    static func extractArmB(_ run: PaddleOCRRawRun) -> FuelExtraction {
        guard let textLines = run.lines?.map(\.text) ?? run.textLines else { return FuelExtraction() }
        return FuelExtractor().extract(textLines: textLines)
    }
}

import CoreML
import CoreVideo
import Foundation

/// The seven-segment glyph classifier: a Core ML model that maps one sliced
/// cell to eight segment probabilities (a-g and the decimal point), and the
/// decoder that turns those into a digit.
///
/// The decoder searches only the patterns a display can show, ranked by
/// likelihood - never a per-bit threshold, which can emit a pattern no glyph
/// has (`docs/EXTRACTION.md` -> "The pump reader"). The same rule lives in
/// `ml/pump-reader/src/pump_reader/glyph.py`; the two must agree.
struct PumpSegmentsModel {
    static let inputWidth = 32
    static let inputHeight = 48

    /// Segment bits, `a` = bit 0 ... `g` = bit 6, `dp` = bit 7.
    static let digitPatterns: [(digit: Character, bits: UInt8)] = [
        ("0", 0b0111111), ("1", 0b0000110), ("2", 0b1011011), ("3", 0b1001111),
        ("4", 0b1100110), ("5", 0b1101101), ("6", 0b1111101), ("7", 0b0000111),
        ("8", 0b1111111), ("9", 0b1101111),
    ]

    struct Read: Equatable {
        let digit: Character
        let decimalPoint: Bool
        /// Log-likelihood gap to the runner-up digit; the abstention signal.
        let margin: Double
        let probabilities: [Double]
    }

    private let model: MLModel

    /// Loads a compiled model (`.mlmodelc`) or compiles an `.mlpackage` first.
    init(contentsOf url: URL) throws {
        let compiled = url.pathExtension == "mlmodelc" ? url : try MLModel.compileModel(at: url)
        model = try MLModel(contentsOf: compiled)
    }

    /// The eight segment probabilities for a cell already resampled to 32x48.
    func probabilities(cell: PumpRGBImage) throws -> [Double] {
        precondition(cell.width == Self.inputWidth && cell.height == Self.inputHeight)
        let buffer = try Self.pixelBuffer(from: cell)
        let input = try MLDictionaryFeatureProvider(dictionary: [
            "glyph": MLFeatureValue(pixelBuffer: buffer),
        ])
        let output = try model.prediction(from: input)
        guard let array = output.featureValue(for: "segments")?.multiArrayValue else {
            throw PumpSegmentsModelError.missingOutput
        }
        return (0..<8).map { array[[0, $0] as [NSNumber]].doubleValue }
    }

    func read(cell: PumpRGBImage) throws -> Read {
        Self.decode(try probabilities(cell: cell))
    }

    /// All ten digits ranked by log-likelihood under the segment probabilities.
    static func rank(_ probabilities: [Double]) -> [PumpGlyphCandidate] {
        let clamped = probabilities.prefix(7).map { min(max($0, 1e-6), 1 - 1e-6) }
        var scored: [PumpGlyphCandidate] = digitPatterns.map { pattern in
            var ll = 0.0
            for i in 0..<7 {
                let on = (pattern.bits >> UInt8(i)) & 1 == 1
                ll += on ? log(clamped[i]) : log(1 - clamped[i])
            }
            return PumpGlyphCandidate(digit: Int(String(pattern.digit))!, logPosterior: ll)
        }
        scored.sort { $0.logPosterior > $1.logPosterior }
        return scored
    }

    /// The most likely digit over the valid patterns; blank is the slicer's call.
    static func decode(_ probabilities: [Double]) -> Read {
        let ranked = rank(probabilities)
        return Read(
            digit: Character(String(ranked[0].digit)),
            decimalPoint: probabilities.count > 7 && probabilities[7] >= 0.5,
            margin: ranked[0].logPosterior - ranked[1].logPosterior,
            probabilities: probabilities)
    }

    private static func pixelBuffer(from cell: PumpRGBImage) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault, cell.width, cell.height, kCVPixelFormatType_32BGRA, nil, &buffer)
        guard status == kCVReturnSuccess, let pixelBuffer = buffer else {
            throw PumpSegmentsModelError.pixelBuffer(status)
        }
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            throw PumpSegmentsModelError.pixelBuffer(status)
        }
        let stride = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let dst = base.assumingMemoryBound(to: UInt8.self)
        for y in 0..<cell.height {
            for x in 0..<cell.width {
                let src = (y * cell.width + x) * 4
                let out = y * stride + x * 4
                dst[out] = cell.pixels[src + 2]      // B
                dst[out + 1] = cell.pixels[src + 1]  // G
                dst[out + 2] = cell.pixels[src]      // R
                dst[out + 3] = 255
            }
        }
        return pixelBuffer
    }
}

enum PumpSegmentsModelError: Error {
    case missingOutput
    case pixelBuffer(CVReturn)
}

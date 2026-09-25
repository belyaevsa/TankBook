import CoreML
import Foundation

/// A row-level sequence reader: a CRNN trained with CTC
/// (`ml/pump-reader/src/pump_reader/rowreader.py`) reads a whole number
/// window's strip at once, so no slicer decides how many cells the row has.
/// The decoding is the Python reference's: prefix beam search over the
/// per-frame distributions for the string, then for every digit position the
/// substitution marginal - the likelihood of the decoded string with that
/// digit replaced by each of the ten, normalised - as the cell's ranking, and
/// the probability that a separator follows it as the cell's decimal mark.
struct PumpRowReader: @unchecked Sendable {
    static let height = 32
    static let minimumWidth = 100
    static let maximumWidth = 160
    static let blank = 0
    static let separator = 11
    static let classCount = 12
    /// Prefixes kept per frame; the reference's width.
    static let beamWidth = 32

    private let model: MLModel

    init(contentsOf url: URL) throws {
        let compiled = url.pathExtension == "mlmodelc" ? url : try MLModel.compileModel(at: url)
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .cpuAndNeuralEngine
        model = try MLModel(contentsOf: compiled, configuration: configuration)
    }

    /// The window's cells, one per decoded digit, or nil when the strip
    /// decodes to no digit at all.
    func read(strip: PumpRGBImage) throws -> [PumpCellReading]? {
        let logProbs = try frames(strip: strip)
        let tokens = Self.prefixSearch(logProbs)
        let cells = Self.posteriors(logProbs, tokens: tokens)
        return cells.isEmpty ? nil : cells
    }

    /// Per-frame log-probabilities over the twelve classes.
    func frames(strip: PumpRGBImage) throws -> [[Double]] {
        let input = Self.input(strip)
        let array = try MLMultiArray(shape: [1, 3, NSNumber(value: Self.height), NSNumber(value: input.width)],
                                     dataType: .float32)
        let plane = Self.height * input.width
        let pointer = array.dataPointer.bindMemory(to: Float.self, capacity: 3 * plane)
        for i in 0..<plane {
            for c in 0..<3 { pointer[c * plane + i] = Float(input.rgb[i * 3 + c]) / 255 }
        }
        let provider = try MLDictionaryFeatureProvider(dictionary: ["strip": MLFeatureValue(multiArray: array)])
        guard let out = try model.prediction(from: provider).featureValue(for: "logprobs")?.multiArrayValue
        else { return [] }
        let count = out.shape[0].intValue
        return (0..<count).map { t in
            (0..<Self.classCount).map { c in out[[NSNumber(value: t), NSNumber(value: c)]].doubleValue }
        }
    }

    // MARK: - Input

    /// The strip at the model's height with its aspect kept, capped at the
    /// maximum width and right-padded with its own edge column to the minimum:
    /// RGB bytes, row-major.
    static func input(_ strip: PumpRGBImage) -> (rgb: [UInt8], width: Int) {
        let scaled = (Double(strip.width) * Double(height) / Double(strip.height)).rounded(.toNearestOrEven)
        let width = min(max(1, Int(scaled)), maximumWidth)
        var rgb = [UInt8](repeating: 0, count: strip.width * strip.height * 3)
        for i in 0..<(strip.width * strip.height) {
            for c in 0..<3 { rgb[i * 3 + c] = strip.pixels[i * 4 + c] }
        }
        let resized = resize(rgb, width: strip.width, height: strip.height, toWidth: width, toHeight: height)
        guard width < minimumWidth else { return (resized, width) }
        var padded = [UInt8](repeating: 0, count: minimumWidth * height * 3)
        for y in 0..<height {
            for x in 0..<minimumWidth {
                let source = min(x, width - 1)
                for c in 0..<3 { padded[(y * minimumWidth + x) * 3 + c] = resized[(y * width + source) * 3 + c] }
            }
        }
        return (padded, minimumWidth)
    }

    /// Bilinear resampling as the training pipeline's Pillow does it: a
    /// triangle filter widened by the scale when shrinking, 22-bit fixed-point
    /// weights, the horizontal pass first and each pass rounded to 8 bits.
    /// Matching it keeps the phone's strips the pixels the model trained on.
    static func resize(_ rgb: [UInt8], width: Int, height: Int, toWidth: Int, toHeight: Int) -> [UInt8] {
        var current = rgb, w = width
        if toWidth != width {
            let k = coefficients(inSize: width, outSize: toWidth)
            var out = [UInt8](repeating: 0, count: toWidth * height * 3)
            for y in 0..<height {
                for x in 0..<toWidth {
                    for c in 0..<3 {
                        var sum = 1 << (precisionBits - 1)
                        for (j, weight) in k.weights[x].enumerated() {
                            sum += Int(current[(y * w + k.start[x] + j) * 3 + c]) * weight
                        }
                        out[(y * toWidth + x) * 3 + c] = clip8(sum)
                    }
                }
            }
            current = out
            w = toWidth
        }
        guard toHeight != height else { return current }
        let k = coefficients(inSize: height, outSize: toHeight)
        var out = [UInt8](repeating: 0, count: w * toHeight * 3)
        for y in 0..<toHeight {
            for x in 0..<w {
                for c in 0..<3 {
                    var sum = 1 << (precisionBits - 1)
                    for (j, weight) in k.weights[y].enumerated() {
                        sum += Int(current[((k.start[y] + j) * w + x) * 3 + c]) * weight
                    }
                    out[(y * w + x) * 3 + c] = clip8(sum)
                }
            }
        }
        return out
    }

    private static let precisionBits = 22

    private static func clip8(_ value: Int) -> UInt8 {
        UInt8(clamping: value >> precisionBits)
    }

    private static func coefficients(inSize: Int, outSize: Int) -> (start: [Int], weights: [[Int]]) {
        let scale = Double(inSize) / Double(outSize)
        let filterScale = max(scale, 1)
        let support = filterScale
        var starts: [Int] = [], weights: [[Int]] = []
        for x in 0..<outSize {
            let center = (Double(x) + 0.5) * scale
            let low = max(Int(center - support + 0.5), 0)
            let count = min(Int(center + support + 0.5), inSize) - low
            var k = (0..<count).map { i -> Double in
                let t = abs((Double(i + low) - center + 0.5) / filterScale)
                return t < 1 ? 1 - t : 0
            }
            let total = k.reduce(0, +)
            if total != 0 { k = k.map { $0 / total } }
            starts.append(low)
            weights.append(k.map { w in
                let v = w * Double(1 << precisionBits)
                return Int(w < 0 ? (-0.5 + v).rounded(.towardZero) : (0.5 + v).rounded(.towardZero))
            })
        }
        return (starts, weights)
    }

    // MARK: - Decoding

    static func logAdd(_ a: Double, _ b: Double) -> Double {
        if a == -.infinity { return b }
        if b == -.infinity { return a }
        let m = max(a, b)
        return m + log(exp(a - m) + exp(b - m))
    }

    /// CTC prefix beam search: each prefix keeps the mass of its paths ending
    /// in a blank and in a symbol, so a repeated digit needs a blank between.
    /// Ties keep the order prefixes were first reached, as the reference does.
    static func prefixSearch(_ logProbs: [[Double]]) -> [Int] {
        var prefixes: [[Int]] = [[]]
        var blanks: [Double] = [0], symbols: [Double] = [-.infinity]
        for lp in logProbs {
            var index: [[Int]: Int] = [:]
            var nextPrefixes: [[Int]] = [], nextBlanks: [Double] = [], nextSymbols: [Double] = []
            func add(_ prefix: [Int], blank: Double, symbol: Double) {
                if let k = index[prefix] {
                    nextBlanks[k] = logAdd(nextBlanks[k], blank)
                    nextSymbols[k] = logAdd(nextSymbols[k], symbol)
                } else {
                    index[prefix] = nextPrefixes.count
                    nextPrefixes.append(prefix)
                    nextBlanks.append(blank)
                    nextSymbols.append(symbol)
                }
            }
            for b in prefixes.indices {
                let prefix = prefixes[b], pb = blanks[b], pnb = symbols[b]
                let total = logAdd(pb, pnb)
                add(prefix, blank: total + lp[blank], symbol: -.infinity)
                for c in 1..<classCount {
                    if prefix.last == c {
                        add(prefix + [c], blank: -.infinity, symbol: pb + lp[c])
                        add(prefix, blank: -.infinity, symbol: pnb + lp[c])
                    } else {
                        add(prefix + [c], blank: -.infinity, symbol: total + lp[c])
                    }
                }
            }
            let scores = nextPrefixes.indices.map { logAdd(nextBlanks[$0], nextSymbols[$0]) }
            let kept = nextPrefixes.indices.sorted { scores[$0] != scores[$1] ? scores[$0] > scores[$1] : $0 < $1 }
                .prefix(beamWidth)
            prefixes = kept.map { nextPrefixes[$0] }
            blanks = kept.map { nextBlanks[$0] }
            symbols = kept.map { nextSymbols[$0] }
        }
        guard let best = prefixes.indices.max(by: { logAdd(blanks[$0], symbols[$0]) < logAdd(blanks[$1], symbols[$1]) })
        else { return [] }
        return prefixes[best]
    }

    /// ln p(label | frames) by the CTC forward recursion.
    static func logLikelihood(_ logProbs: [[Double]], label: [Int]) -> Double {
        guard !logProbs.isEmpty else { return -.infinity }
        var ext = [blank]
        for token in label { ext += [token, blank] }
        var alpha = [Double](repeating: -.infinity, count: ext.count)
        var prev = alpha
        alpha[0] = logProbs[0][ext[0]]
        if ext.count > 1 { alpha[1] = logProbs[0][ext[1]] }
        for t in 1..<logProbs.count {
            swap(&alpha, &prev)
            let row = logProbs[t]
            for s in 0..<ext.count {
                var a = prev[s]
                if s >= 1 { a = logAdd(a, prev[s - 1]) }
                if s >= 2, ext[s] != blank, ext[s] != ext[s - 2] { a = logAdd(a, prev[s - 2]) }
                alpha[s] = a + row[ext[s]]
            }
        }
        return ext.count > 1 ? logAdd(alpha[ext.count - 1], alpha[ext.count - 2]) : alpha[0]
    }

    /// One cell per decoded digit: the ten digits ranked by their normalised
    /// substitution likelihood, and a decimal mark when a separator after the
    /// digit is more likely than not.
    static func posteriors(_ logProbs: [[Double]], tokens: [Int]) -> [PumpCellReading] {
        tokens.indices.filter { tokens[$0] != separator }.map { i in
            let scores = (0..<10).map { d -> Double in
                var variant = tokens
                variant[i] = d + 1
                return logLikelihood(logProbs, label: variant)
            }
            let z = scores.reduce(-Double.infinity, logAdd)
            let ranked = (0..<10).map { PumpGlyphCandidate(digit: $0, logPosterior: scores[$0] - z) }
                .sorted { $0.logPosterior > $1.logPosterior }
            var with = tokens, without = tokens
            if i + 1 < tokens.count, tokens[i + 1] == separator {
                without.remove(at: i + 1)
            } else {
                with.insert(separator, at: i + 1)
            }
            let a = logLikelihood(logProbs, label: with)
            let b = logLikelihood(logProbs, label: without)
            let mark = a.isFinite ? 1 / (1 + exp(min(50, b - a))) : 0
            return PumpCellReading(probabilities: [], ranked: ranked, decimalPoint: mark >= 0.5)
        }
    }
}

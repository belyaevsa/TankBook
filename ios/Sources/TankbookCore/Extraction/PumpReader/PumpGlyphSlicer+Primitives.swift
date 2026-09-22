import Foundation

// The slicer's numeric primitives: the pitch, the runs, the thresholds and the
// circular mean. Split out of `PumpGlyphSlicer.swift` so its type body stays
// under the lint limit; the members are the same and stay on the type.
extension PumpGlyphSlicer {

    // MARK: - Pitch via autocorrelation

    static func autocorrelationPitch(_ profile: [Float], minLag: Int, maxLag: Int) -> Int? {
        let count = profile.count
        guard count > maxLag, maxLag >= minLag else { return nil }
        let mean = profile.reduce(0, +) / Float(count)
        let centered = profile.map { $0 - mean }
        var energy: Float = 0
        for value in centered { energy += value * value }
        guard energy > 0 else { return nil }
        let lags = Array(minLag...min(maxLag, count - 1))
        var values: [Float] = []
        values.reserveCapacity(lags.count)
        for lag in lags {
            var value: Float = 0
            for i in 0..<(count - lag) {
                value += centered[i] * centered[i + lag]
            }
            values.append(value / energy)
        }
        guard let bestValue = values.max() else { return nil }
        // The profile of a digit row repeats at the pitch AND at every multiple
        // of it, and the doubled lag often carries the higher peak (a decimal
        // mark or a dim `1` every other cell weakens the fundamental). Take the
        // shortest local peak that is nearly as strong as the strongest, so the
        // fundamental wins over its harmonic; measured on the train export the
        // harmonic halved the count on 954 of 8 527 windows.
        for (i, lag) in lags.enumerated() where values[i] >= harmonicTolerance * bestValue {
            let before = i == 0 ? -.greatestFiniteMagnitude : values[i - 1]
            let after = i + 1 < values.count ? values[i + 1] : -.greatestFiniteMagnitude
            if values[i] >= before && values[i] >= after { return lag }
        }
        return lags[values.firstIndex(of: bestValue)!]
    }

    /// How close to the strongest autocorrelation peak a shorter peak must be
    /// to be taken as the fundamental pitch.
    static let harmonicTolerance: Float = 0.6

    // MARK: - Primitives

    static func runs(in profile: [Float], threshold: Float, mergeGap: Int) -> [Run] {
        var result: [Run] = []
        var i = 0
        while i < profile.count {
            guard profile[i] > threshold else { i += 1; continue }
            let start = i
            var end = i
            while end < profile.count && profile[end] > threshold { end += 1 }
            let runEnd = end - 1
            if let last = result.last, start - last.end <= mergeGap {
                result[result.count - 1].end = runEnd
            } else {
                result.append(Run(start: start, end: runEnd, isDecimalPoint: false))
            }
            i = end + 1
        }
        return result
    }

    static func topInkRow(
        _ run: Run, ink: [Float], width: Int, bandTop: Int, bandBottom: Int, threshold: Float
    ) -> Int? {
        for y in bandTop...bandBottom {
            for x in run.start...run.end where ink[y * width + x] > threshold {
                return y
            }
        }
        return nil
    }

    static func boxFilter(_ values: [Float], radius: Int) -> [Float] {
        let count = values.count
        guard radius > 0, count > 0 else { return values }
        var prefix = [Float](repeating: 0, count: count + 1)
        for i in 0..<count { prefix[i + 1] = prefix[i] + values[i] }
        var out = [Float](repeating: 0, count: count)
        for i in 0..<count {
            let left = max(0, i - radius)
            let right = min(count - 1, i + radius)
            out[i] = (prefix[right + 1] - prefix[left]) / Float(right - left + 1)
        }
        return out
    }

    static func otsuThreshold(_ values: [Float]) -> Float {
        let count = values.count
        guard count > 1, let lo = values.min(), let hi = values.max(), hi > lo else {
            return values.max() ?? 0
        }
        let bins = 256
        var hist = [Float](repeating: 0, count: bins)
        let scale = Float(bins - 1) / (hi - lo)
        for value in values {
            var index = Int(((value - lo) * scale).rounded())
            index = max(0, min(bins - 1, index))
            hist[index] += 1
        }
        let binCenters = (0..<bins).map { lo + Float($0) * (hi - lo) / Float(bins - 1) }
        var prefixCount = [Float](repeating: 0, count: bins)
        var prefixSum = [Float](repeating: 0, count: bins)
        for i in 0..<bins {
            prefixCount[i] = (i > 0 ? prefixCount[i - 1] : 0) + hist[i]
            prefixSum[i] = (i > 0 ? prefixSum[i - 1] : 0) + hist[i] * binCenters[i]
        }
        let total = Float(count)
        let totalSum = prefixSum[bins - 1]
        var best: Float = -1
        var bestThreshold = lo
        for i in 0..<(bins - 1) {
            let weight1 = prefixCount[i]
            let weight2 = total - weight1
            guard weight1 > 0, weight2 > 0 else { continue }
            let mean1 = prefixSum[i] / weight1
            let mean2 = (totalSum - prefixSum[i]) / weight2
            let between = weight1 * weight2 * (mean1 - mean2) * (mean1 - mean2)
            if between > best {
                best = between
                bestThreshold = binCenters[i]
            }
        }
        return bestThreshold
    }

    static func percentile(_ values: [Float], _ p: Float) -> Float {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let index = min(sorted.count - 1, Int((Float(sorted.count - 1) * p).rounded()))
        return sorted[index]
    }

    /// One sort for the three percentiles: sorting the strip's pixels was 45 %
    /// of the whole live read (Time Profiler, 2026-09-21), and it was sorted
    /// three times here. Exactly the values `percentile` gives.
    static func percentiles(_ values: [Float]) -> (p05: Float, p50: Float, p95: Float) {
        guard !values.isEmpty else { return (0, 0, 0) }
        let sorted = values.sorted()
        func at(_ p: Float) -> Float { sorted[min(sorted.count - 1, Int((Float(sorted.count - 1) * p).rounded()))] }
        return (at(0.05), at(0.50), at(0.95))
    }

    static func circularMean(_ values: [Double], period: Double) -> Double {
        guard !values.isEmpty, period > 0 else { return 0 }
        var sx = 0.0
        var sy = 0.0
        for value in values {
            let angle = 2 * Double.pi * value / period
            sx += cos(angle)
            sy += sin(angle)
        }
        var mean = atan2(sy, sx) * period / (2 * Double.pi)
        if mean < 0 { mean += period }
        return mean
    }
}

import Foundation

/// The fast Hough transform for mostly horizontal lines (Brady & Yong 1992;
/// Brady, SIAM J. Comput. 1998): for every slope `t` in `0..<n` of an image `n`
/// columns wide, the sums of the image along dyadic staircase patterns that rise
/// `t` rows across the width, at every vertical offset - all slopes from one
/// recursive pass of `O(n^2 log n)` additions. Row `t` of the result is the
/// image's projection profile at that slope, so a profile criterion can be
/// scored at every angle at once (Bezmaternykh & Nikolaev, arXiv:1912.02504).
enum PumpFastHough {
    /// The transform of `image` (`height` rows x `width` columns, row-major),
    /// zero-padded to a power-of-two width and to `height + width` rows so the
    /// patterns' shifts never wrap onto real pixels. Returns the padded width
    /// `n` and the accumulator, `n` slopes x `rows` offsets, row-major by slope:
    /// slope `t` rises `t` rows over the `n` columns (y grows with x).
    static func transform(_ image: [Float], width: Int, height: Int) -> (n: Int, rows: Int, sums: [Float]) {
        var n = 1
        while n < max(width, 1) { n *= 2 }
        let rows = height + n
        // Columns as vectors over the padded rows.
        var columns = [[Float]](repeating: [Float](repeating: 0, count: rows), count: n)
        for x in 0..<min(width, n) {
            for y in 0..<height { columns[x][y] = image[y * width + x] }
        }
        let result = merge(columns[...], rows: rows)
        return (n, rows, result.flatMap { $0 })
    }

    /// The Brady-Yong recursion over a run of columns: each half's slopes are
    /// computed alone, and slope `t` of the whole is the left half's slope
    /// `t / 2` plus the right half's slope `t / 2` shifted down by the rows the
    /// line has risen across the left half, `t - t / 2`.
    private static func merge(_ columns: ArraySlice<[Float]>, rows: Int) -> [[Float]] {
        let width = columns.count
        if width == 1 { return [columns[columns.startIndex]] }
        let half = width / 2
        let left = merge(columns.prefix(half), rows: rows)
        let right = merge(columns.suffix(width - half), rows: rows)
        var out = [[Float]](repeating: [Float](repeating: 0, count: rows), count: width)
        for t in 0..<width {
            let inner = t / 2, shift = t - inner
            let l = left[inner], r = right[inner]
            for y in 0..<(rows - shift) { out[t][y] = l[y] + r[y + shift] }
            for y in (rows - shift)..<rows { out[t][y] = l[y] }
        }
        return out
    }
}

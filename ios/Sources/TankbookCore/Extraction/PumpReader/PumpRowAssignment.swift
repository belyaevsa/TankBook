import CoreGraphics
import Foundation

/// Which located window is the total, the volume and the price - from geometry
/// alone, before any digit is read.
///
/// Measured on the corpus (114 heads, agents/reviews/PU.14-REVIEW-DECODE-DESIGN.md §3):
/// every head stacks the transaction column top-down as total, volume, price;
/// a grade-price board is a row of three or four near-equal windows on one
/// baseline, and on Wayne heads the transaction price lives only there. So the
/// rule is: take the boards out, sort what is left by their vertical centre,
/// and read the column top-down.
enum PumpRowAssignment {
    struct Window {
        /// TL, TR, BR, BL in the oriented image's pixels.
        let quad: [CGPoint]
        let glyphCount: Int
    }

    struct Assignment: Equatable {
        /// One role per input window, in input order.
        let roles: [PumpField?]
    }

    /// Boards: windows whose vertical centres lie within this fraction of
    /// their height of each other, and whose widths agree within `boardWidthTolerance`.
    static let boardBaselineTolerance: CGFloat = 0.9
    static let boardWidthTolerance: CGFloat = 0.45
    static let boardMinimumWindows = 3

    /// The fewest cells a field can show with its decimals: `0.50` is three.
    static let minimumCells: [PumpField: Int] = [.total: 3, .liters: 3, .unitPrice: 3]

    static func assign(windows: [Window], rotationCW: Int) -> Assignment {
        guard !windows.isEmpty else { return Assignment(roles: []) }
        let ordered = windows.map { PumpQuadWarp.readingOrder($0.quad, rotationCW: rotationCW) }
        let boxes = ordered.map { Self.bounds($0, rotationCW: rotationCW) }

        var roles = [PumpField?](repeating: nil, count: windows.count)

        // Boards: greedy groups of near-equal windows sharing a baseline (a
        // row, Wayne and Dresser) or a centre line (a column, Lukoil and the
        // Russian Gilbarco heads).
        var used = Set<Int>()
        var rows: [[Int]] = []
        var columns: [[Int]] = []
        func sameSize(_ a: CGRect, _ b: CGRect) -> Bool {
            abs(a.width - b.width) <= boardWidthTolerance * max(a.width, b.width)
                && abs(a.height - b.height) <= boardWidthTolerance * max(a.height, b.height)
        }
        // Rows first: a horizontal board is the common case, and a vertical
        // pair of transaction windows must never be mistaken for a column board.
        for i in boxes.indices where !used.contains(i) {
            var row = [i]
            for j in boxes.indices where j != i && !used.contains(j) {
                let a = boxes[i], b = boxes[j]
                if sameSize(a, b), abs(a.midY - b.midY) <= boardBaselineTolerance * min(a.height, b.height) {
                    row.append(j)
                }
            }
            if row.count >= boardMinimumWindows {
                rows.append(row)
                for k in row { used.insert(k) }
            }
        }
        // Columns only on a head with no row board at all (Lukoil, the Russian
        // Gilbarco heads stack their grade prices vertically).
        if rows.isEmpty {
            for i in boxes.indices where !used.contains(i) {
                var column = [i]
                for j in boxes.indices where j != i && !used.contains(j) {
                    let a = boxes[i], b = boxes[j]
                    if sameSize(a, b), abs(a.midX - b.midX) <= boardBaselineTolerance * min(a.width, b.width) {
                        column.append(j)
                    }
                }
                // Three equal windows and nothing else is the transaction
                // column itself, not a board.
                if column.count >= boardMinimumWindows, column.count < windows.count {
                    columns.append(column)
                    for k in column { used.insert(k) }
                }
            }
        }

        // A head whose only windows are one equal-width row is a horizontal
        // transaction layout (an overlay), not a board: read it left to right.
        if rows.count == 1, columns.isEmpty, used.count == windows.count, rows[0].count == 3 {
            let row = rows[0].sorted { boxes[$0].midX < boxes[$1].midX }
            for (k, field) in zip(row, [PumpField.total, .liters, .unitPrice]) { roles[k] = field }
            return Assignment(roles: roles)
        }
        for group in rows + columns {
            for k in group { roles[k] = .board }
        }

        // The transaction column, top-down.
        let column = boxes.indices.filter { !used.contains($0) }.sorted { boxes[$0].midY < boxes[$1].midY }
        let order: [PumpField]
        switch column.count {
        case 3: order = [.total, .liters, .unitPrice]
        case 2: order = [.total, .liters]
        case 1: order = [.liters]
        default: order = []
        }
        for (k, field) in zip(column, order) {
            roles[k] = field
        }
        return Assignment(roles: roles)
    }

    /// The axis-aligned box of a quad, in the frame where the display reads
    /// upright (the rotation applied to the points, not the image).
    static func bounds(_ quad: [CGPoint], rotationCW: Int) -> CGRect {
        let rotated: [CGPoint]
        switch ((rotationCW % 360) + 360) % 360 {
        case 90: rotated = quad.map { CGPoint(x: -$0.y, y: $0.x) }
        case 180: rotated = quad.map { CGPoint(x: -$0.x, y: -$0.y) }
        case 270: rotated = quad.map { CGPoint(x: $0.y, y: -$0.x) }
        default: rotated = quad
        }
        let xs = rotated.map(\.x), ys = rotated.map(\.y)
        return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
    }

    /// A window whose cell count is below what its field can show is a slicer
    /// miscount, not a reading: the law must not see it.
    static func plausibleCount(_ count: Int, for field: PumpField) -> Bool {
        count >= (minimumCells[field] ?? 1)
    }
}

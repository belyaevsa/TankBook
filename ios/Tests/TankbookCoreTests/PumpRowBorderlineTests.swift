import CoreGraphics
import Foundation
import Testing
@testable import TankbookCore

/// A row that fails one geometry rule by a borderline margin is offered to the
/// law at a lower rank instead of dropped (`PumpRowGeometry.Verdict.borderline`,
/// `PumpReader.verified(from:)`). The rows are synthetic cells, so each case
/// moves exactly one measurement across its limit.
@Suite("Pump row borderline verdicts")
struct PumpRowBorderlineTests {
    private static let band: CGFloat = 80
    private static let stripHeight = 96

    /// `count` cells of width `pitch x band`, blanks at `blank`, a decimal mark
    /// after `mark`.
    private static func cells(_ count: Int, pitch: CGFloat = 0.7, blank: Set<Int> = [], mark: Int? = nil,
                              band: CGFloat = band) -> [GlyphCell] {
        (0..<count).map { index in
            GlyphCell(rect: CGRect(x: CGFloat(index) * pitch * band, y: 8, width: pitch * band, height: band),
                      hasDecimalPoint: index == mark, isBlank: blank.contains(index))
        }
    }

    private static func verdict(_ cells: [GlyphCell]) -> PumpRowGeometry.Verdict {
        PumpRowGeometry.verdict(cells: cells, stripWidth: 600, stripHeight: stripHeight)
    }

    @Test("a row inside every rule is kept and is not borderline")
    func cleanRow() {
        let v = Self.verdict(Self.cells(6, mark: 3))
        #expect(v.kept && !v.borderline)
    }

    @Test("one rule failed by one step is borderline; two steps is not")
    func oneStepPastEachRule() {
        let cap = PumpReadingLaw.maxCells
        #expect(Self.verdict(Self.cells(cap + 1)).borderline)
        #expect(!Self.verdict(Self.cells(cap + 2)).borderline)
        #expect(Self.verdict(Self.cells(6, pitch: 1.30)).borderline)
        #expect(!Self.verdict(Self.cells(6, pitch: 1.40)).borderline)
        #expect(Self.verdict(Self.cells(7, blank: [2, 3])).borderline)
        #expect(!Self.verdict(Self.cells(7, blank: [2, 3, 4])).borderline)
        #expect(Self.verdict(Self.cells(6, mark: 1)).borderline)     // four implied decimals
        #expect(!Self.verdict(Self.cells(7, mark: 1)).borderline)    // five
    }

    @Test("two failed rules, or an ink band failure, are never borderline")
    func notBorderline() {
        let cap = PumpReadingLaw.maxCells
        let twoRules = Self.verdict(Self.cells(cap + 1, pitch: 1.30))
        #expect(!twoRules.kept && !twoRules.borderline)
        let thinBand = Self.verdict(Self.cells(6, band: 20))
        #expect(thinBand.reasons == [.inkBand] && !thinBand.borderline)
    }

    private static func square(_ y: CGFloat) -> [CGPoint] {
        [CGPoint(x: 0, y: y), CGPoint(x: 100, y: y), CGPoint(x: 100, y: y + 20), CGPoint(x: 0, y: y + 20)]
    }

    private static func row(_ y: CGFloat, kept: Bool, borderline: Bool, cells: Int = 6) -> PumpReader.Verdict {
        PumpReader.Verdict(quad: square(y), heightFraction: 0.05, cells: cells, meanMargin: 0, kept: kept,
                           detected: true, borderline: borderline)
    }

    @Test("a borderline row fills an empty row, never displaces or duplicates a kept one")
    func rankedAfterKept() {
        let kept = Self.row(0, kept: true, borderline: false, cells: 4)
        let sameRowBorderline = Self.row(2, kept: false, borderline: true, cells: 9)
        let newRowBorderline = Self.row(60, kept: false, borderline: true)
        let dropped = Self.row(120, kept: false, borderline: false)
        let out = PumpReader.verified(from: [sameRowBorderline, dropped, newRowBorderline, kept])
        #expect(out.map(\.quad) == [kept.quad, newRowBorderline.quad])
    }
}

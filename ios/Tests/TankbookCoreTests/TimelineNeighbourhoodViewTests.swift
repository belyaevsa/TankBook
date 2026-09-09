import Foundation
import Testing
@testable import TankbookCore

// RV.117b: the neighbourhood VIEW derives no bound of its own - it reads the
// intervals the validator already computed (EntryValidation.validRange) and
// renders them. A behavioural test cannot express that (any two same-input
// recomputations agree, so nothing observable differs), so this is a source
// scan, the PaletteAccentGuard shape (docs/TESTING.md -> the baseline gate): if
// the panel ever started recomputing an interval it would need the validator's
// private inputs - the pace limit, the day diff, the neighbour arithmetic -
// and any of those tokens appearing in the panel's files is the regression.
@Suite("RV.117b the neighbourhood view reads validRange, never recomputes it")
struct TimelineNeighbourhoodViewTests {

    private static var panelDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // TankbookCoreTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // ios
            .appendingPathComponent("App/Sources/EditEntry", isDirectory: true)
    }

    /// The panel's two files: the view model + sentence builder
    /// (TimelineNeighbourhood.swift) and the rendered card
    /// (TimelineNeighbourhoodCard.swift). Anything that derives a bound would
    /// live in one of these - the whole point of the row is that the flag and
    /// the panel must never disagree (docs/TASKS.md RV.117).
    private static let panelFiles = ["TimelineNeighbourhood.swift", "TimelineNeighbourhoodCard.swift"]

    private static func contents(_ name: String) throws -> String {
        try String(contentsOf: panelDirectory.appendingPathComponent(name),
                   encoding: .utf8)
    }

    /// The model file must produce its `TimelineValidRange` by CALLING the
    /// validator - that is what "reads validRange" means. Without this line the
    /// file could construct intervals by hand and the token scan below would
    /// still pass.
    @Test("the neighbourhood model is produced by the validator")
    func neighbourhoodModelIsProducedByTheValidator() throws {
        let model = try Self.contents("TimelineNeighbourhood.swift")
        #expect(model.contains("TimelineValidator.validate"),
                "the panel must derive its range from the validator, never build one")
    }

    /// The validator's private inputs are the only way to recompute an interval,
    /// and none of them may appear in the panel: the pace limit, a day-diff, the
    /// 86 400 s day constant, interval-building arithmetic on the neighbours,
    /// or a constructed `.bounded(...)`. The card's chart maps dates to pixels
    /// via `timeIntervalSince`, which is geometry - not a bound - so only the
    /// `addingTimeInterval` form is banned.
    @Test("the panel never recomputes a bound (source scan)")
    func panelNeverRecomputesABound() throws {
        let forbidden = ["paceLimitKmPerDay", "dayDiff", "86_400", "addingTimeInterval(",
                         "limitKmPerDay"]
        var findings: [String] = []
        for name in Self.panelFiles {
            let source = try Self.contents(name)
            for token in forbidden where source.contains(token) {
                findings.append("\(name) contains '\(token)'")
            }
        }
        #expect(findings.isEmpty,
                """
                a bound is being recomputed in the view (docs/TASKS.md RV.117 named \
                trap): \(findings) - read validRange from TimelineValidator instead
                """)
    }
}

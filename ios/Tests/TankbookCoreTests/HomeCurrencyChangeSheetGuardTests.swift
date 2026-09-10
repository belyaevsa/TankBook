import Foundation
import Testing

// RV.178 - the negative claim that pins the product decision: the
// home-currency question has NO cancel path. The currency change is already
// decided by tapping Save; the sheet asks only what to do with the entries that
// exist, and both answers commit. A third "helpful" action added later - a
// Cancel, a "decide later", a close - would fail this test and have to
// re-decide deliberately (docs/ERRORS.md -> Vehicle detail).
//
// A source scan rather than a runtime assertion: the guarantee is about the
// SHAPE of the control, and the sheet is a SwiftUI view whose action count is
// only reachable by rendering it. The file is the single definition of the
// sheet, so the scan is exact.
@Suite("The home-currency sheet has no cancel path (RV.178)")
struct HomeCurrencyChangeSheetGuardTests {

    private static var sheetURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // TankbookCoreTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // ios
            .deletingLastPathComponent()  // repo root
            .appendingPathComponent("ios/App/Sources/VehicleDetail/HomeCurrencyChangeSheet.swift")
    }

    @Test("the sheet defines exactly two actions, both answers, and no cancel")
    func noThirdAction() throws {
        let source = try String(contentsOf: Self.sheetURL, encoding: .utf8)

        // Exactly two Button sites: Convert and Keep. A third action - cancel,
        // a close, "decide later" - changes this count and fails here.
        let buttonSites = source.components(separatedBy: "Button(").count - 1
        #expect(buttonSites == 2,
                "the sheet must define exactly two actions, found \(buttonSites)")

        #expect(source.contains("homeCurrencyChangeConvertButton"))
        #expect(source.contains("homeCurrencyChangeKeepButton"))

        // No cancel in any form.
        #expect(!source.contains("role: .cancel"))
        #expect(!source.contains("\"Cancel\""))

        // The refusal to dismiss without an answer is part of the same decision.
        #expect(source.contains(".interactiveDismissDisabled(true)"),
                "the sheet must refuse a swipe-dismiss that abandons the question")
    }
}

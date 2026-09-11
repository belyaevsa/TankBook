import Foundation
import Testing
@testable import TankbookCore

/// RV.149 - the fill-up save must report a lost receipt photo through the SAME
/// shared message the expense save uses (PJ.28): one full localised sentence
/// for one situation, never a second near-identical string (the trap the row
/// names - a duplicate lets the two screens drift apart in wording and in RU).
///
/// The guard is a source-scan over the two save call sites, the same shape as
/// `PaletteAccentGuardTests`: it fails when a surface stops reporting at all
/// (the RV.149 defect - a silent drop), when a surface reports through a
/// DIFFERENT symbol, or when the message is renamed on one surface but not the
/// other. It asserts the key, never the English text, so a duplicate string
/// cannot pass.
///
/// Lives in the SwiftPM test target because it is a pure function over source
/// text - no UIKit, no repository, no simulator.
@Suite("Receipt-photo-lost report guard (RV.149)")
struct ReceiptPhotoSaveReportGuardTests {

    private static var appSources: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // TankbookCoreTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // ios
            .appendingPathComponent("App/Sources", isDirectory: true)
    }

    private static func source(of relative: String) throws -> String {
        try String(contentsOf: appSources.appendingPathComponent(relative),
                   encoding: .utf8)
    }

    /// The `toastCenter.show(...)` lines of one app source file, trimmed.
    private static func showLines(in relative: String) throws -> [String] {
        try source(of: relative).components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.contains("toastCenter.show(") }
    }

    @Test("The fill-up save reports a lost receipt photo through the shared message")
    func fillUpSaveReportsThroughTheSharedKey() throws {
        let reportLines = try Self.showLines(in: "ConfirmManual/ManualFillUpReceiptSave.swift")
        #expect(!reportLines.isEmpty,
                "the fill-up receipt save must have a report call site - a silent drop is the RV.149 defect")
        #expect(reportLines.contains(where: { $0.contains("L10n.receiptNotSavedMessage") }),
                "the fill-up report must use the SHARED message symbol, not a second string: \(reportLines)")

        // The report is wired into the save's success path, after the entry is
        // on disk (never a "saved" claim for a save that failed). RV.173: it
        // fires ONCE per save, from the ONE write outcome - a call inside the
        // grouped save's per-expense loop would shout once per row, so the
        // count is part of the contract.
        let view = try Self.source(of: "ConfirmManual/ManualFillUpView.swift")
        let reportCalls = view.components(separatedBy: "reportLostReceiptPhoto(").count - 1
        #expect(reportCalls == 1,
                "the fill-up save must call the report exactly once, not per row: \(reportCalls)")
    }

    @Test("The expense save reports through the same shared symbol")
    func expenseSaveUsesTheSameSharedKey() throws {
        let lines = try Self.showLines(in: "ServiceEntry/ExpenseEntryView.swift")
        #expect(!lines.isEmpty)
        #expect(lines.contains(where: { $0.contains("L10n.receiptNotSavedMessage") }),
                "both surfaces must share ONE sentence: \(lines)")
    }

    /// RV.202: the Edit-entry non-fill save (service/expense attach) must report
    /// a lost photo through the same shared symbol, after the entry is on disk -
    /// the half RV.149 had to be filed for when PJ.28's fence stopped one entry
    /// kind short. This is the source-scan half; `RV202NonFillReceiptAttachTests`
    /// pins the `.lost` flag the report keys off.
    @Test("The Edit-entry non-fill save reports a lost receipt photo")
    func editEntryNonFillSaveReportsThroughTheSharedSymbol() throws {
        let view = try Self.source(of: "EditEntry/EditEntryView.swift")
        #expect(view.contains("reportLostReceiptPhoto("),
                "the non-fill save must report a lost photo, never a silent drop (RV.202)")
    }
}

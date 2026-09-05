import Foundation
import Testing
@testable import TankbookCore

// MARK: - RV.57 the proceed note's presence rule (docs/JOURNEYS.md F4, amended)

/// The note's presence is derived from there being an in-flight request, and it
/// is absent when the parse was local-only. The load-bearing claim is the exact
/// set of phases that count as "in flight": running and budget-expired show the
/// note; idle (no transport armed), answered and saved do not. A vacuous
/// version would test `shouldShow(inFlight: true) == true` - these pin the
/// per-phase mapping instead.
@Suite("Gateway proceed note (RV.57)")
struct GatewayProceedNoteTests {

    @Test("the note shows exactly while a request is in flight")
    func showsOnlyWhileInFlight() {
        #expect(GatewayProceedNote.shouldShow(phase: .running))
        #expect(GatewayProceedNote.shouldShow(phase: .budgetExpired))
        #expect(!GatewayProceedNote.shouldShow(phase: .idle))
        #expect(!GatewayProceedNote.shouldShow(phase: .answered))
        #expect(!GatewayProceedNote.shouldShow(phase: .authExpired))
        #expect(!GatewayProceedNote.shouldShow(phase: .saved))
    }

    @Test("a local-only parse never shows the note")
    func localOnlyParseShowsNoNote() {
        // `.idle` is the local-only parse: no transport was armed, so no request
        // is in flight and the note has nothing to say.
        #expect(!GatewayProceedNote.shouldShow(phase: .idle))
    }

    @Test("the in-flight phases are exactly running and budget-expired")
    func inFlightPhasesAreRunningAndBudgetExpired() {
        #expect(GatewayReadingPhase.running.isInFlight)
        #expect(GatewayReadingPhase.budgetExpired.isInFlight)
        #expect(!GatewayReadingPhase.idle.isInFlight)
        #expect(!GatewayReadingPhase.answered.isInFlight)
        #expect(!GatewayReadingPhase.authExpired.isInFlight)
        #expect(!GatewayReadingPhase.saved.isInFlight)
    }

    // MARK: - RV.65 a dead session names itself, and only auth does

    /// The failure classification the capture surface reads: only an auth-
    /// expired refusal is `.authExpired`; every other transport failure is the
    /// ordinary F4 `.answered` (the on-device result stands, nothing to fix).
    @Test("an auth-expired failure is the only one that resolves to authExpired")
    func phaseAfterFailureClassifiesOnlyAuthAsAuthExpired() {
        #expect(GatewayReadingPhase.phase(after: SyncServerError.authExpired) == .authExpired)
        #expect(GatewayReadingPhase.phase(after: SyncServerError.transportUnavailable) == .answered)
        #expect(GatewayReadingPhase.phase(after: SyncServerError.tierRefused) == .answered)
        #expect(GatewayReadingPhase.phase(after: SyncServerError.refused(status: 402)) == .answered)
    }

    // MARK: - The note is a hint, never amber, never a spinner (hard rule 7)

    /// The note's foreground must stay `inkSoft` (a hint) - never `warn` (amber
    /// is attention only, and this note is informational: nothing needs a
    /// decision, the user is told they can proceed). XCUITest cannot read a
    /// colour, so this pins the palette by scanning the source, the same
    /// source-guard shape as the empty-scan caption's guard. It also asserts the
    /// note is dismissable and carries NO spinner - "No spinner that implies
    /// waiting" (the RV.57 fence): the whole point is that the user need not
    /// wait, so a `ProgressView` would tell the opposite lie.
    @Test("the note renders inkSoft, dismissable, and spinner-free")
    func noteIsInkSoftDismissableAndSpinnerFree() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // TankbookCoreTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // ios
            .appendingPathComponent("App/Sources/ConfirmManual/ManualFillUpGatewayBanner.swift")
        let contents = try String(contentsOf: url, encoding: .utf8)

        let usesWarn = contents.contains("Theme.Palette.warn")
        let usesInkSoft = contents.contains("Theme.Palette.inkSoft")
        #expect(usesInkSoft,
                "the proceed note must render in Theme.Palette.inkSoft, never amber")
        #expect(!usesWarn,
                "the proceed note must NEVER be amber (hard rule 5) - a hint, not an error")

        #expect(contents.contains("gatewayProceedNoteDismissButton"),
                "the note must carry a dismiss affordance (hard rule 7: survives being ignored)")

        #expect(!contents.contains("ProgressView"),
                "the note must carry no spinner - a spinner implies waiting, the user need not wait")
    }
}

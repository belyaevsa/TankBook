import Foundation
import Observation
import TankbookCore

// MARK: - P6.3 the gateway session (docs/API.md -> "The device's side of
// /extract", rules 2 & 3; docs/JOURNEYS.md F4).
//
// The on-device result is already on screen when the sheet opens - the app
// never waits on the gateway to show the card. The session runs the /extract
// request in the background and applies the budget in the UI's terms:
//
// - within the 3 s budget the answer applies directly (still fill-blanks-only);
// - at 3 s the sheet stops waiting and tells the user to proceed now - the
//   REQUEST IS NOT CANCELLED, it keeps running (the budget is about the user's
//   next step, never an abort);
// - RV.57 (product-owner ruling, 2026-09-04): a LATE answer is never applied to
//   the open editor - "if a user keeps the edit entry open (they fill up
//   odometer) and recognition has arrived - there is no need to async update".
//   It lands in the inbox instead, keyed to the saved entry, never as a value
//   that moves under the user's cursor;
// - once the entry is saved, the answer is NOT dropped (RV.38 amends F4): it
//   lands in the inbox as a suggestion the user accepts, edits or declines -
//   "leave it as it is" is the default, and an accepted update fills blank
//   fields only, never overwriting a value the user saved.
//
// The session owns the timing; the view owns the form. The policy that decides
// which fields may fill lives in core (`GatewaySuggestionPolicy`), so the sheet
// and the tests cannot disagree about the boundary.

/// Drives one `/extract` request for one Confirm sheet.
@MainActor
@Observable
final class GatewayScanSession {
    /// What the sheet should show about the background request. The phase and
    /// its `isInFlight` decision live in core (`GatewayReadingPhase`) so the
    /// proceed note's presence rule (RV.57) tests at L1.
    typealias Phase = GatewayReadingPhase

    private(set) var phase: Phase = .idle
    /// The fields the user has engaged since the on-device pre-fill (tapped,
    /// typed, or picked). Engagement is permanent (hard rule 13).
    private(set) var touched: Set<FieldRef> = []

    private var started = false
    private var saved = false
    private var onAnswer: ((GatewayExtraction) -> Void)?
    /// RV.38: what to do with an answer that lands AFTER the entry was saved.
    /// F4 used to drop it; now it becomes an inbox item, so the app asks instead
    /// of silently rewriting (hard rule 13). Receives the entry id the answer is
    /// about.
    private var onSavedAnswer: ((GatewayExtraction, UUID) -> Void)?
    /// The in-flight request, retained so `markSaved` can hand its delivery to
    /// a task that survives the sheet's dismissal (the monitor's `[weak self]`
    /// cannot - the session is deallocated with the sheet).
    private var work: Task<GatewayExtraction, Error>?

    /// The UI budget. Product value 3 s (`GatewayBudget.duration`, docs/API.md
    /// rule 2); overridable ONLY by `-seedGatewayBudget <seconds>`, in the same
    /// family as `-seedGatewayDelay` beneath it.
    ///
    /// It exists because the `.running` state is otherwise UNOBSERVABLE from a
    /// UI test: the budget starts when the sheet appears, and XCUITest's launch
    /// plus its first query routinely take longer than 3 s, so a test looking
    /// for the in-flight banner reliably arrives after it is gone. Without this
    /// seam the RV.8 test could only be written as "the timeout banner appears",
    /// which passes with the whole in-flight state missing - which is exactly
    /// the bug RV.8 was.
    private let budget: Duration = GatewayScanSession.budget()

    static func budget(arguments: [String] = ProcessInfo.processInfo.arguments) -> Duration {
        guard let index = arguments.firstIndex(of: "-seedGatewayBudget"),
              arguments.indices.contains(index + 1),
              let seconds = Double(arguments[index + 1]) else { return GatewayBudget.duration }
        return .seconds(seconds)
    }

    /// Starts the request and the budget monitor. `onAnswer` is called on the
    /// main actor with the answer when (and only when) it may still be applied;
    /// `onSavedAnswer` is called instead once the entry is saved (RV.38) so the
    /// answer lands in the inbox rather than dying in `markSaved()`.
    func start(transport: any GatewayExtractTransport,
               request: GatewayExtractRequest,
               onAnswer: @escaping (GatewayExtraction) -> Void,
               onSavedAnswer: @escaping (GatewayExtraction, UUID) -> Void) {
        guard !started else { return }
        started = true
        saved = false
        self.onAnswer = onAnswer
        self.onSavedAnswer = onSavedAnswer
        phase = .running
        let work = Task.detached { [transport] in
            try await transport.extract(request)
        }
        self.work = work
        Task { [weak self] in await self?.monitor(work) }
    }
    /// The user engaged a field; from now on no late answer may touch it.
    func markTouched(_ ref: FieldRef) {
        guard started else { return }
        touched.insert(ref)
    }

    /// The entry was saved. From now on no answer may silently arrive (hard
    /// rule 13) - a late answer is routed to the inbox instead (RV.38, F4
    /// amended), keyed by the saved entry's id.
    ///
    /// The delivery is handed to a task that captures the request and the
    /// delivery closure STRONGLY, because the sheet (and this session) are torn
    /// down on save: the monitor's `[weak self]` cannot deliver a saved answer.
    /// Only the request that is still in flight is delivered - an answer that
    /// already landed within the budget went to the form (and into the save),
    /// so it must not become a second inbox item.
    func markSaved(entryID: UUID) {
        saved = true
        let wasAlreadyAnswered = phase == .answered
        phase = .saved
        guard let work, !wasAlreadyAnswered else { return }
        let onSavedAnswer = self.onSavedAnswer
        Task { [work, onSavedAnswer] in
            guard let extraction = try? await work.value else { return }
            onSavedAnswer?(extraction, entryID)
        }
    }

    // MARK: - The budget monitor

    private func monitor(_ work: Task<GatewayExtraction, Error>) async {
        let outcome: GatewayWait<GatewayExtraction>
        do {
            outcome = try await GatewayWaiter.wait(work, timeout: budget)
        } catch {
            // The transport refused or failed within the budget. An auth
            // refusal (RV.65: /extract 401'd and the refresh could not fix it)
            // names its next step - sign in - on the capture surface instead of
            // failing silently; every other failure (402/429/426/5xx/offline)
            // leaves the on-device result standing (F4) with no error surface
            // and no upsell, nothing to fix.
            phase = GatewayReadingPhase.phase(after: error)
            return
        }
        switch outcome {
        case .answered(let extraction):
            phase = .answered
            deliver(extraction)
        case .stillRunning:
            // The budget expired: the UI moves on; the request was NOT
            // cancelled and keeps running. RV.57: the late answer is NOT
            // applied to the open editor (the product-owner ruling - no async
            // update, nothing moves under the user's cursor). `markSaved`
            // awaits this same `work` and routes the answer to the inbox.
            phase = .budgetExpired
        }
    }

    /// Hands the answer to the form, unless the entry was saved meanwhile - in
    /// which case the saved answer is the `markSaved` task's job, so this drops
    /// it (a saved entry is corrected by its owner alone, never silently; the
    /// inbox item is created by the strongly-held `markSaved` task, RV.38).
    private func deliver(_ extraction: GatewayExtraction) {
        guard !saved else { return }
        onAnswer?(extraction)
    }
}

// MARK: - The transport the sheet uses

/// Builds the transport for a Confirm sheet's gateway session. A launch-arg
/// seed wins (UI tests and screenshots cannot hit a real provider), otherwise
/// the real remote transport - and only when signed in, because `/extract` is
/// bearer-only: a guest never runs the gateway.
@MainActor
enum GatewayScanStarter {
    static func makeTransport(
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> (any GatewayExtractTransport)? {
        if let seed = GatewaySeedTransport.from(arguments: arguments) { return seed }
        let store = KeychainSessionStore()
        // The gateway is armed only when the session can actually authenticate
        // (RV.26). A session that merely exists but has failed its refresh still
        // passes `load() != nil`; arming it uploads the image for a guaranteed
        // 401 (docs/JOURNEYS.md F4 made that silent). The decision lives in core
        // (`GatewayArming.shouldArm`) so it tests at L1; the `authExpired` mark
        // is the authoritative "cannot authenticate" signal.
        guard GatewayArming.shouldArm(sessionStore: store) else { return nil }
        return RemoteGatewayExtractTransport(
            director: AppConfigStore.shared.director,
            transport: appTransport(URLSessionTransport()),
            tokenProvider: KeychainTokenProvider(sessionStore: store),
            // PR.1: the same single-flight refresher every authenticated
            // transport shares - a stale (but valid) session refreshes on the
            // gateway's 401 exactly as sync does, so a cloud reading that can
            // succeed does instead of being refused silently.
            refresher: AppSessionRefresher.shared)
    }
}

// MARK: - The seeded transport (UI tests + screenshots)

/// A launch-arg-driven fake transport. `-seedGateway` arms it; the seeded
/// answer arrives after `-seedGatewayDelay <seconds>` (default 6 - long enough
/// that the 3 s budget fires first, which is the state the UI tests exercise).
/// The answer is deterministic and deliberately distinctive so a late-answer
/// fill is observable in a UI test.
///
/// `-seedGatewayAuthExpired` (RV.65) makes the seeded transport REFUSE with
/// `SyncServerError.authExpired` after the delay (default 0.5 - inside the
/// 3 s budget, so the sheet's monitor maps the failure to the `.authExpired`
/// phase and the sign-in notice shows). It exists because a UI test cannot hit
/// a real server to produce a 401 the refresh cannot fix; the seed stands in
/// for the dead-session outcome.
struct GatewaySeedTransport: GatewayExtractTransport {
    let delay: Duration
    let extraction: GatewayExtraction
    let failure: SyncServerError?

    func extract(_ request: GatewayExtractRequest) async throws -> GatewayExtraction {
        try await Task.sleep(for: delay)
        if let failure { throw failure }
        return extraction
    }

    static func from(arguments: [String]) -> GatewaySeedTransport? {
        guard arguments.contains("-seedGateway") else { return nil }
        let authExpired = arguments.contains("-seedGatewayAuthExpired")
        let delay: Duration
        if let index = arguments.firstIndex(of: "-seedGatewayDelay"),
           arguments.indices.contains(index + 1),
           let seconds = Double(arguments[index + 1]) {
            delay = .seconds(seconds)
        } else {
            delay = authExpired ? .milliseconds(500) : .seconds(6)
        }
        return GatewaySeedTransport(delay: delay,
                                    extraction: Self.seededExtraction(arguments),
                                    failure: authExpired ? .authExpired : nil)
    }

    /// The scripted answer. The values are distinctive (99.99 total, 1.679
    /// price, diesel) so a UI test can tell a late-answer fill from a derived
    /// value or a default. `-seedGatewayConsistent` swaps in a self-consistent
    /// triple (42.30 x 1.679 = 71.02) so the SCREENSHOT of the suggestion state
    /// locks cleanly instead of showing an amber mismatch - the point of that
    /// capture is the dimmed suggestion fields, not a cross-check argument.
    private static func seededExtraction(_ arguments: [String]) -> GatewayExtraction {
        if arguments.contains("-seedGatewayConsistent") {
            return GatewayExtraction(
                total: .init(value: Decimal(string: "71.02")!, confidence: 0.92),
                volume: .init(value: 42.30, confidence: 0.90),
                unitPrice: .init(value: Decimal(string: "1.679")!, confidence: 0.88),
                date: .init(value: "17.08.2026", confidence: 0.80),
                fuelKind: .init(value: .petrol95, confidence: 0.70),
                currency: .init(value: .eur, confidence: 0.60),
                pipeline: "seed"
            )
        }
        return GatewayExtraction(
            total: .init(value: Decimal(string: "99.99")!, confidence: 0.92),
            volume: .init(value: 55.00, confidence: 0.90),
            unitPrice: .init(value: Decimal(string: "1.679")!, confidence: 0.88),
            date: .init(value: "01.01.2020", confidence: 0.80),
            fuelKind: .init(value: .diesel, confidence: 0.70),
            currency: .init(value: .rub, confidence: 0.60),
            pipeline: "seed"
        )
    }
}

// MARK: - Field mapping

extension ManualFillUpMath.Field {
    /// The gateway's field ref for the same figure (the on-device vocabulary
    /// and the gateway's share the `FieldRef` enum).
    var fieldRef: FieldRef {
        switch self {
        case .total: return .total
        case .volume: return .volume
        case .unitPrice: return .unitPrice
        }
    }
}

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
// - at 3 s the sheet stops waiting and tells the user to carry on with what was
//   read locally - the REQUEST IS NOT CANCELLED, it keeps running (the budget
//   is about the user's next step, never an abort);
// - a late answer may fill only fields that are still blank and untouched, and
//   renders as a suggestion (hard rule 13);
// - once the entry is saved, nothing arrives at all (F4).
//
// The session owns the timing; the view owns the form. The policy that decides
// which fields may fill lives in core (`GatewaySuggestionPolicy`), so the sheet
// and the tests cannot disagree about the boundary.

/// Drives one `/extract` request for one Confirm sheet.
@MainActor
@Observable
final class GatewayScanSession {
    /// What the sheet should show about the background request.
    enum Phase: Equatable {
        /// No request is running (no scan, no gateway, or signed out).
        case idle
        /// The request is in flight and the 3 s budget has not expired yet.
        case running
        /// The budget expired: the sheet has moved on (the on-device result is
        /// already on screen), the request keeps running in the background.
        case budgetExpired
        /// The request finished and any fillable fields were applied (or the
        /// answer was dropped because the entry was saved).
        case answered
        /// The entry was saved; late answers are dropped (F4).
        case saved
    }

    private(set) var phase: Phase = .idle
    /// The fields the user has engaged since the on-device pre-fill (tapped,
    /// typed, or picked). Engagement is permanent (hard rule 13).
    private(set) var touched: Set<FieldRef> = []

    private var started = false
    private var saved = false
    private var onAnswer: ((GatewayExtraction) -> Void)?

    /// Starts the request and the budget monitor. `onAnswer` is called on the
    /// main actor with the answer when (and only when) it may still be applied.
    func start(transport: any GatewayExtractTransport,
               request: GatewayExtractRequest,
               onAnswer: @escaping (GatewayExtraction) -> Void) {
        guard !started else { return }
        started = true
        saved = false
        self.onAnswer = onAnswer
        phase = .running
        let work = Task.detached { [transport] in
            try await transport.extract(request)
        }
        Task { [weak self] in await self?.monitor(work) }
    }
    /// The user engaged a field; from now on no late answer may touch it.
    func markTouched(_ ref: FieldRef) {
        guard started else { return }
        touched.insert(ref)
    }

    /// The entry was saved; from now on no answer may arrive at all (F4).
    func markSaved() {
        saved = true
        phase = .saved
    }

    // MARK: - The budget monitor

    private func monitor(_ work: Task<GatewayExtraction, Error>) async {
        let outcome: GatewayWait<GatewayExtraction>
        do {
            outcome = try await GatewayWaiter.wait(work)
        } catch {
            // The transport refused or failed within the budget (402/429/426/
            // 5xx/offline). The on-device result stands (F4) - there is no
            // error surface and no upsell, nothing to fix.
            phase = .answered
            return
        }
        switch outcome {
        case .answered(let extraction):
            phase = .answered
            deliver(extraction)
        case .stillRunning(let running):
            // The budget expired: the UI moves on; the request was NOT
            // cancelled and keeps running. Await the late answer.
            phase = .budgetExpired
            let extraction = try? await running.value
            phase = .answered
            if let extraction {
                deliver(extraction)
            }
        }
    }

    /// Hands the answer to the form, unless the entry was saved meanwhile.
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
        guard (try? KeychainSessionStore().load()) != nil else { return nil }
        let baseURL = (try? ConfigDefaults.bundledAppConfig().apiBaseURL)
            ?? URL(string: "https://api.tankbook.live")!
        return RemoteGatewayExtractTransport(
            baseURL: baseURL,
            transport: URLSessionTransport(),
            tokenProvider: KeychainTokenProvider(sessionStore: KeychainSessionStore()))
    }
}

// MARK: - The seeded transport (UI tests + screenshots)

/// A launch-arg-driven fake transport. `-seedGateway` arms it; the seeded
/// answer arrives after `-seedGatewayDelay <seconds>` (default 6 - long enough
/// that the 3 s budget fires first, which is the state the UI tests exercise).
/// The answer is deterministic and deliberately distinctive so a late-answer
/// fill is observable in a UI test.
struct GatewaySeedTransport: GatewayExtractTransport {
    let delay: Duration
    let extraction: GatewayExtraction

    func extract(_ request: GatewayExtractRequest) async throws -> GatewayExtraction {
        try await Task.sleep(for: delay)
        return extraction
    }

    static func from(arguments: [String]) -> GatewaySeedTransport? {
        guard arguments.contains("-seedGateway") else { return nil }
        let delay: Duration
        if let index = arguments.firstIndex(of: "-seedGatewayDelay"),
           arguments.indices.contains(index + 1),
           let seconds = Double(arguments[index + 1]) {
            delay = .seconds(seconds)
        } else {
            delay = .seconds(6)
        }
        return GatewaySeedTransport(delay: delay, extraction: Self.seededExtraction(arguments))
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

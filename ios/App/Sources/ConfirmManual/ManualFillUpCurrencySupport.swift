import Foundation
import SwiftUI
import TankbookCore

// MARK: - P2.5 foreign-currency support for the Confirm sheet
//
// The rate store is a shared, thread-safe instance over the bundled seed pack
// plus the persisted cache, refreshed from the backend's public `/rates/pack`
// feed (never launch-blocking - a miss is never an error, F9). The foreign-
// currency decision and its money pair live in `RateStore.resolve` (core); the
// form-state extension below holds the thin view-side conveniences so the
// Confirm sheet and the Edit screen read one source of truth (P5.2b), including
// the manual-rate override (hard rule 13).

/// The app-wide rate store. Built lazily on first use from the bundled seed
/// pack and the persisted cache, with the real fetcher behind the configured
/// base URL; the refresh is kicked off in the background, never blocking launch
/// (hard rule 1).
@MainActor
enum AppRates {
    /// The injected Low Power Mode state (P6.8), handed to `RateStore` so its
    /// refresh defers through the app's single seam. Set by
    /// `configure(powerState:)` from the app root before the store is first
    /// touched; the default is the real `ProcessInfoPowerState`, so the store
    /// still works alone in tests.
    private static var powerState: any PowerStateProvider = ProcessInfoPowerState()

    /// Set once at launch, before `store` is first touched.
    ///
    /// The chosen guarantee is **fail loudly**: `store` is a lazy `static let`,
    /// so a power state set after it was built would be silently ignored (the
    /// store captured whatever was there). Rather than let that happen, this
    /// traps if the store is already built - the injection is early by
    /// construction (the app root calls it in `init`, before any screen can
    /// touch the store), and a regression fails the `precondition` instead of
    /// quietly taking a default no test can force.
    static func configure(powerState: any PowerStateProvider) {
        precondition(!storeBuilt,
                     "AppRates.configure(powerState:) must run before the rate store is first touched")
        self.powerState = powerState
    }

    /// Set by `store`'s initializer the first time it is accessed, so
    /// `configure` can tell "not built yet" from "too late".
    private static var storeBuilt = false

    static let store: RateStore = {
        storeBuilt = true
        let persisted = loadPersisted()
        let seed = (try? RateSeedStore.bundledSeed()) ?? []
        let store = RateStore(seed: seed, fetcher: makeFetcher(), powerState: powerState)
        // Fetched rows already persisted (and the seed written back on a prior
        // launch) replace seed rows for the same key - `merge` is keyed.
        store.merge(persisted)
        return store
    }()

    /// The shared `LowPowerResumer` (P6.8, set at app launch): a deferred pack
    /// refresh registers here so it drains with the deferred sync the moment the
    /// mode ends, instead of waiting for the next process launch. Nil until the
    /// app root wires it, so the store still works alone in tests.
    static var resumer: LowPowerResumer?

    /// Set by the app root: a backfill that filled something bumps the toast-
    /// center revision so Home re-reads its derived stats (S8 - the backfill is
    /// SILENT: `noteEntryChanged` posts no toast, no banner, no badge). Nil
    /// until the root wires it, so `refresh` still works alone in tests.
    static var onBackfilled: (@MainActor () -> Void)?

    /// Refreshes the cache from the feed, persists what it merged, then runs
    /// the S8 backfill (PJ.8): a rate that arrived later fills rate-pending
    /// entries, fill-blanks-only, at the entry's own date (hard rule 3). A
    /// failed fetch leaves the cache (and any pending entries) exactly as they
    /// were - the backfill over the unchanged cache is still safe and silent.
    static func refresh() async {
        let refreshed = await store.refresh()
        // `RateStore.refresh` returns false only for a Low Power deferral (the
        // store always has a fetcher here): the fetch is opportunistic work
        // (docs/SYNC.md -> Low Power Mode table), so it waits for power and
        // drains when the mode ends.
        if !refreshed {
            await registerDeferredRefresh()
        }
        persist(store.allRates())
        await runBackfill()
    }

    /// One backfill pass over the current cache (S8). Idempotent; a fill bumps
    /// the revision through `onBackfilled` so the UI re-reads, silently.
    @discardableResult
    static func runBackfill() async -> MoneyBackfillService.Result? {
        guard let repository = try? AppStore.repository() else { return nil }
        let result = try? MoneyBackfillService(store: store).backfill(repository)
        if result?.filledCount ?? 0 > 0 {
            onBackfilled?()
        }
        return result
    }

    /// One stable id per refresh deferral, so re-registering replaces rather
    /// than stacking a second drain closure.
    private static let deferredRefreshID = UUID()

    private static func registerDeferredRefresh() async {
        guard let resumer else { return }
        let work = LowPowerResumer.PendingWork(id: Self.deferredRefreshID,
                                               kind: .ratePackRefresh) {
            await AppRates.refresh()
        }
        await resumer.register(work)
    }

    private static func loadPersisted() -> [ExchangeRate] {
        guard let repository = try? AppStore.repository() else { return [] }
        return (try? repository.exchangeRates()) ?? []
    }

    private static func persist(_ rates: [ExchangeRate]) {
        guard let repository = try? AppStore.repository() else { return }
        try? repository.upsertExchangeRates(rates)
        // Keep ~2 years rolling (docs/SCHEMA.md -> Exchange rates).
        let calendar = Calendar.current
        let cutoff = calendar.date(byAdding: .year, value: -2, to: Date()) ?? Date()
        try? repository.pruneExchangeRates(olderThan: cutoff)
    }

    private static func makeFetcher() -> RemoteRateFetcher {
        return RemoteRateFetcher(director: AppConfigStore.shared.director,
                                 transport: makeTransport(),
                                 tokenProvider: PublicTokenProvider())
    }

    /// The rate transport. `-stubRates` (UI tests + screenshots) answers the
    /// `/rates/pack` endpoint with a deterministic pack so the refresh -> S8
    /// backfill path runs without a live feed; otherwise the transport is the
    /// app-wide seeded/real one (offline under a seeded launch, P6.21).
    private static func makeTransport() -> any TankbookHTTPTransport {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-stubRates") {
            return RateStubTransport()
        }
        return appTransport(SeededLaunch.transport())
        #else
        return appTransport(URLSessionTransport())
        #endif
    }
}

/// The rates endpoint is public - no auth (docs/API.md -> Exchange rates) - so
/// the fetcher's client never attaches a bearer token for it. The allowlist is
/// still enforced by `TankbookHTTPClient` before any I/O.
private struct PublicTokenProvider: AuthorizationTokenProvider {
    func token() -> String? { nil }
}

/// PJ.8's UI-test/screenshot seam (`-stubRates`): answers the public
/// `/rates/pack` endpoint with a deterministic EUR->PLN pack for the dates
/// `HomeTestSeed` dates its rate-pending fill-ups (2026-08-22..24, deliberately
/// OUTSIDE the bundled seed pack so only this fetch fills them), so the launch
/// refresh -> S8 backfill fills them without a live feed or `-runRateBackfill`.
/// Stateless; any other path is a 404 (a miss, never an error - F9).
#if DEBUG
private struct RateStubTransport: TankbookHTTPTransport {
    func execute(_ request: TankbookHTTPRequest) async throws -> TankbookHTTPResponse {
        guard request.url.path.hasPrefix("/v1/rates/pack") else {
            return TankbookHTTPResponse(status: 404)
        }
        let body = """
        {"base":"EUR","rates":[
          {"date":"2026-08-22","quote":"PLN","rate":4.2706,"source":"ecb"},
          {"date":"2026-08-23","quote":"PLN","rate":4.2706,"source":"ecb"},
          {"date":"2026-08-24","quote":"PLN","rate":4.2706,"source":"ecb"}
        ]}
        """
        return TankbookHTTPResponse(status: 200, body: Data(body.utf8))
    }
}
#endif

@MainActor
extension ManualFillUpFormState {
    /// The effective foreign-currency state for this form. A typed manual rate
    /// is the user's decision and WINS over the feed's snapshot (hard rule 13):
    /// it renders as `.converted(.manual)` at the entry's OWN date - never
    /// today (F9) - and the feed never rewrites it afterwards. Never on a
    /// low-confidence currency: an uncertain currency asks, never converts.
    func conversionState(vehicle: Vehicle?, lowConfidence: Bool) -> ForeignCurrencyState {
        guard let vehicle else { return .notForeign }
        guard currency != vehicle.homeCurrency else { return .notForeign }
        if !lowConfidence, let manual = manualRateDecimal {
            return .converted(RateSnapshot(rate: manual, rateDate: date, source: .manual))
        }
        let snapshot = AppRates.store.snapshot(original: currency,
                                               home: vehicle.homeCurrency,
                                               on: date)
        return ForeignCurrencyDetector.state(currency: currency,
                                             homeCurrency: vehicle.homeCurrency,
                                             lowConfidence: lowConfidence,
                                             snapshot: snapshot)
    }

    /// The converted home amount for the card, for the total Save will write -
    /// the exact same decision, never a separately-rounded figure. A manual
    /// rate writes through `Money.applyingManualRate` (the documented pair:
    /// the entry's date, `rateSource == .manual`) - never a hand-built snapshot
    /// fed to `converted(using:)`, which is fill-blanks-only (P5.2a pins this).
    func convertedAmount(vehicle: Vehicle?, volumeUnit: VolumeUnit,
                         lowConfidence: Bool) -> Decimal? {
        guard let vehicle, let total = effectiveTotal(volumeUnit: volumeUnit) else { return nil }
        switch conversionState(vehicle: vehicle, lowConfidence: lowConfidence) {
        case .converted(let snapshot):
            let base = Money(amount: total, currency: currency, homeCurrency: vehicle.homeCurrency)
            if snapshot.source == .manual {
                return base.applyingManualRate(snapshot.rate, on: snapshot.rateDate).homeAmount
            }
            return base.converted(using: snapshot).homeAmount
        case .ratePending, .notForeign, .lowConfidence:
            return nil
        }
    }

    /// Applies the current conversion to a money pair for saving. A manual rate
    /// is the user's number and replaces whatever the feed wrote via
    /// `Money.applyingManualRate`; otherwise the store's snapshot applies
    /// fill-blanks-only; when the state is not `.converted` the pair saves
    /// rate-pending (F9) - conversion is metadata, never a save-blocker.
    func convertForSave(_ money: Money, vehicle: Vehicle?, lowConfidence: Bool) -> Money {
        switch conversionState(vehicle: vehicle, lowConfidence: lowConfidence) {
        case .converted(let snapshot):
            if snapshot.source == .manual {
                return money.applyingManualRate(snapshot.rate, on: snapshot.rateDate)
            }
            return money.converted(using: snapshot)
        case .ratePending, .notForeign, .lowConfidence:
            return money
        }
    }
}

extension ManualFillUpView {
    /// The single foreign-currency decision for the current form, shared by the
    /// conversion card and the save path. Detection comes from the extraction's
    /// currency when present and the user's chip choice otherwise - never the
    /// device locale alone. A typed manual rate overrides the feed (rule 13).
    var conversionState: ForeignCurrencyState {
        form.conversionState(vehicle: vehicle, lowConfidence: currencyLowConfidence)
    }

    /// The converted home amount for the card, for the total Save will write.
    var convertedAmount: Decimal? {
        form.convertedAmount(vehicle: vehicle, volumeUnit: volumeUnit,
                             lowConfidence: currencyLowConfidence)
    }

    /// Applies the current conversion to a money pair for saving. When the
    /// state is not `.converted` the pair saves rate-pending (F9).
    func convertForSave(_ money: Money) -> Money {
        form.convertForSave(money, vehicle: vehicle, lowConfidence: currencyLowConfidence)
    }
}

extension ManualFillUpView {
    /// The "No car yet" hint card, shown when the sheet opens with no garage.
    var noVehicleCard: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "car")
                .font(.caption)
                .foregroundStyle(Theme.Palette.inkSoft)
            Text("No car yet – add one from Garage to start logging fill-ups.")
                .font(.caption)
                .foregroundStyle(Theme.Palette.inkSoft)
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Theme.Palette.dash)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card)
                .stroke(Theme.Palette.hairline, lineWidth: 1)
        )
        .accessibilityIdentifier("manualFillUpNoVehicleHint")
    }
}

/// The currency section (artboard): the chip row plus, depending on the
/// foreign-currency state, the amber low-confidence prompt or the neutral
/// caption. The conversion card itself (rate-pending / converted) renders as a
/// separate card below the three-number card, matching ConfirmForeign.dc.html -
/// this section only owns the chips and the two inline hints.
struct ManualFillUpCurrencySection: View {
    @Binding var form: ManualFillUpFormState
    let homeCurrency: CurrencyCode
    let lowConfidence: Bool
    let state: ForeignCurrencyState

    /// Collapsed while the entry is in the home currency and the reading is
    /// confident - the overwhelmingly common case. Paying abroad is rare, and a
    /// five-chip row plus a caption cost ~100 pt of the first screen, which
    /// pushed the ODOMETER - the field consumption depends on - below the fold
    /// and behind the pinned Save bar.
    ///
    /// It is a fold, never a lock (hard rule 13): one tap opens the chips, and
    /// the collapsed row still names the currency in force.
    // The flag lives on the form state (`form.isCurrencyExpanded`), not here -
    // see the note there. A local `@State` did not survive the parent's
    // re-render, so the section folded itself back the instant it was opened.

    /// The section opens ITSELF whenever the currency is not simply the home
    /// one: a low-confidence reading must ask rather than convert (P2.5), and a
    /// genuinely foreign entry has a conversion the user must see. Only the
    /// boring case folds away.
    private var mustStayOpen: Bool {
        Self.needsAttention(currency: form.currency, homeCurrency: homeCurrency,
                            lowConfidence: lowConfidence, state: state)
    }

    /// Whether the currency is something the user must SEE rather than merely
    /// be able to reach. Callers use it to decide **placement**: a section that
    /// opens itself below the fold is not open in any sense that matters, so a
    /// currency needing attention renders above the numbers card, and only the
    /// folded home-currency case sits below it.
    static func needsAttention(currency: CurrencyCode, homeCurrency: CurrencyCode,
                               lowConfidence: Bool, state: ForeignCurrencyState) -> Bool {
        lowConfidence || state != .notForeign || currency != homeCurrency
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if form.isCurrencyExpanded || mustStayOpen {
                SectionEyebrow("Currency")
                CurrencyChipRow(currency: $form.currency, homeCurrency: homeCurrency,
                                lowConfidence: lowConfidence)
                hint
            } else {
                collapsedRow
            }
        }
    }

    /// One compact line: the currency in force, and an affordance to change it.
    private var collapsedRow: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { form.isCurrencyExpanded = true }
        } label: {
            HStack(spacing: 6) {
                Text("Currency")
                    .font(.caption2)
                    .foregroundStyle(Theme.Palette.inkSoft)
                Spacer(minLength: 8)
                Text(AddVehicleSupport.currencyLabel(for: form.currency))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.Palette.ink)
                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(Theme.Palette.inkSoft)
            }
            // `.contentShape` is load-bearing, not decoration: a `.plain`
            // Button's hit area is its RENDERED content, and this row is a label
            // on the left, a Spacer, and a value on the right - so its middle,
            // which is exactly where a tap lands, was empty and hit nothing. The
            // row reported `isHittable = true` and swallowed every tap. The
            // working rows in this app (`TankLevelRow`) all carry this line.
            .contentShape(Rectangle())
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
        }
        .buttonStyle(.plain)
        .formCard()
        .accessibilityIdentifier("manualFillUpCurrencyCollapsed")
        .accessibilityLabel(Text("Currency"))
        .accessibilityValue(Text(AddVehicleSupport.currencyLabel(for: form.currency)))
    }

    @ViewBuilder
    private var hint: some View {
        switch state {
        case .lowConfidence:
            // Never silently convert: an uncertain currency asks, in amber.
            hintText(L10n.localize("Which currency is this?"), color: Theme.Palette.warn,
                     identifier: "manualFillUpCurrencyHint")
        case .notForeign:
            hintText(String(format: L10n.localize("Recent first · a foreign amount converts to %@ automatically"),
                            homeCurrency.rawValue),
                     color: Theme.Palette.inkSoft, identifier: nil)
        case .ratePending, .converted:
            // The conversion card owns the rate-pending / converted copy.
            EmptyView()
        }
    }

    private func hintText(_ text: String, color: Color, identifier: String?) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(color)
            .modifier(OptionalIdentifier(identifier: identifier))
    }
}

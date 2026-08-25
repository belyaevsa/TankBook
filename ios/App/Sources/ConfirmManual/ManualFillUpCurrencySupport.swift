import Foundation
import SwiftUI
import TankbookCore

// MARK: - P2.5 foreign-currency support for the Confirm sheet
//
// The rate store is a shared, thread-safe instance over the bundled seed pack
// (no network - a miss is never an error, F9). The foreign-currency decision
// and its money pair live in `RateStore.resolve` (core); this extension holds
// the three thin view-side conveniences so the sheet and the save path read one
// source of truth.

/// The app-wide rate store. Bundled seed pack now; the fetcher lands with sync.
enum AppRates {
    static let store = RateStore(seed: (try? RateSeedStore.bundledSeed()) ?? [])
}

extension ManualFillUpView {
    /// The single foreign-currency decision for the current form, shared by the
    /// conversion card and the save path. Detection comes from the extraction's
    /// currency when present and the user's chip choice otherwise - never the
    /// device locale alone.
    var conversionState: ForeignCurrencyState {
        guard let vehicle else { return .notForeign }
        let snapshot = AppRates.store.snapshot(original: form.currency,
                                               home: vehicle.homeCurrency,
                                               on: form.date)
        return ForeignCurrencyDetector.state(currency: form.currency,
                                             homeCurrency: vehicle.homeCurrency,
                                             lowConfidence: currencyLowConfidence,
                                             snapshot: snapshot)
    }

    /// The converted home amount for the card, for the total Save will write -
    /// the exact same snapshot, never a separately-rounded figure.
    var convertedAmount: Decimal? {
        guard case .converted(let snapshot) = conversionState,
              let vehicle, let total = form.effectiveTotal(volumeUnit: volumeUnit) else { return nil }
        let base = Money(amount: total, currency: form.currency,
                         homeCurrency: vehicle.homeCurrency)
        return base.converted(using: snapshot).homeAmount
    }

    /// Applies the current conversion to a money pair for saving. When the
    /// state is not `.converted` the pair saves rate-pending (F9).
    func convertForSave(_ money: Money) -> Money {
        guard case .converted(let snapshot) = conversionState else { return money }
        return money.converted(using: snapshot)
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

import SwiftUI
import TankbookCore

// MARK: - Formatting helpers

/// Display formatting for the tank-level sheet and row (design/screens/
/// TankLevel.dc.html). All fractions are eighths of the tank; quarters and
/// full get their artboard fraction glyphs, everything else a plain percent.
enum TankLevelFormat {
    /// The slider snaps to eighths: 0, 12.5, 25, …, 100.
    static let eighthStep = 100.0 / 8.0

    static func snapped(_ pct: Double) -> Double {
        min(max((pct / eighthStep).rounded() * eighthStep, 0), 100)
    }

    /// "75" / "62.5" – whole eighths show as integers, half-eighths keep one
    /// decimal place (tabular, DIN on screen).
    static func percent(_ pct: Double) -> String {
        let oneDecimal = (pct * 10).rounded() / 10
        if oneDecimal.truncatingRemainder(dividingBy: 1) == 0 {
            return String(Int(oneDecimal))
        }
        return String(format: "%.1f", oneDecimal)
    }

    /// The fraction glyph for an eighth that has one (Full / ¾ / ½ / ¼).
    static func fractionGlyph(_ pct: Double) -> String? {
        switch pct {
        case 100: return L10n.localize("Full")
        case 75: return "¾"
        case 50: return "½"
        case 25: return "¼"
        default: return nil
        }
    }

    /// The primary button title: "Set ¾ tank" for the artboard's four presets,
    /// "Set 63% tank" for the fine-tuned eighths in between.
    static func setTitle(_ pct: Double) -> String {
        if let glyph = fractionGlyph(pct) {
            switch pct {
            case 100: return L10n.localize("Set full tank")
            default: return String(format: L10n.localize("Set %@ tank"), glyph)
            }
        }
        return String(format: L10n.localize("Set %d%% tank"), Int(pct.rounded()))
    }

    /// The fill-up form's tank row: "Full · 100%" for a full tank, the percent
    /// for a level that is set, and the "Set level" prompt for a bare partial.
    static func rowTitle(isFull: Bool, level: Double?) -> String {
        if isFull { return L10n.localize("Full · 100%") }
        guard let level else { return L10n.localize("Set level") }
        return "\(percent(level))%"
    }

    /// The litres equivalence ("≈ 53 of 71 L"), the artboard's fine-tune
    /// caption; only meaningful when a capacity is known.
    static func litresEquivalence(pct: Double, capacityL: Double) -> String {
        let litres = Int((pct / 100 * capacityL).rounded())
        let capacity = Int(capacityL.rounded())
        return String(format: L10n.localize("≈ %d of %d L"), litres, capacity)
    }
}

// MARK: - The tank row (in the fill-up forms)

/// The tappable "Tank after fill-up" row the tank-level sheet opens from
/// (docs/SCREENMAP.md: Tank level reached from "Confirm's tank row"). Always
/// shown: for a full fill it reads "Full · 100%", for a level set it reads the
/// percent, and for a bare partial it invites "Set level".
struct TankLevelRow: View {
    let isFull: Bool
    let tankLevelAfterPct: Double?
    let action: () -> Void

    private var value: String {
        TankLevelFormat.rowTitle(isFull: isFull, level: tankLevelAfterPct)
    }

    private var isSet: Bool { isFull || tankLevelAfterPct != nil }

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("Tank after fill-up")
                    .font(.subheadline)
                    .foregroundStyle(Theme.Palette.inkSoft)
                    .fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 8)
                HStack(spacing: 5) {
                    Text(value)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isSet ? Theme.Palette.ink : Theme.Palette.action)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.Palette.inkSoft)
                }
            }
            .contentShape(Rectangle())
            .padding(.horizontal, Theme.Spacing.cardPadding)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("tankLevelRow")
    }
}

// MARK: - The sheet

/// The tank-level sheet (design/screens/TankLevel.dc.html): one easy question
/// – "how full is it now?" – whose answer lets a consumption segment close on a
/// partial fill (docs/SCHEMA.md, TANK-LEVEL). The percentage is the user's:
/// a suggested draft (the current value, or ¾ for a fresh partial) is only a
/// default input, never a fact (hard rule 13). Skip dismisses without applying;
/// "Set" folds the chosen level back into the fill-up form.
///
/// ERRORS.md -> Tank level: when no tank capacity is set the litres equivalence
/// is hidden behind the hint "Set tank size in Garage to see liters." – the
/// percentages still work; the sheet is never blocked on a missing capacity.
struct TankLevelSheet: View {
    @Binding var tankLevelAfterPct: Double?
    @Binding var isFull: Bool
    /// The vehicle's tank capacity in litres; nil hides the litres line and
    /// shows the ERRORS.md hint instead.
    let capacityL: Double?

    @Environment(\.dismiss) private var dismiss
    @State private var draft: Double

    private static let chips: [(value: Double, label: String)] = [
        (100, "Full"), (75, "¾"), (50, "½"), (25, "¼")
    ]

    init(tankLevelAfterPct: Binding<Double?>, isFull: Binding<Bool>, capacityL: Double?) {
        self._tankLevelAfterPct = tankLevelAfterPct
        self._isFull = isFull
        self.capacityL = capacityL
        let current = tankLevelAfterPct.wrappedValue ?? (isFull.wrappedValue ? 100 : 75)
        _draft = State(initialValue: current)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                header
                chipsRow
                fineTuneCard
                infoLine
                buttons
            }
            .padding(.horizontal, Theme.Spacing.screenMargin)
            .padding(.top, 6)
            .padding(.bottom, 24)
        }
        .background(Theme.Palette.midnight)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Tank after fill-up")
                .font(.title3.weight(.bold))
                .foregroundStyle(Theme.Palette.ink)
            Spacer(minLength: 8)
            Text("didn't fill to full?")
                .font(.caption)
                .foregroundStyle(Theme.Palette.inkSoft)
        }
        .padding(.horizontal, 2)
    }

    // MARK: Chips

    private var chipsRow: some View {
        HStack(spacing: 7) {
            ForEach(Self.chips, id: \.value) { chip in
                chipButton(chip)
            }
        }
    }

    private func chipButton(_ chip: (value: Double, label: String)) -> some View {
        let selected = draft == chip.value
        return Button {
            draft = chip.value
        } label: {
            Text(L10n.localize(chip.label))
                .font(.footnote.weight(selected ? .bold : .semibold))
                .foregroundStyle(selected ? Theme.Palette.ink : Theme.Palette.inkSoft)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Capsule().fill(selected ? Theme.Palette.taillight.opacity(0.14) : Theme.Palette.dash))
                .overlay(Capsule().stroke(selected ? Theme.Palette.taillight : Theme.Palette.hairline,
                                          lineWidth: selected ? 1.5 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("tankLevelChip_\(Int(chip.value))")
    }

    // MARK: Fine-tune card

    private var fineTuneCard: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("Fine-tune")
                    .font(.caption)
                    .textCase(.uppercase)
                    .tracking(1.2)
                    .foregroundStyle(Theme.Palette.inkSoft)
                Spacer(minLength: 8)
                Text(TankLevelFormat.percent(draft))
                    .font(.custom(AppFonts.dinAlternateBold, size: 34))
                    .foregroundStyle(Theme.Palette.ink)
                    .monospacedDigit()
                Text("%")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.Palette.inkSoft)
            }
            .padding(.bottom, 14)

            TankLevelSlider(value: $draft)
                .accessibilityIdentifier("tankLevelSlider")

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("snaps to eighths")
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.inkSoft)
                Spacer(minLength: 8)
                if let capacityL {
                    Text(TankLevelFormat.litresEquivalence(pct: draft, capacityL: capacityL))
                        .font(.footnote)
                        .foregroundStyle(Theme.Palette.inkSoft)
                        .monospacedDigit()
                        .accessibilityIdentifier("tankLevelLitresEquivalence")
                }
            }
            .padding(.top, 10)

            if capacityL == nil {
                Text("Set tank size in Garage to see liters.")
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.inkSoft)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 6)
                    .accessibilityIdentifier("tankLevelNoCapacityHint")
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(Theme.Palette.dash)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Theme.Palette.hairline, lineWidth: 1)
        )
    }

    // MARK: Info

    private var infoKey: String {
        "With a tank level, consumption stays exact even between partial fill-ups. "
            + "Skip it and this counts as a partial – math resumes at your next full tank."
    }

    private var infoLine: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle")
                .font(.caption)
                .foregroundStyle(Theme.Palette.inkSoft)
                .padding(.top, 1)
            Text(L10n.localize(infoKey))
                .font(.caption)
                .foregroundStyle(Theme.Palette.inkSoft)
                .lineSpacing(2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 2)
        .accessibilityIdentifier("tankLevelInfoLine")
    }

    // MARK: Buttons

    private var buttons: some View {
        HStack(spacing: 10) {
            Button("Skip") { dismiss() }
                .buttonStyle(.plain)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.Palette.inkSoft)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(RoundedRectangle(cornerRadius: 15).fill(Theme.Palette.dash))
                .overlay(RoundedRectangle(cornerRadius: 15).stroke(Theme.Palette.hairline, lineWidth: 1))
                .accessibilityIdentifier("tankLevelSkipButton")

            Button(action: apply) {
                Text(TankLevelFormat.setTitle(draft))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(RoundedRectangle(cornerRadius: 15).fill(Theme.Palette.taillight))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("tankLevelSetButton")
        }
    }

    private func apply() {
        if draft >= 100 {
            isFull = true
            tankLevelAfterPct = 100
        } else {
            isFull = false
            tankLevelAfterPct = draft
        }
        dismiss()
    }
}

// MARK: - The slider

/// The artboard's fine-tune control: a taillight gradient fill, a light thumb,
/// E/F end labels and quarter ticks. Values snap to eighths of the tank.
private struct TankLevelSlider: View {
    @Binding var value: Double

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let fraction = min(max(value / 100, 0), 1)
            let trackCenter = geo.size.height / 2
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.Palette.ink.opacity(0.15))
                    .frame(height: 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .offset(y: trackCenter - 5)
                Capsule()
                    .fill(LinearGradient(colors: [Theme.Palette.taillight.opacity(0.65),
                                                  Theme.Palette.taillight],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(0, width * fraction), height: 10)
                    .offset(y: trackCenter - 5)
                // Quarter ticks under the track.
                ForEach([0.25, 0.5, 0.75], id: \.self) { tick in
                    Rectangle()
                        .fill(Theme.Palette.ink.opacity(0.2))
                        .frame(width: 1.5, height: 7)
                        .offset(x: width * tick - 0.75, y: trackCenter + 8)
                }
                // E / F end labels.
                Text("E")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Theme.Palette.inkSoft)
                    .offset(x: 0, y: trackCenter - 19)
                Text("F")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Theme.Palette.inkSoft)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .offset(y: trackCenter - 19)
                // The thumb rides on top.
                Circle()
                    .fill(Theme.Palette.ink)
                    .frame(width: 26, height: 26)
                    .overlay(Circle().stroke(Theme.Palette.taillight, lineWidth: 3))
                    .shadow(color: .black.opacity(0.4), radius: 6, y: 2)
                    .offset(x: width * fraction - 13, y: trackCenter - 13)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        value = TankLevelFormat.snapped(drag.location.x / width * 100)
                    }
            )
        }
        .frame(height: 34)
    }
}

// MARK: - Test seeding

/// UI-test seeding for the tank-level sheet. `-seedTankLevel` creates a car
/// with a known capacity (the litres equivalence shows), `-seedTankLevelNoCapacity`
/// a car without one (the ERRORS.md hint shows). Combined with
/// `-homeResetDatabase` for isolation; idempotent once a vehicle exists.
enum TankLevelTestSeed {
    @MainActor
    static func seedIfRequested() {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("-seedTankLevel")
            || arguments.contains("-seedTankLevelNoCapacity")
            || arguments.contains("-homeResetDatabase") else { return }
        if arguments.contains("-homeResetDatabase") {
            AppStore.resetForTestsOncePerLaunch()
        }
        guard let repository = try? AppStore.repository() else { return }
        guard (try? repository.liveVehicles())?.isEmpty != false else { return }

        let withCapacity = arguments.contains("-seedTankLevel")
        let now = Date()
        let vehicle = Vehicle(
            id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
            name: "Volvo V60", make: "Volvo", model: "V60", year: 2015,
            plate: nil, powertrain: .ice, fuelKinds: [.petrol95, .diesel],
            tankCapacityL: withCapacity ? 71 : nil, batteryCapacityKWh: nil,
            homeCurrency: .eur,
            units: Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100,
                                  energy: .kWhPer100),
            photo: nil, archived: false, paceLimitKmPerDay: 1500,
            initialOdometer: 119_486)
        try? repository.upsertVehicle(vehicle)

        let priorDate = now.addingTimeInterval(-6 * 86_400)
        let prior = FillUp(
            id: UUID.v7(), createdAt: priorDate, updatedAt: priorDate, deletedAt: nil,
            vehicleId: vehicle.id, date: priorDate, odometer: 119_486,
            money: Money(amount: Decimal(string: "71.02")!, currency: .eur, homeCurrency: .eur),
            note: nil, attachments: [], provenance: .manual, conflict: .none,
            purchaseGroupId: nil, volumeL: 42.30, unitPrice: Decimal(string: "1.679")!,
            fuelKind: .petrol95, fuelGrade: nil, isFull: true, tankLevelAfterPct: 100,
            stationId: nil, crossCheck: .verified, extraction: nil)
        try? repository.upsertFillUp(prior)
    }
}

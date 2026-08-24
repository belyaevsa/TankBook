import SwiftUI
import TankbookCore

// MARK: - Currency chips

/// The currency chip row (artboard): EUR/PLN/CZK/CHF plus a "More…" menu. One
/// tap picks the entry's original currency; a foreign pick makes the money pair
/// rate-pending (F9) - never silently converted (docs/ERRORS.md -> Confirm).
/// Shared by the ConfirmManual sheet and the Edit-entry money card (P1.6
/// lifted the chip row out of the section so both use the same component).
struct CurrencyChipRow: View {
    @Binding var currency: CurrencyCode
    let homeCurrency: CurrencyCode
    let lowConfidence: Bool

    private static let chips: [CurrencyCode] = [
        .eur, .pln, .czk, CurrencyCode(rawValue: "CHF")!
    ]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Self.chips, id: \.self) { code in
                chip(code)
            }
            moreMenu
        }
    }

    private func chip(_ code: CurrencyCode) -> some View {
        let selected = currency == code
        let border = selected
            ? (lowConfidence ? Theme.Palette.warn : Theme.Palette.taillight)
            : Theme.Palette.hairline
        return Button {
            currency = code
        } label: {
            Text(chipLabel(code))
                .font(.footnote.weight(selected ? .bold : .semibold))
                .foregroundStyle(selected ? Theme.Palette.ink : Theme.Palette.inkSoft)
                .padding(.horizontal, 13)
                .padding(.vertical, 7)
                .background(Capsule().fill(selected ? Theme.Palette.taillight.opacity(0.14) : Theme.Palette.dash))
                .overlay(Capsule().stroke(border, lineWidth: selected ? 1.5 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("manualFillUpCurrency_\(code.rawValue)")
    }

    private var moreMenu: some View {
        Menu {
            ForEach(AddVehicleSupport.currencyOptions, id: \.self) { code in
                Button {
                    currency = code
                } label: {
                    Text(chipLabel(code))
                }
            }
        } label: {
            Text("More…")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.Palette.inkSoft)
                .padding(.horizontal, 13)
                .padding(.vertical, 7)
                .background(Capsule().fill(Theme.Palette.dash))
                .overlay(Capsule().stroke(Theme.Palette.hairline, lineWidth: 1))
        }
        .accessibilityIdentifier("currencyChipMore")
    }

    private func chipLabel(_ code: CurrencyCode) -> String {
        AddVehicleSupport.currencyLabel(for: code)
    }
}

/// The currency section (artboard): the chip row plus the hint that explains
/// the current conversion state (rate-pending for a foreign pick, the neutral
/// caption otherwise).
struct ManualFillUpCurrencySection: View {
    @Binding var form: ManualFillUpFormState
    let homeCurrency: CurrencyCode
    let lowConfidence: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionEyebrow("Currency")
            CurrencyChipRow(currency: $form.currency, homeCurrency: homeCurrency,
                            lowConfidence: lowConfidence)
            hint
        }
    }

    @ViewBuilder
    private var hint: some View {
        if lowConfidence {
            hintText(L10n.localize("Which currency is this?"), color: Theme.Palette.warn,
                     identifier: "manualFillUpCurrencyHint")
        } else if form.currency != homeCurrency {
            hintText(L10n.localize("≈ – · converts when online"), color: Theme.Palette.inkSoft,
                     identifier: "manualFillUpConversionHint")
        } else {
            hintText(String(format: L10n.localize("Recent first · a foreign amount converts to %@ automatically"),
                            homeCurrency.rawValue),
                     color: Theme.Palette.inkSoft, identifier: nil)
        }
    }

    private func hintText(_ text: String, color: Color, identifier: String?) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(color)
            .modifier(OptionalIdentifier(identifier: identifier))
    }
}

// MARK: - The three-number card

/// The pump-card stack (artboard): TOTAL / LITERS / PRICE PER L in DIN, with
/// live third-value derivation and the cross-check line. Two typed numbers
/// derive the third and read `.notApplicable`; three typed run the cross-check
/// (verified locks, mismatch goes amber and refuses to lock).
///
/// P2.3: the scanned path lands in this same card. Fields the extraction
/// resolved render at 60% opacity until confirmed by tap or edit (DESIGN.md) -
/// the dim is visual only, the field stays fully editable and focusable
/// (hard rule 13); a field with a crop shows the magnifier that opens the
/// source crop (tap-to-verify); the lock draw-in honours Reduce Motion.
struct ManualFillUpNumbersCard: View {
    @Binding var form: ManualFillUpFormState
    @FocusState.Binding var focus: ManualFillUpFocus?
    let volumeUnit: VolumeUnit
    let currencySymbol: String
    /// P2.3: the per-field source-image crops from the capture pipeline.
    /// Empty on the Edit-entry reuse (no scan, nothing to verify).
    var crops: [ManualFillUpMath.Field: CropEvidence] = [:]
    var reduceMotion: Bool = false
    var onVerify: (ManualFillUpMath.Field, CropEvidence) -> Void = { _, _ in }

    private var derived: ManualFillUpMath.Derived? { form.derived(volumeUnit: volumeUnit) }

    var body: some View {
        VStack(spacing: 0) {
            totalRow
            CardDivider()
            litersRow
            CardDivider()
            priceRow
            checkLine
                .padding(.vertical, 6)
        }
        .formCard()
    }

    private func binding(_ field: ManualFillUpMath.Field) -> Binding<String> {
        Binding(
            get: { form.displayText(for: field, volumeUnit: volumeUnit) ?? "" },
            set: { newValue in
                switch field {
                case .total: form.total = newValue
                case .volume: form.liters = newValue
                case .unitPrice: form.pricePerL = newValue
                }
                // Typing IS the confirmation (DESIGN.md: dimmed "until
                // confirmed by tap or edit").
                form.userConfirmedFields.insert(field)
            }
        )
    }

    private var totalRow: some View {
        figureRow(label: "Total", field: .total, unit: currencySymbol,
                  isSuspect: isSuspect(.total), identifier: "manualFillUpTotalField")
    }

    private var litersRow: some View {
        figureRow(label: "Liters", field: .volume, unit: L10n.volumeUnit(volumeUnit),
                  isSuspect: isSuspect(.volume), identifier: "manualFillUpLitersField")
    }

    private var priceRow: some View {
        VStack(spacing: 0) {
            figureRow(label: "Price / L", field: .unitPrice, unit: currencySymbol,
                      isSuspect: isSuspect(.unitPrice), identifier: "manualFillUpPricePerLField")
            if form.pricePerL.isEmpty, derived == nil {
                Text("fills in from total ÷ liters")
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.inkSoft)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.horizontal, Theme.Spacing.cardPadding)
                    .padding(.bottom, 10)
            }
        }
    }

    private func figureRow(label: LocalizedStringKey, field: ManualFillUpMath.Field,
                           unit: String, isSuspect: Bool, identifier: String) -> some View {
        let dimmed = ConfirmConfidenceGate.confidence(
            resolved: form.resolvedByExtraction.contains(field),
            crossCheck: derived?.crossCheck ?? .notApplicable,
            userConfirmed: form.userConfirmedFields.contains(field)
        ) == .unconfirmed
        return HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(Theme.Palette.inkSoft)
                .fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: 8)
            TextField("", text: binding(field))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.custom(AppFonts.dinAlternateBold, size: 28))
                .foregroundStyle(fieldIsTyped(field) ? Theme.Palette.ink : Theme.Palette.inkSoft)
                .focused($focus, equals: focusTarget(field))
                .fieldUnderline(isFocused: focus == focusTarget(field), warn: isSuspect)
                .accessibilityIdentifier(identifier)
                // The P2.3 dim: 60% opacity until the field is confirmed. The
                // field keeps every editing affordance - it is a default input
                // that stays fully editable and focusable, and VoiceOver still
                // announces it normally (hard rule 13; asserted by UI test).
                .opacity(dimmed ? ConfirmConfidenceGate.dimmedOpacity : 1)
            if let crop = crops[field], fieldHasValue(field) {
                verifyButton(field: field, crop: crop)
            }
            Text(unit)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(Theme.Palette.inkSoft)
                .opacity(dimmed ? ConfirmConfidenceGate.dimmedOpacity : 1)
        }
        .padding(.horizontal, Theme.Spacing.cardPadding)
        .padding(.vertical, 10)
    }

    /// The tap-to-verify affordance (P2.3): shows the crop of the source image
    /// this pre-filled value came from. Present only when the capture pipeline
    /// attached a crop - with none, the affordance is simply absent (degrade
    /// to a no-op, never a dead button). Tapping it confirms the field, which
    /// lifts the dim exactly as DESIGN.md's "until confirmed by tap or edit".
    private func verifyButton(field: ManualFillUpMath.Field, crop: CropEvidence) -> some View {
        Button {
            form.userConfirmedFields.insert(field)
            onVerify(field, crop)
        } label: {
            Image(systemName: "magnifyingglass")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.Palette.headlight)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(verifyLabel(field))
        .accessibilityIdentifier("manualFillUpVerifyButton_\(field.rawValue)")
    }

    private func verifyLabel(_ field: ManualFillUpMath.Field) -> LocalizedStringKey {
        switch field {
        case .total: return "Check the total on the receipt"
        case .volume: return "Check the liters on the receipt"
        case .unitPrice: return "Check the price on the receipt"
        }
    }

    @ViewBuilder
    private var checkLine: some View {
        if case .mismatch = derived?.crossCheck {
            VStack(spacing: 6) {
                Rectangle().fill(Theme.Palette.warn).frame(height: 1.5)
                Text("these don't multiply up – check the amber field")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.Palette.warn)
                    .multilineTextAlignment(.center)
            }
            .accessibilityIdentifier("manualFillUpCrossCheckMismatch")
            .padding(.horizontal, Theme.Spacing.cardPadding)
        } else {
            let locked = derived?.crossCheck == .verified
            let color: Color = locked ? Theme.Palette.taillight : Theme.Palette.inkSoft
            // Must be LocalizedStringKey, not String: `Text(_: String)` does
            // not localise, so an inferred `String` here renders the English
            // key in Russian even though the catalogue has the translation.
            let text: LocalizedStringKey = locked ? "✓" : "checks as you type"
            HStack(spacing: 10) {
                // The lock's draw-in (docs/DESIGN.md -> Motion): the rule
                // grows from the ends toward the tick. The tick itself fades
                // and scales in. A green lock proves the three numbers are
                // CONSISTENT, never that liters and price are the right way
                // round - a x b == b x a - so the lock NEVER suppresses editing
                // and NEVER gates saving (the save bar depends only on two of
                // three being typed).
                Rectangle().fill(color).frame(height: 1.5)
                    .scaleEffect(x: locked ? 1 : 0.12, anchor: .trailing)
                Text(text)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(color)
                    .lineLimit(1)
                    // The rules take whatever is left; without this the label
                    // was squeezed to "checks as you t...".
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(1)
                    .scaleEffect(locked ? 1 : 0.9)
                    .opacity(locked ? 1 : 0.85)
                Rectangle().fill(color).frame(height: 1.5)
                    .scaleEffect(x: locked ? 1 : 0.12, anchor: .leading)
            }
            .animation(reduceMotion ? nil : .spring(duration: 0.45), value: locked)
            .accessibilityIdentifier(locked ? "manualFillUpCheckLineLocked" : "manualFillUpCheckLine")
            .padding(.horizontal, Theme.Spacing.cardPadding)
            .onChange(of: locked) { _, isLocked in
                // The lock's .success beat (DESIGN.md). A no-op on the
                // simulator; a subtle confirmation on a device.
                if isLocked {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
            }
        }
    }

    private func fieldIsTyped(_ field: ManualFillUpMath.Field) -> Bool {
        switch field {
        case .total: return !form.total.isEmpty
        case .volume: return !form.liters.isEmpty
        case .unitPrice: return !form.pricePerL.isEmpty
        }
    }

    /// Whether the field currently shows a value (a pre-filled or typed one).
    /// The verify affordance only makes sense over an actual number.
    private func fieldHasValue(_ field: ManualFillUpMath.Field) -> Bool {
        fieldIsTyped(field) || derivedDisplay(field) != nil
    }

    private func derivedDisplay(_ field: ManualFillUpMath.Field) -> String? {
        switch field {
        case .total: return derived.map { ManualFillUpFormat.decimal($0.total, fractionDigits: 2) }
        case .volume: return derived.map { volume in
            ManualFillUpFormat.decimal(ManualFillUpMath.displayVolume(from: volume.volumeL, unit: volumeUnit),
                                       fractionDigits: 2)
        }
        case .unitPrice: return derived.map { ManualFillUpFormat.decimal($0.unitPrice, fractionDigits: 3) }
        }
    }

    private func focusTarget(_ field: ManualFillUpMath.Field) -> ManualFillUpFocus {
        switch field {
        case .total: return .total
        case .volume: return .liters
        case .unitPrice: return .pricePerL
        }
    }

    private func isSuspect(_ field: ManualFillUpMath.Field) -> Bool {
        guard case .mismatch(let suspect) = derived?.crossCheck else { return false }
        switch suspect {
        case .total: return field == .total
        case .volume: return field == .volume
        case .unitPrice: return field == .unitPrice
        default: return false
        }
    }
}

// MARK: - Fuel kind + full-tank toggle

struct ManualFillUpFuelFullCard: View {
    @Binding var form: ManualFillUpFormState
    let fuelKinds: [FuelKind]

    var body: some View {
        VStack(spacing: 0) {
            FieldRow("Fuel") {
                HStack(spacing: 6) {
                    ForEach(fuelKinds, id: \.self) { kind in
                        chip(kind)
                    }
                }
            }
            CardDivider()
            fullToggleRow
        }
        .formCard()
    }

    private func chip(_ kind: FuelKind) -> some View {
        let selected = form.fuelKind == kind
        return Button {
            form.fuelKind = kind
        } label: {
            Text(kind.labelKey)
                .font(.footnote.weight(selected ? .bold : .semibold))
                .foregroundStyle(selected ? Theme.Palette.ink : Theme.Palette.inkSoft)
                .padding(.horizontal, 13)
                .padding(.vertical, 7)
                .background(Capsule().fill(selected ? Theme.Palette.taillight.opacity(0.14) : Theme.Palette.dash))
                .overlay(Capsule().stroke(selected ? Theme.Palette.taillight : Theme.Palette.hairline,
                                          lineWidth: selected ? 1.5 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("manualFillUpFuelKind_\(kind.rawValue)")
    }

    private var fullToggleRow: some View {
        HStack {
            Text("Full tank")
                .font(.subheadline)
                .foregroundStyle(Theme.Palette.inkSoft)
            Spacer(minLength: 8)
            Toggle("", isOn: Binding(
                get: { form.isFull },
                set: { full in
                    form.isFull = full
                    // The 100 ⇔ full invariant (docs/SCHEMA.md): turning the
                    // toggle on is a 100% tank, turning it off from a full
                    // state is a bare partial (the tank row then offers the
                    // sheet to set a real level).
                    if full {
                        form.tankLevelAfterPct = 100
                    } else if form.tankLevelAfterPct == 100 {
                        form.tankLevelAfterPct = nil
                    }
                }
            ))
            .labelsHidden()
            .tint(Theme.Palette.taillight)
            .accessibilityIdentifier("manualFillUpIsFullToggle")
        }
        .padding(.horizontal, Theme.Spacing.cardPadding)
        .padding(.vertical, 12)
    }
}

// MARK: - Odometer

struct ManualFillUpOdometerCard: View {
    @Binding var form: ManualFillUpFormState
    @FocusState.Binding var focus: ManualFillUpFocus?
    let distanceUnit: DistanceUnit
    let conflict: OdometerConflict?
    let onFixDate: () -> Void
    /// The helper caption under the row; ConfirmManual explains the last-known
    /// pre-fill, the Edit screen passes `nil` (its odometer is not a pre-fill).
    var caption: LocalizedStringKey? = "last known · update after typing fuel"

    var body: some View {
        VStack(spacing: 0) {
            odometerRow
            if let conflict {
                warningRow(conflict)
            }
            if let caption {
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(Theme.Palette.inkSoft)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.horizontal, Theme.Spacing.cardPadding)
                    .padding(.bottom, 12)
            }
        }
        .formCard()
    }

    private var odometerRow: some View {
        FieldRow("Odometer") {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                TextField("", text: $form.odometer)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .font(.custom(AppFonts.dinAlternateBold, size: 24))
                    .foregroundStyle(Theme.Palette.ink)
                    .focused($focus, equals: .odometer)
                    .fieldUnderline(isFocused: focus == .odometer, warn: conflict != nil)
                    .accessibilityIdentifier("manualFillUpOdometerField")
                    .onChange(of: focus) { oldValue, newValue in
                        // Format-on-blur (HANDOVER.md open item 0): grouped
                        // digits belong in DISPLAY, not in a field being typed
                        // into. Focus strips the grouping, blur re-applies it.
                        if newValue == .odometer {
                            form.odometer = OdometerFormat.ungrouped(form.odometer)
                        } else if oldValue == .odometer, let value = form.odometerValue {
                            form.odometer = OdometerFormat.grouped(value)
                        }
                    }
                Text(L10n.distanceUnit(distanceUnit))
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.inkSoft)
            }
        }
    }

    private func warningRow(_ conflict: OdometerConflict) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(Theme.Palette.warn)
            VStack(alignment: .leading, spacing: 8) {
                Text(conflict.quote ?? "Odometer breaks the timeline – check it.")
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.warn)
                    .accessibilityIdentifier("manualFillUpOdometerWarning")
                HStack(spacing: 14) {
                    Button("Fix") { focus = .odometer }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.Palette.headlight)
                        .accessibilityIdentifier("manualFillUpOdometerFixButton")
                    Button("Fix date") { onFixDate() }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.Palette.headlight)
                        .accessibilityIdentifier("manualFillUpOdometerFixDateButton")
                }
                .font(.caption.weight(.semibold))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Spacing.cardPadding)
        .padding(.bottom, 10)
    }
}

// MARK: - Station

struct ManualFillUpStationRow: View {
    let stations: [Station]
    @Binding var selection: Station?

    var body: some View {
        HStack {
            Text("Station")
                .font(.subheadline)
                .foregroundStyle(Theme.Palette.inkSoft)
            Spacer(minLength: 8)
            if stations.isEmpty {
                Text("Nearby suggestion")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.Palette.headlight)
                    .accessibilityIdentifier("manualFillUpStationRow")
            } else {
                Menu {
                    ForEach(stations, id: \.id) { station in
                        Button {
                            selection = station
                        } label: {
                            Text(station.name)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(selection?.name ?? "Nearby suggestion")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.Palette.headlight)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2)
                            .foregroundStyle(Theme.Palette.inkSoft)
                    }
                }
                .accessibilityIdentifier("manualFillUpStationButton")
            }
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 4)
    }
}

// MARK: - Date

/// The date row (artboard): a label, a tappable formatted date, and the
/// graphical picker. Shared by ConfirmManual and the Edit-entry screen (P1.6
/// lifted the row's binding from the whole form to a single `Date` so both use
/// the same component). Past dates only - a fill-up cannot be logged in the
/// future.
struct ManualFillUpDateRow: View {
    @Binding var date: Date
    @Binding var showDatePicker: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Date")
                    .font(.subheadline)
                    .foregroundStyle(Theme.Palette.inkSoft)
                Spacer(minLength: 8)
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { showDatePicker.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Text(date.formatted(.dateTime.month(.abbreviated).day().year()))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.Palette.ink)
                        Image(systemName: "chevron.down")
                            .font(.caption2)
                            .foregroundStyle(Theme.Palette.inkSoft)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("entryDateButton")
            }
            .padding(.horizontal, Theme.Spacing.cardPadding)
            .padding(.vertical, 12)
            if showDatePicker {
                DatePicker("", selection: $date, in: ...Date(), displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .accessibilityIdentifier("entryDatePicker")
                    .padding(.horizontal, Theme.Spacing.cardPadding)
                    .padding(.bottom, 12)
            }
        }
        .formCard()
    }
}

// MARK: - Helper

/// Applies an accessibility identifier only when one is wanted; the plain
/// caption rows (conversion note under the currency chips) get none.
struct OptionalIdentifier: ViewModifier {
    let identifier: String?

    func body(content: Content) -> some View {
        if let identifier {
            content.accessibilityIdentifier(identifier)
        } else {
            content
        }
    }
}

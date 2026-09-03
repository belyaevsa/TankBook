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
                // P2.15: filtered here, not via `.numericInput`, because this
                // card shows a DERIVED value in an empty field - a change-based
                // filter fires on the derived figure and a write-back mid-edit
                // destabilises the cursor. Filtering in the set keeps the model
                // clean without re-rendering the field out from under the user.
                let cleaned = NumericInputSanitizer.sanitize(newValue, kind: .decimal)
                switch field {
                case .total: form.total = cleaned
                case .volume: form.liters = cleaned
                case .unitPrice: form.pricePerL = cleaned
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
                .foregroundStyle(Theme.Palette.action)
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

// MARK: - Odometer

struct ManualFillUpOdometerCard: View {
    @Binding var form: ManualFillUpFormState
    @FocusState.Binding var focus: ManualFillUpFocus?
    let distanceUnit: DistanceUnit
    let conflict: OdometerConflict?
    let onFixDate: () -> Void
    /// PJ.14: the last-known odometer reference for the live "+N km since last"
    /// caption (docs/VISION.md -> Fill-up log; docs/DESIGN.md -> the Pump
    /// Card). ConfirmManual passes the derived last known; the Edit screen
    /// passes nil (its odometer is not a pre-fill) and renders no caption.
    /// `paceLimitKmPerDay` is the vehicle's own pace rule (default 1500,
    /// docs/SCHEMA.md).
    var lastKnown: OdometerLastKnown?
    var paceLimitKmPerDay: Double = 1500

    var body: some View {
        VStack(spacing: 0) {
            odometerRow
            if let conflict {
                warningRow(conflict)
            }
            caption
        }
        .formCard()
    }

    /// PJ.14: the live delta caption, computed in core (`OdometerDelta`) so the
    /// four states are L1-testable - a view-only caption would only be reachable
    /// by XCUITest, which asserts behaviour and never values (the P3.7 lesson).
    /// Amber is attention, never alarm (hard rule 5): only a backwards odometer
    /// and an exceeded pace warn, and the caption never blocks the save - an
    /// implausible odometer warns and the user decides (hard rule 13).
    @ViewBuilder
    private var caption: some View {
        if let delta = deltaValue {
            captionText(delta)
                .font(.caption2)
                .foregroundStyle(delta.state.isWarning ? Theme.Palette.warn : Theme.Palette.inkSoft)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.horizontal, Theme.Spacing.cardPadding)
                .padding(.bottom, 12)
                .accessibilityIdentifier("manualFillUpOdometerCaption")
        }
    }

    /// The delta itself, evaluated fresh on every render so the caption reacts
    /// live as the user types (the form binding re-renders the card).
    private var deltaValue: OdometerDelta? {
        OdometerDelta.evaluate(typed: form.odometerValue,
                               lastKnown: lastKnown?.odometer,
                               lastKnownDate: lastKnown?.date,
                               entryDate: form.date,
                               paceLimitKmPerDay: paceLimitKmPerDay)
    }

    /// The localized caption per state. The forward case is an interpolated
    /// literal (`Text(_: LocalizedStringKey)`) so the catalogue's plural
    /// variations render; the warn/equal cases are plain literals. The `Text`
    /// wrapper is deliberate - a bare `LocalizedStringKey` return would hide the
    /// literals from the P0.3 localization gate.
    private func captionText(_ delta: OdometerDelta) -> Text {
        switch delta.state {
        case .forward: return Text("+\(delta.km) km since last")
        case .equal: return Text("Same as last")
        case .backwards: return Text("Odometer went backwards – check it.")
        case .pace: return Text("Daily pace over the limit – check it.")
        }
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
                    .numericInput($form.odometer, kind: .integer)
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

    /// The validator's own wording when it has one (already localised at its
    /// source), else the catalogue literal - reached through the
    /// `LocalizedStringKey` overload, which a coalesced `String?` cannot be.
    @ViewBuilder
    private func conflictText(_ conflict: OdometerConflict) -> some View {
        if let quote = conflict.quote {
            Text(quote)
        } else {
            Text("Odometer breaks the timeline – check it.")
        }
    }

    private func warningRow(_ conflict: OdometerConflict) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(Theme.Palette.warn)
            VStack(alignment: .leading, spacing: 8) {
                // Split rather than `quote ?? "literal"`: the coalesced
                // expression is a String, so `Text` takes the non-localising
                // StringProtocol overload and the fallback renders its ENGLISH
                // key in Russian - even though the catalogue holds
                // "Пробег нарушает хронологию – проверьте его.". Same defect as
                // "checks as you type" (P2.1) and the third of its kind; the
                // localization gate cannot see it, because the key IS present.
                conflictText(conflict)
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.warn)
                    .accessibilityIdentifier("manualFillUpOdometerWarning")
                HStack(spacing: 14) {
                    Button("Fix") { focus = .odometer }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.Palette.action)
                        .accessibilityIdentifier("manualFillUpOdometerFixButton")
                    Button("Fix date") { onFixDate() }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.Palette.action)
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

    /// A chosen station's name is runtime data; the placeholder is copy. Coalescing
    /// them into one `String` sends the literal through `Text(_: String)`, which
    /// does not localise - see the note atop `L10n.swift`.
    @ViewBuilder
    private func stationLabel(_ selection: Station?) -> some View {
        if let name = selection?.name {
            Text(name)
        } else {
            Text("Choose station")
        }
    }

    var body: some View {
        HStack {
            Text("Station")
                .font(.subheadline)
                .foregroundStyle(Theme.Palette.inkSoft)
            Spacer(minLength: 8)
            if stations.isEmpty {
                // Nothing to choose from yet, so nothing to tap: an honest
                // placeholder in inkSoft, never the action colour (a label that
                // looks tappable and is not is a dead control - SCREENMAP rule
                // zero). The location-based suggestion is PJ.19; until it
                // ships this row promises nothing (docs/JOURNEYS.md -> J4).
                Text("Not set")
                    .font(.subheadline)
                    .foregroundStyle(Theme.Palette.inkSoft)
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
                        // Same coalesced-String trap: a station's name is
                        // runtime data, the fallback is copy. Coalescing them
                        // makes the whole expression a String and the fallback
                        // renders its English key. Split so the literal reaches
                        // the LocalizedStringKey overload.
                        stationLabel(selection)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.Palette.action)
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
            // RV.10: the WHOLE header row is the toggle, not just the date text
            // at the far end - the eye lands on the row's left half once a
            // calendar is on screen, and only that half answered a tap before.
            // The chevron flips while the picker is open, so the one collapse
            // cue ("pointing up = collapse me") sits right above the calendar.
            // Dismissing never touches the date binding: the value the user did
            // not choose is never written (hard rule 13).
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showDatePicker.toggle() }
            } label: {
                HStack {
                    Text("Date")
                        .font(.subheadline)
                        .foregroundStyle(Theme.Palette.inkSoft)
                    Spacer(minLength: 8)
                    HStack(spacing: 6) {
                        Text(date.formatted(.dateTime.month(.abbreviated).day().year()))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.Palette.ink)
                        Image(systemName: showDatePicker ? "chevron.up" : "chevron.down")
                            .font(.caption2)
                            .foregroundStyle(Theme.Palette.inkSoft)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, Theme.Spacing.cardPadding)
            .padding(.vertical, 12)
            .accessibilityIdentifier("entryDateButton")
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

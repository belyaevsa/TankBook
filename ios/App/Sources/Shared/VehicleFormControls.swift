import PhotosUI
import SwiftUI
import TankbookCore
import UIKit

// MARK: - Numeric input filtering (P2.15)

/// Filters a numeric field's writes through `NumericInputSanitizer` as the
/// value changes, then writes the cleaned value back. The write-back is what
/// forces the TextField's display to re-sync: filtering inside a Binding's
/// `set` leaves the field showing the raw text while the model stays clean,
/// because a `set` that resolves to the previous value never re-renders the
/// TextField. `keyboardType` is a hint, not a constraint - a hardware keyboard
/// (the simulator), paste and dictation all bypass it - so every numeric field
/// routes its changes through this one place. The rule itself lives in core and
/// is unit-tested there; the app layer only applies it.
extension View {
    func numericInput(_ value: Binding<String>, kind: NumericInputSanitizer.Kind) -> some View {
        onChange(of: value.wrappedValue) { _, newValue in
            let cleaned = NumericInputSanitizer.sanitize(newValue, kind: kind)
            if cleaned != newValue {
                value.wrappedValue = cleaned
            }
        }
    }
}

// MARK: - Photo tile

/// The optional car photo tile (Add-car artboard): dashed card, system photo
/// picker, thumbnail preview once picked, remove affordance. Shared by Add car
/// and Vehicle detail so the garage photo is edited the same way in both.
struct VehiclePhotoTile: View {
    @Binding var photo: Data?
    @Binding var photoItem: PhotosPickerItem?

    var body: some View {
        let previewImage = photo.flatMap { UIImage(data: $0) }
        let hasPhoto = photo != nil
        return HStack(spacing: 12) {
            PhotosPicker(selection: $photoItem, matching: .images) {
                HStack(spacing: 12) {
                    Group {
                        if let previewImage {
                            Image(uiImage: previewImage)
                                .resizable()
                                .scaledToFill()
                        } else {
                            Image(systemName: "camera")
                                .font(.system(size: 18))
                                .foregroundStyle(Theme.Palette.action)
                        }
                    }
                    .frame(width: 44, height: 44)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Theme.Palette.midnight))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(hasPhoto ? "Replace photo" : "Add a photo")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.Palette.action)
                        Text("Shown on the garage card")
                            .font(.caption2)
                            .foregroundStyle(Theme.Palette.inkSoft)
                    }
                }
            }
            .accessibilityIdentifier("vehiclePhotoButton")

            if hasPhoto {
                Button {
                    photo = nil
                    photoItem = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.Palette.inkSoft)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("vehiclePhotoRemoveButton")
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Theme.Palette.dash)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Theme.Palette.inkSoft.opacity(0.35),
                              style: StrokeStyle(lineWidth: 1.5, dash: [6]))
        )
        .onChange(of: photoItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self) {
                    photo = data
                }
            }
        }
    }
}

// MARK: - Identity card (Name / Make · model · year / Plate)

/// The three-row identity card plus the empty-name warn (docs/ERRORS.md ->
/// Add car, row 1: "Name empty on save"). Shared by Add car and Vehicle detail:
/// a name a user can correct only once is the exact hard-rule-13 violation
/// P1.12 exists to remove, so both screens edit through the same rows.
struct VehicleIdentityCard: View {
    @Binding var name: String
    @Binding var makeModel: String
    @Binding var plate: String
    @Binding var make: String?
    @Binding var model: String?
    @Binding var year: Int?
    @FocusState.Binding var focus: AddVehicleFocus?
    let showNameWarning: Bool
    var idPrefix: String = "addVehicle"

    var body: some View {
        VStack(spacing: 0) {
            nameRow
            CardDivider()
            makeModelRow
            CardDivider()
            plateRow
        }
        .formCard()
    }

    private var nameRow: some View {
        VStack(spacing: 0) {
            FieldRow("Name") {
                TextField("", text: $name)
                    .multilineTextAlignment(.trailing)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.Palette.ink)
                    .focused($focus, equals: .name)
                    .fieldUnderline(isFocused: focus == .name, warn: showNameWarning)
                    .accessibilityIdentifier("\(idPrefix)NameField")
            }
            if showNameWarning {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(Theme.Palette.warn)
                    Text("Give the car any name – you can change it later.")
                        .font(.caption)
                        .foregroundStyle(Theme.Palette.warn)
                        .accessibilityIdentifier("\(idPrefix)NameWarning")
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.Spacing.cardPadding)
                .padding(.bottom, 10)
            }
        }
    }

    private var makeModelRow: some View {
        FieldRow("Make · model · year") {
            TextField("", text: $makeModel)
                .multilineTextAlignment(.trailing)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.Palette.ink)
                .focused($focus, equals: .makeModel)
                .accessibilityIdentifier("\(idPrefix)MakeModelField")
                .onChange(of: makeModel) { _, newValue in
                    let parsed = MakeModelParser.parse(newValue)
                    make = parsed.make
                    model = parsed.model
                    year = parsed.year
                }
        }
    }

    private var plateRow: some View {
        FieldRow("Plate") {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                TextField("", text: $plate)
                    .multilineTextAlignment(.trailing)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.Palette.ink)
                    .focused($focus, equals: .plate)
                    .accessibilityIdentifier("\(idPrefix)PlateField")
                Text("Optional")
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.inkSoft)
            }
        }
    }
}

// Shared vehicle-form controls, lifted out of AddVehicle (P1.12) so the Add
// car screen and the Vehicle detail screen render the SAME chips, pickers and
// fields. A second divergent copy of the fuel-kind pills or the capacity field
// is exactly how two screens that edit the same `Vehicle` drift apart, so both
// edit through these. Every component takes explicit bindings - no screen's
// form state leaks into another's. `idPrefix` keeps the accessibility
// identifiers screen-specific (a UI test on one screen must not match the
// other screen's elements).

/// The four-way powertrain segmented control (the Add-car artboard). Fuel
/// compatibility is re-derived on switch so the pills never contradict the
/// powertrain.
struct VehiclePowertrainPicker: View {
    @Binding var powertrain: Powertrain
    @Binding var selectedFuelKinds: Set<FuelKind>
    var idPrefix: String = "addVehicle"

    var body: some View {
        HStack(spacing: 6) {
            ForEach([Powertrain.ice, .hybrid, .phev, .ev], id: \.self) { power in
                powertrainButton(power)
            }
        }
    }

    private func powertrainButton(_ power: Powertrain) -> some View {
        let selected = powertrain == power
        return Button {
            select(power)
        } label: {
            Text(power.labelKey)
                .font(.footnote.weight(selected ? .bold : .semibold))
                .foregroundStyle(selected ? Theme.Palette.ink : Theme.Palette.inkSoft)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 11)
                        .fill(selected ? Theme.Palette.taillight.opacity(0.14) : Theme.Palette.dash)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 11)
                        .stroke(selected ? Theme.Palette.taillight : Theme.Palette.hairline,
                                lineWidth: selected ? 1.5 : 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("\(idPrefix)Powertrain\(power.rawValue.uppercased())")
    }

    private func select(_ power: Powertrain) {
        powertrain = power
        let compatible = selectedFuelKinds.filter { power.allowedFuelKinds.contains($0) }
        selectedFuelKinds = compatible.isEmpty ? Set(power.defaultFuelKinds) : Set(compatible)
    }
}

/// The fuel-kind chip row (the Add-car artboard), plus the "+" menu for kinds
/// outside the current powertrain's default set. Chips are toggles; every value
/// stays user-overridable (hard rule 13).
struct VehicleFuelPills: View {
    @Binding var powertrain: Powertrain
    @Binding var selectedFuelKinds: Set<FuelKind>
    var idPrefix: String = "addVehicle"

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 68), spacing: 6, alignment: .leading)],
                      alignment: .leading, spacing: 6) {
                ForEach(chipKinds, id: \.self) { kind in
                    pill(kind)
                }
                if !remainingKinds.isEmpty {
                    addFuelMenu
                }
            }
            if !FuelKind.isRealisticCombination(selectedFuelKinds) {
                discouragementNote
            }
        }
    }

    /// P2.3c (2026-08-30): diesel + petrol stays DISCOURAGED but savable. The
    /// pair is almost certainly a misconfigured car, but a wrong configuration
    /// is correctable and is not a data-integrity failure, so nothing may be
    /// blocked (hard rule 13). The note appears only once the pair is actually
    /// selected - it never appears mid-selection as a threat, and it never
    /// gates the save.
    private var discouragementNote: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption2)
                .foregroundStyle(Theme.Palette.warn)
            Text("Diesel and petrol don't normally share a car – check it.")
                .font(.caption)
                .foregroundStyle(Theme.Palette.warn)
                .accessibilityIdentifier("\(idPrefix)FuelKindWarning")
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var chipKinds: [FuelKind] {
        Array(Set(powertrain.allowedFuelKinds).union(selectedFuelKinds))
            .sorted { lhs, rhs in
                (FuelKind.allCases.firstIndex(of: lhs) ?? 0) < (FuelKind.allCases.firstIndex(of: rhs) ?? 0)
            }
    }

    private var remainingKinds: [FuelKind] {
        FuelKind.allCases.filter { !chipKinds.contains($0) }
    }

    private func pill(_ kind: FuelKind) -> some View {
        let selected = selectedFuelKinds.contains(kind)
        return Button {
            toggle(kind)
        } label: {
            Text(kind.labelKey)
                .font(.footnote.weight(selected ? .bold : .semibold))
                .foregroundStyle(selected ? Theme.Palette.ink : Theme.Palette.inkSoft)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Capsule().fill(selected ? Theme.Palette.taillight.opacity(0.14) : Theme.Palette.dash))
                .overlay(
                    Capsule().stroke(selected ? Theme.Palette.taillight : Theme.Palette.hairline,
                                     lineWidth: selected ? 1.5 : 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("\(idPrefix)FuelKind_\(kind.rawValue)")
    }

    /// P2.3c (2026-08-30): toggling is always allowed. `isRealisticCombination`
    /// now only feeds the discouragement note above - diesel + petrol is
    /// savable, never refused (hard rule 13).
    private func toggle(_ kind: FuelKind) {
        if selectedFuelKinds.contains(kind) {
            selectedFuelKinds.remove(kind)
        } else {
            selectedFuelKinds.insert(kind)
        }
    }

    private var addFuelMenu: some View {
        Menu {
            ForEach(remainingKinds, id: \.self) { kind in
                Button {
                    toggle(kind)
                } label: {
                    Text(kind.labelKey)
                }
                .accessibilityIdentifier("\(idPrefix)AddFuelMenu_\(kind.rawValue)")
            }
        } label: {
            Text("+")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.Palette.inkSoft)
                .frame(minWidth: 24)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Capsule().fill(Theme.Palette.dash))
                .overlay(Capsule().stroke(Theme.Palette.hairline, lineWidth: 1))
        }
        .accessibilityIdentifier("\(idPrefix)AddFuelMenu")
    }
}

/// The tank/battery capacity row. For EV the single capacity field is battery
/// kWh, else tank L (the "Improves accuracy · optional" section on Add car).
/// `tankCapacityL` feeds partial-fill math, which is why the "enables
/// partial-fill math" caption appears only for a tank.
struct VehicleCapacityField: View {
    @Binding var capacity: String
    let isElectric: Bool
    let volumeUnit: VolumeUnit
    @FocusState.Binding var focus: AddVehicleFocus?
    var idPrefix: String = "addVehicle"

    var body: some View {
        FieldRow(isElectric ? "Battery capacity" : "Tank capacity") {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                TextField("", text: $capacity)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.Palette.ink)
                    .focused($focus, equals: .capacity)
                    .accessibilityIdentifier("\(idPrefix)TankCapacityField")
                    .numericInput($capacity, kind: .decimal)
                Text(isElectric ? L10n.kWh : L10n.volumeUnit(volumeUnit))
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.inkSoft)
                if !isElectric, !capacity.isEmpty {
                    Text("· enables partial-fill math")
                        .font(.caption)
                        .foregroundStyle(Theme.Palette.inkSoft)
                }
            }
        }
    }
}

/// The home-currency picker menu (the "Home currency" row). The offered set is
/// the same on every screen so Add car and Vehicle detail can never offer
/// different currencies (AddVehicleSupport.currencyOptions).
struct VehicleHomeCurrencyMenu: View {
    @Binding var currency: CurrencyCode
    var idPrefix: String = "addVehicle"

    var body: some View {
        Menu {
            ForEach(AddVehicleSupport.currencyOptions, id: \.self) { code in
                Button {
                    currency = code
                } label: {
                    Text(AddVehicleSupport.currencyLabel(for: code))
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(AddVehicleSupport.currencyLabel(for: currency))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.Palette.ink)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(Theme.Palette.inkSoft)
            }
        }
        .accessibilityIdentifier("\(idPrefix)HomeCurrencyMenu")
    }
}

/// The odometer text field with the format-on-blur behaviour (HANDOVER.md open
/// item 0: grouping is DISPLAY only - focus strips the thin-space grouping,
/// blur re-applies it). The value parses through `OdometerFormat.ungrouped`, so
/// Add car and Vehicle detail can never disagree about what a typed reading
/// means. `onEdit` fires on every keystroke (the Add-car warn's
/// "engaged with the field" latch).
struct VehicleOdometerField: View {
    @Binding var odometer: String
    @FocusState.Binding var focus: AddVehicleFocus?
    let distanceUnit: DistanceUnit
    let warn: Bool
    var idPrefix: String = "addVehicle"
    var onEdit: () -> Void = {}

    private var odometerValue: Int? {
        let trimmed = odometer.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : Int(OdometerFormat.ungrouped(trimmed))
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            TextField("", text: $odometer)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .font(.custom(AppFonts.dinAlternateBold, size: 19))
                .foregroundStyle(Theme.Palette.ink)
                .focused($focus, equals: .odometer)
                .fieldUnderline(isFocused: focus == .odometer, warn: warn)
                .accessibilityIdentifier("\(idPrefix)OdometerField")
                .numericInput($odometer, kind: .integer)
                .onChange(of: odometer) { _, _ in onEdit() }
                .onChange(of: focus) { oldValue, newValue in
                    if newValue == .odometer {
                        odometer = OdometerFormat.ungrouped(odometer)
                    } else if oldValue == .odometer, let value = odometerValue {
                        odometer = OdometerFormat.grouped(value)
                    }
                }
            Text(L10n.distanceUnit(distanceUnit))
                .font(.caption)
                .foregroundStyle(Theme.Palette.inkSoft)
        }
    }
}

// MARK: - Units editor (Vehicle detail only)

/// The per-car units editor (docs/DESIGN.md: units live on each car in the
/// Garage, never in Settings). Each of the four unit axes is its own menu;
/// changing one cascades the coherent companions (picking MPG implies mi + gal,
/// picking L/100 implies km + L - the app suggests, the user decides: every
/// value stays overridable after the cascade). See VehicleUnitsEditor.swift.

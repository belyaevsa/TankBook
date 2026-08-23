import PhotosUI
import SwiftUI
import TankbookCore
import UIKit

// MARK: - Photo tile

/// The optional car photo tile (artboard): dashed card, system photo picker,
/// thumbnail preview once picked, remove affordance.
struct AddVehiclePhotoTile: View {
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
                                .foregroundStyle(Theme.Palette.headlight)
                        }
                    }
                    .frame(width: 44, height: 44)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Theme.Palette.midnight))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(hasPhoto ? "Replace photo" : "Add a photo")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.Palette.headlight)
                        Text("Shown on the garage card")
                            .font(.caption2)
                            .foregroundStyle(Theme.Palette.inkSoft)
                    }
                }
            }
            .accessibilityIdentifier("addVehiclePhotoButton")

            if hasPhoto {
                Button {
                    photo = nil
                    photoItem = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.Palette.inkSoft)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("addVehiclePhotoRemoveButton")
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

// MARK: - Powertrain picker

/// The four-way powertrain segmented control (artboard). Fuel compatibility is
/// re-derived on switch so the chips never contradict the powertrain.
struct AddVehiclePowertrainPicker: View {
    @Binding var form: AddVehicleFormState

    var body: some View {
        HStack(spacing: 6) {
            ForEach([Powertrain.ice, .hybrid, .phev, .ev], id: \.self) { power in
                powertrainButton(power)
            }
        }
    }

    private func powertrainButton(_ power: Powertrain) -> some View {
        let selected = form.powertrain == power
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
        .accessibilityIdentifier("addVehiclePowertrain\(power.rawValue.uppercased())")
    }

    private func select(_ power: Powertrain) {
        form.powertrain = power
        let compatible = form.selectedFuelKinds.filter { power.allowedFuelKinds.contains($0) }
        form.selectedFuelKinds = compatible.isEmpty ? Set(power.defaultFuelKinds) : Set(compatible)
    }
}

// MARK: - Fuel pills

/// The fuel-kind chip row (artboard), plus the "+" menu for kinds outside the
/// current powertrain's default set. Chips are toggles; every value stays
/// user-overridable.
struct AddVehicleFuelPills: View {
    @Binding var form: AddVehicleFormState

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 68), spacing: 6, alignment: .leading)],
                  alignment: .leading, spacing: 6) {
            ForEach(chipKinds, id: \.self) { kind in
                pill(kind)
            }
            if !remainingKinds.isEmpty {
                addFuelMenu
            }
        }
    }

    private var chipKinds: [FuelKind] {
        Array(Set(form.powertrain.allowedFuelKinds).union(form.selectedFuelKinds))
            .sorted { lhs, rhs in
                (FuelKind.allCases.firstIndex(of: lhs) ?? 0) < (FuelKind.allCases.firstIndex(of: rhs) ?? 0)
            }
    }

    private var remainingKinds: [FuelKind] {
        FuelKind.allCases.filter { !chipKinds.contains($0) }
    }

    private func pill(_ kind: FuelKind) -> some View {
        let selected = form.selectedFuelKinds.contains(kind)
        return Button {
            if selected {
                form.selectedFuelKinds.remove(kind)
            } else {
                form.selectedFuelKinds.insert(kind)
            }
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
        .accessibilityIdentifier("addVehicleFuelKind_\(kind.rawValue)")
    }

    private var addFuelMenu: some View {
        Menu {
            ForEach(remainingKinds, id: \.self) { kind in
                Button {
                    form.selectedFuelKinds.insert(kind)
                } label: {
                    Text(kind.labelKey)
                }
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
        .accessibilityIdentifier("addVehicleAddFuelMenu")
    }
}

// MARK: - Odometer + currency card

/// Odometer row with its warn (error-state 2, "Fix · confirm it's right" -
/// never blocks) and the locale-defaulted home currency row.
struct AddVehicleOdometerCard: View {
    @Binding var form: AddVehicleFormState
    @FocusState.Binding var focus: AddVehicleFocus?
    let units: Vehicle.Units

    var body: some View {
        VStack(spacing: 0) {
            odometerRow
            if form.showOdometerWarning {
                odometerWarningRow
            }
            CardDivider()
            homeCurrencyRow
        }
        .formCard()
    }

    private var odometerRow: some View {
        FieldRow("Current odometer") {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                TextField("", text: $form.odometer)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .font(.custom(AppFonts.dinAlternateBold, size: 19))
                    .foregroundStyle(Theme.Palette.ink)
                    .focused($focus, equals: .odometer)
                    .fieldUnderline(isFocused: focus == .odometer, warn: false)
                    .accessibilityIdentifier("addVehicleOdometerField")
                    .onChange(of: form.odometer) { _, _ in
                        form.odometerTouched = true
                    }
                Text(L10n.distanceUnit(units.distance))
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.inkSoft)
            }
        }
    }

    private var odometerWarningRow: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(Theme.Palette.warn)
            VStack(alignment: .leading, spacing: 8) {
                Text("That's the total distance the car has driven – check the dashboard.")
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.warn)
                    .accessibilityIdentifier("addVehicleOdometerWarning")
                HStack(spacing: 14) {
                    Button("Fix") {
                        focus = .odometer
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.Palette.headlight)
                    .accessibilityIdentifier("addVehicleOdometerFixButton")
                    Button("It's right") {
                        form.odometerConfirmed = true
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.Palette.headlight)
                    .accessibilityIdentifier("addVehicleOdometerConfirmButton")
                }
                .font(.caption.weight(.semibold))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Spacing.cardPadding)
        .padding(.bottom, 12)
    }

    private var homeCurrencyRow: some View {
        FieldRow("Home currency") {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Menu {
                    ForEach(AddVehicleSupport.currencyOptions, id: \.self) { code in
                        Button {
                            form.homeCurrency = code
                        } label: {
                            Text("\(code.rawValue) \(AddVehicleSupport.currencySymbol(for: code))")
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(currencyLabel)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.Palette.ink)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2)
                            .foregroundStyle(Theme.Palette.inkSoft)
                    }
                }
                .accessibilityIdentifier("addVehicleHomeCurrencyMenu")
                Text("· stats shown in this")
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.inkSoft)
            }
        }
    }

    private var currencyLabel: String {
        "\(form.homeCurrency.rawValue) \(AddVehicleSupport.currencySymbol(for: form.homeCurrency))"
    }
}

// MARK: - Improves accuracy card (capacity + units)

/// Tank/battery capacity (the "Improves accuracy · optional" section) and the
/// units row. For EV the single capacity field is battery kWh, else tank L.
struct AddVehicleAccuracyCard: View {
    @Binding var form: AddVehicleFormState
    @FocusState.Binding var focus: AddVehicleFocus?
    let units: Vehicle.Units

    var body: some View {
        VStack(spacing: 0) {
            capacityRow
            CardDivider()
            unitsRow
        }
        .formCard()
    }

    private var capacityRow: some View {
        let isElectric = form.powertrain == .ev
        return FieldRow(isElectric ? "Battery capacity" : "Tank capacity") {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                TextField("", text: $form.capacity)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.Palette.ink)
                    .focused($focus, equals: .capacity)
                    .accessibilityIdentifier("addVehicleTankCapacityField")
                Text(isElectric ? L10n.kWh : L10n.volumeUnit(units.volume))
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.inkSoft)
                if !isElectric, !form.capacity.isEmpty {
                    Text("· enables partial-fill math")
                        .font(.caption)
                        .foregroundStyle(Theme.Palette.inkSoft)
                }
            }
        }
    }

    private var unitsRow: some View {
        FieldRow("Units") {
            Text(unitsLabel)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.Palette.ink)
                .accessibilityIdentifier("addVehicleUnitsRow")
        }
    }

    private var unitsLabel: String {
        let distance = L10n.distanceUnit(units.distance)
        let volume = L10n.volumeUnit(units.volume)
        let consumption = L10n.consumptionUnit(units.consumption)
        return "\(distance) · \(volume) · \(consumption)"
    }
}

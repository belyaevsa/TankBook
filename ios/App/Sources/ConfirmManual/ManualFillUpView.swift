import os
import SwiftUI
import TankbookCore

/// The ConfirmManual sheet (P1.3): the manual fill-up form, and the fallback
/// the whole capture pipeline degrades to (docs/JOURNEYS.md F1 - the failure
/// state IS this form). Stands alone: no camera, no OCR, no network.
///
/// Matches design/screens/ConfirmManual.dc.html: the three-number card with
/// live derivation and the cross-check line, fuel kind, full-tank toggle, the
/// last-known odometer, station, date, and the taillight Save bar. The core
/// rule (docs/SCHEMA.md -> FillUp): type any two of total / litres / price, the
/// third derives on save and `crossCheck = .notApplicable`; type all three and
/// the cross-check applies. Money is always a pair (hard rule 3) - with no
/// rates service a foreign currency saves rate-pending ("≈ – · converts when
/// online") and backfills later, never silently converted.
struct ManualFillUpView: View {
    @Binding var hasUnsavedChanges: Bool
    @Environment(\.dismiss) private var dismiss

    @State private var form = ManualFillUpFormState()
    @FocusState private var focus: ManualFillUpFocus?
    @State private var vehicle: Vehicle?
    @State private var existingEntries: [any Entry] = []
    @State private var stations: [Station] = []
    @State private var selectedStation: Station?
    @State private var currencyLowConfidence = false
    @State private var showDatePicker = false
    @State private var showTankLevel = false
    @State private var didLoad = false

    private static let log = Logger(subsystem: "app.tankbook", category: "confirmManual")

    private var volumeUnit: VolumeUnit { vehicle?.units.volume ?? .l }
    private var distanceUnit: DistanceUnit { vehicle?.units.distance ?? .km }

    var body: some View {
        ScrollView {
            VStack(spacing: 9) {
                if vehicle == nil {
                    noVehicleCard
                } else {
                    ManualFillUpCurrencySection(
                        form: $form,
                        homeCurrency: vehicle!.homeCurrency,
                        lowConfidence: currencyLowConfidence)
                    ManualFillUpNumbersCard(
                        form: $form, focus: $focus,
                        volumeUnit: volumeUnit,
                        currencySymbol: currencySymbol)
                    ManualFillUpFuelFullCard(form: $form, fuelKinds: vehicle!.fuelKinds)
                    if !form.isFull {
                        TankLevelRow(isFull: form.isFull,
                                     tankLevelAfterPct: form.tankLevelAfterPct,
                                     action: { showTankLevel = true })
                            .formCard()
                    }
                    ManualFillUpOdometerCard(
                        form: $form, focus: $focus,
                        distanceUnit: distanceUnit,
                        conflict: odometerConflict,
                        onFixDate: { showDatePicker = true })
                    ManualFillUpStationRow(stations: stations, selection: $selectedStation)
                    ManualFillUpDateRow(date: $form.date, showDatePicker: $showDatePicker)
                }
            }
            .padding(.horizontal, Theme.Spacing.screenMargin)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.immediately)
        .background(Theme.Palette.midnight)
        .safeAreaInset(edge: .bottom) { saveBar }
        .task { await load() }
        .sheet(isPresented: $showTankLevel) {
            DiscardAwareSheet(policy: .discardSilently, hasUnsavedChanges: .constant(false)) {
                TankLevelSheet(tankLevelAfterPct: $form.tankLevelAfterPct,
                               isFull: $form.isFull,
                               capacityL: vehicle?.tankCapacityL)
                    .navigationTitle("Tank level")
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
        .onChange(of: form, initial: true) { _, newValue in
            if let vehicle {
                hasUnsavedChanges = newValue.hasEdits(vehicle: vehicle)
            }
        }
    }

    private var currencySymbol: String {
        AddVehicleSupport.currencySymbol(for: form.currency)
    }

    private var odometerConflict: OdometerConflict? {
        guard let vehicle else { return nil }
        return form.odometerConflict(vehicle: vehicle,
                                     existingEntries: existingEntries,
                                     distanceUnit: distanceUnit)
    }

    // MARK: - Loading

    private func load() async {
        guard !didLoad else { return }
        didLoad = true
        ManualFillUpTestSeed.seedIfRequested()
        do {
            let repository = try AppStore.repository()
            let vehicles = try repository.liveVehicles()
            let preferences = try? repository.livePreferences()
            guard let vehicle = Self.pickVehicle(vehicles, defaultID: preferences?.defaultVehicleId) else {
                return
            }
            self.vehicle = vehicle
            existingEntries = try repository.liveEntries(forVehicle: vehicle.id)
            stations = try repository.liveStations()
            form.currency = vehicle.homeCurrency
            form.fuelKind = vehicle.fuelKinds.first ?? .petrol95
            let lastKnown = existingEntries.compactMap(\.odometer).max() ?? vehicle.initialOdometer
            form.odometer = lastKnown.map(String.init) ?? ""
            form.initialOdometer = form.odometer
            form.initialDate = form.date
            currencyLowConfidence = ProcessInfo.processInfo.arguments.contains("-forceCurrencyLowConfidence")
            if ProcessInfo.processInfo.arguments.contains("-screenshotPrefill") {
                // Screenshot hook: land the three-number card in its derived
                // state (total + liters typed, price fills in) without typing.
                form.total = "71.02"
                form.liters = "42.30"
            }
        } catch {
            Self.log.error("Manual fill-up load failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func pickVehicle(_ vehicles: [Vehicle], defaultID: UUID?) -> Vehicle? {
        if let defaultID, let match = vehicles.first(where: { $0.id == defaultID }) {
            return match
        }
        return vehicles.first
    }

    // MARK: - Save

    private var saveEnabled: Bool {
        guard let vehicle else { return false }
        return form.canSave(volumeUnit: volumeUnit)
    }

    private func save() {
        guard let vehicle, let derived = form.derived(volumeUnit: volumeUnit) else { return }
        do {
            let repository = try AppStore.repository()
            let toSave = buildFillUp(vehicle: vehicle, derived: derived)
            try repository.upsertFillUp(toSave)
            hasUnsavedChanges = false
            dismiss()
        } catch {
            Self.log.error("Manual fill-up save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// provenance = .manual, the derived third value, and the engine's verdict.
    /// The conflict flag is written from `TimelineValidator` - saving is never
    /// blocked, a flagged entry surfaces its amber badge later.
    private func buildFillUp(vehicle: Vehicle, derived: ManualFillUpMath.Derived) -> FillUp {
        let now = Date()
        let money = Money(amount: derived.total, currency: form.currency,
                          homeCurrency: vehicle.homeCurrency)
        var candidate = FillUp(
            id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
            vehicleId: vehicle.id, date: form.date, odometer: form.odometerValue,
            money: money, note: nil, attachments: [], provenance: .manual,
            conflict: .none, purchaseGroupId: nil,
            volumeL: derived.volumeL, unitPrice: derived.unitPrice,
            fuelKind: form.fuelKind, fuelGrade: nil, isFull: form.isFull,
            tankLevelAfterPct: form.isFull ? 100 : form.tankLevelAfterPct,
            stationId: selectedStation?.id,
            crossCheck: derived.crossCheck, extraction: nil)
        let validations = TimelineValidator.validate(entries: existingEntries + [candidate],
                                                     vehicle: vehicle)
        candidate.conflict = validations.first { $0.entryID == candidate.id }?.conflict ?? .none
        return candidate
    }

    // MARK: - Save bar

    private var saveBar: some View {
        VStack(spacing: 8) {
            Button(action: save) {
                Text("Save fill-up")
                    .font(.body.weight(.bold))
                    .foregroundStyle(saveEnabled ? Color.white : Theme.Palette.inkSoft)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(saveEnabled ? Theme.Palette.taillight : Theme.Palette.dash)
                    .clipShape(RoundedRectangle(cornerRadius: 15))
                    .shadow(color: saveEnabled ? Theme.Palette.taillight.opacity(0.3) : .clear,
                            radius: 18, y: 4)
            }
            .buttonStyle(.plain)
            .disabled(!saveEnabled)
            .accessibilityIdentifier("manualFillUpSaveButton")

            if !saveEnabled {
                Text("Enter total and liters to save")
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.inkSoft)
                    .accessibilityIdentifier("manualFillUpSaveHint")
            }
        }
        .padding(.horizontal, Theme.Spacing.screenMargin)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .background(Theme.Palette.midnight)
    }

    // MARK: - No vehicle

    private var noVehicleCard: some View {
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

// MARK: - Focus

/// Which ConfirmManual field holds focus (drives the cyan underline).
enum ManualFillUpFocus: Hashable {
    case total, liters, pricePerL, odometer
}

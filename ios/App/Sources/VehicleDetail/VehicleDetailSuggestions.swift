import SwiftUI
import TankbookCore

// MARK: - Vehicle detail: Make · model · year suggestions (RV.137)

/// The Vehicle-detail half of the shared catalogue picker: what a typed query
/// offers and what picking one means. The suggestion rows themselves live in
/// Shared/VehicleCatalogSuggestionsArea.swift - one implementation for Add car
/// and this screen (a second suggester is the duplication RV.129 names). This
/// extension is kept out of VehicleDetailView.swift's body to stay under the
/// file/type lint budget (the resolvePresentationTarget pattern).
///
/// The screen makes hard rule 13's permanence real: nothing here stores a
/// catalogue id for a later pack to rewrite (VehicleDetailView.swift's header),
/// so a pick writes make, model and year as TEXT the user owns, exactly as
/// typing them would, and touches nothing else.
extension VehicleDetailView {
    /// Whether the catalog suggestion list is mounted. The same gate as Add
    /// car (RV.67): a pure function of the field text and the applied state,
    /// never of focus - so the scroll that dismisses the keyboard cannot
    /// unmount the very list it reaches for. `acceptedModelText` starts at the
    /// loaded text, so merely focusing the filled field offers nothing; the
    /// list mounts when the user edits it into a new query.
    var showsModelSuggestions: Bool {
        ModelSuggestionGate.shouldShow(query: form.makeModel, accepted: acceptedModelText)
    }

    /// The mounted suggestion list below the identity card, gated on the field
    /// reading as a NEW query (never on focus alone).
    @ViewBuilder
    var makeModelSuggestions: some View {
        if showsModelSuggestions {
            VehicleCatalogSuggestionsArea(query: form.makeModel,
                                          entries: catalogEntries,
                                          units: form.units,
                                          idPrefix: "vehicleDetail",
                                          onApply: applyMakeModelSuggestion)
        }
    }

    /// Selecting a suggestion fills make, model and year as TEXT the user owns
    /// (form.applyMakeModelSuggestion), and no name, powertrain, fuel or units.
    /// RV.182: the row also shows a tank/battery volume, so the pick fills a
    /// BLANK capacity with it (blank fields only - a capacity the user typed is
    /// never touched, hard rule 13). No catalogue identifier is recorded (the
    /// permanence decision in VehicleDetailView.swift's header). The applied
    /// text is recorded before the field holds it so the list unmounts (query ==
    /// accepted) and the user sees the pick; clearing focus drops the keyboard.
    func applyMakeModelSuggestion(_ prefill: CatalogPrefill) {
        acceptedModelText = VehicleDetailFormState.makeModelText(make: prefill.make,
                                                                 model: prefill.model,
                                                                 year: prefill.year)
        form.applyMakeModelSuggestion(prefill)
        focus = nil
    }

    /// The bundled catalog seed (the same store Add car loads): populated on a
    /// fresh install, no network. A missing bundle is a build defect; the edit
    /// screen simply offers no rows and nothing errors (hard rule 7 has no
    /// user-facing state to name here).
    func loadCatalog() {
        if let entries = try? VehicleCatalogStore.bundledEntries() {
            catalogEntries = entries
        }
    }
}

#if DEBUG
extension VehicleDetailView {
    /// RV.137 screenshot hooks for the Make · model field, driven here because
    /// simctl cannot tap or type (the Add-car hook pattern).
    ///
    /// `-vehicleDetailModelSuggestions` edits the field into a five-row query
    /// ("Lada") and focuses it, so a capture shows the suggestion list WITH the
    /// keyboard raised - the state the owner reported as "picker stopped
    /// working", now served on the edit screen. `acceptedModelText` still holds
    /// the loaded text, so the edit reads as a new query and the list mounts.
    ///
    /// `-vehicleDetailKeyboardUp` focuses the field WITHOUT editing it: the
    /// loaded text is the accepted text, so no list mounts and the fuel chips
    /// sit at their natural place above the keyboard - the fuel-chip visibility
    /// half of the report. The text is set first and the focus lands a beat
    /// later, once the screen is on screen, so the keyboard actually raises.
    func presentModelSuggestionsIfRequested() async {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("-vehicleDetailModelSuggestions")
            || arguments.contains("-vehicleDetailKeyboardUp") else { return }
        try? await Task.sleep(nanoseconds: 700_000_000)
        if arguments.contains("-vehicleDetailModelSuggestions") {
            form.makeModel = "Lada"
        }
        focus = .makeModel
    }

    /// RV.182 screenshot poses `-vehicleDetailCatalogFillLitres` /
    /// `-vehicleDetailCatalogFillGallons`: simctl cannot tap a suggestion row, so
    /// this empties the capacity field (the blank state the fix fills) and
    /// applies the catalogue pick the capture must show. Both poses pick the
    /// Granta, whose 50 L differs from the seeded Volvo's own 71 L - so the
    /// capture shows a FILLED value, not the car's loaded one (litres: `50 L`,
    /// gallons: `13.2 gal`, the same pair the Add-car RV.69 captures use).
    /// Screenshot-only.
    func applyCatalogFillForScreenshot() async {
        let arguments = ProcessInfo.processInfo.arguments
        let litres = arguments.contains("-vehicleDetailCatalogFillLitres")
        let gallons = arguments.contains("-vehicleDetailCatalogFillGallons")
        guard litres || gallons else { return }
        guard let entries = try? VehicleCatalogStore.bundledEntries() else { return }
        guard let granta = entries.first(where: { $0.make == "Lada" && $0.model == "Granta" }) else {
            return
        }
        try? await Task.sleep(nanoseconds: 700_000_000)
        if gallons {
            form.units.volume = .galUS
            // Let the units editor's onChange fire (it reconverts the loaded
            // tank) BEFORE the pick fills the blank field; applying in the same
            // synchronous step would let the reconvert reinterpret the filled
            // gallons figure as litres (RV.69).
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        form.capacity = ""
        applyMakeModelSuggestion(granta.prefill(currentYear: 2026))
    }
}
#endif

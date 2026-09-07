// MARK: - Vehicle delete confirmation (RV.99)

extension L10n {
    /// "Delete Volvo V60?" - the Vehicle detail destructive confirmation's
    /// title names the car about to be tombstoned (RV.99). One full localised
    /// phrase per language - never a concatenation of "Delete" + name: the
    /// name is runtime data sharing the sentence, and RU quotes it as a
    /// nominative apposition (docs/LOCALIZATION.md), so the verb governs no
    /// case the app cannot decline.
    static func vehicleDeleteConfirmTitle(name: String) -> String {
        String(format: localize("Delete %@?"), name)
    }
}

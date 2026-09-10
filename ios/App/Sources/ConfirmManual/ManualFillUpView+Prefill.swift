import SwiftUI
import TankbookCore

// MARK: - RV.161 the scanned station pre-fill, and P6.3's on-device boundary

// Split out of `ManualFillUpView.swift` so that file stays within the lint
// ceiling. Both methods read the view's `@State`, so the extension is on the
// live view, not a copy.

extension ManualFillUpView {

    /// RV.161: the station the receipt names becomes a default input the user
    /// edits (hard rule 13). It is resolved against the live stations - so an
    /// existing same-named station is selected rather than duplicated - but
    /// **not written here**: the row shows it selected and changeable, and the
    /// save persists it. Writing on pre-fill would mint a synced station from a
    /// misread on a sheet the user then cancels.
    func applyScannedStation(_ name: String?) {
        guard let name else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, selectedStation == nil else { return }
        let resolved = ImportStationResolver.station(for: trimmed, existing: stations)
        selectedStation = resolved
        scannedStationID = resolved.id
        if !stations.contains(where: { $0.id == resolved.id }) {
            stations.append(resolved)
        }
        // The scan's own evidence is this receipt's station; PJ.19's ranking,
        // which runs after this, must not move it (hard rule 13 - the user can).
        stationChosenByUser = true
    }

    /// The fields the on-device extraction resolved - the late answer's
    /// "not blank" boundary. The QR-anchored total is NOT one of these: a QR
    /// total is exact, and treating it as on-device-resolved would be fine too
    /// (it is never blank), but the extraction's own fields are the honest set.
    static func onDeviceResolvedFields(_ extraction: FuelExtraction) -> Set<FieldRef> {
        var resolved = Set<FieldRef>()
        if extraction.total != nil { resolved.insert(.total) }
        if extraction.liters != nil { resolved.insert(.volume) }
        if extraction.unitPrice != nil { resolved.insert(.unitPrice) }
        if extraction.date != nil { resolved.insert(.date) }
        if extraction.currency != nil { resolved.insert(.currency) }
        if extraction.fuelKind != nil { resolved.insert(.fuelKind) }
        return resolved
    }
}

import TankbookCore

// MARK: - RV.150 the save stamps the station the ranking reads

// Kept out of `ManualFillUpView.swift` so that file stays within the lint
// ceiling; the method is called from the save path exactly once, after the
// fill-up write.

extension ManualFillUpView {

    /// RV.161: writes the station a scan resolved, at the moment the user
    /// commits the entry. `scannedStationID` is the resolved id and the row's
    /// selection; if the user changed the station in between, the ids differ
    /// and nothing is written. The write routes through the shared
    /// deterministic `createStation`, so it resolves to the same id the entry
    /// already carries. A failed write degrades to no station row (the entry
    /// still saves) - the fields re-resolve on the next capture there.
    func persistScannedStation(repository: TankbookRepository) {
        guard let scannedStationID,
              selectedStation?.id == scannedStationID,
              let name = selectedStation?.name else { return }
        self.scannedStationID = nil
        do {
            _ = try repository.createStation(named: name)
        } catch {
            AppLog.error(operation: "confirmManual.stationCreate",
                         category: .ui, error: error)
        }
    }

    /// RV.150: a save at a chosen station stamps the Station row the suggestion
    /// ranks by - `lastUsedAt` becomes the save's moment, `defaults` records
    /// what was actually bought, and a station with no recorded location adopts
    /// the forecourt fix the Confirm sheet already read (fill-blanks-only,
    /// never over an existing coordinate - docs/SCHEMA.md -> Station). The
    /// write rides the ordinary `.dirty` sync path like any other station edit.
    ///
    /// A stamp write failure degrades to no stamp and never blocks the entry:
    /// the fields re-stamp on the next save there, exactly like a failed
    /// receipt-photo write. No station chosen means no station write at all.
    func stampChosenStation(repository: TankbookRepository, source: MutationSource) {
        guard let stationID = selectedStation?.id else { return }
        do {
            _ = try loggedWrite(AppLog.shared, op: .update,
                                entityType: Station.entityType,
                                entityId: stationID, source: source) {
                try repository.stampStation(id: stationID,
                                            fuelKind: form.fuelKind,
                                            fuelGrade: nil,
                                            locationFix: stationLocationFix)
            }
        } catch {
            AppLog.error(operation: "confirmManual.stationStamp",
                         category: .ui, error: error)
        }
    }
}

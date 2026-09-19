import Foundation
import TankbookCore

#if DEBUG
// MARK: - RV.115 the imported station's brand (UI tests + screenshots)

extension ImportFlowModel {
    /// `-seedImportBrand`: one fill whose station column is the printed line a
    /// Russian receipt carries - a legal form, the chain, a forecourt number.
    /// The commit runs the shipped resolver, so the Log row shows the BRAND
    /// the matcher chose ("Gazpromneft") and the Garage's station row shows
    /// both; the L4 asserts the brand, then changes it.
    func installSeededBrandParse() {
        let fill = ImportCandidate(
            entityType: "fillUp",
            date: Date(timeIntervalSince1970: 1_752_393_600),  // 2026-07-21
            odometer: 119_486, volumeL: 40, unitPrice: "62.50",
            money: ImportMoney(amount: "2500.00", currency: "RUB"),
            fuelKind: "petrol95", isFull: true, tankLevelAfterPct: 100, note: nil,
            vehicleName: "Volvo", provenance: ImportProvenance(tag: "import", source: "drivvo"),
            sourceRow: 1, station: "ООО \"Газпромнефть-Центр\" АЗС 12089")
        let response = ImportParseResponse(
            importId: "00000000-0000-4000-8000-000000000115", format: "drivvo",
            scope: "vehicle", candidates: [fill], unparsed: [], ambiguities: [])
        dateFormatAnswer = nil
        adoptSingleFile(fileName: "Drivvo_export.csv",
                        rawData: Data("""
                        Дата;Одометр;Азс;Топливо;Литры;Цена;Сумма
                        21.07.2026;119486;ООО "Газпромнефть-Центр" АЗС 12089;АИ-95;40;62.50;2500.00
                        """.utf8),
                        parse: response)
        ensureTargetCar(preferredVehicleID: nil)
        rebuildClassification()
    }
}
#endif

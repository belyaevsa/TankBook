import Foundation
import XCTest
import TankbookCore
@testable import Tankbook

/// RV.272 + RV.273 - stored litres crossing into the car's display unit without
/// conversion. The extraction is litres and price-per-litre by contract
/// (docs/SCHEMA.md -> GatewayExtraction.volume, FillUp.unitPrice) while the
/// Confirm form, the recognised page and the Recently deleted row all carry the
/// car's own unit label, so every one of those boundaries must convert.
final class RV272PrefillUnitsTests: XCTestCase {

    private func decimal(_ string: String) -> Decimal { Decimal(string: string)! }

    private func vehicle(volume: VolumeUnit) -> Vehicle {
        let now = Date()
        return Vehicle(
            id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
            name: "RV272", make: "Volvo", model: "V60", year: 2015,
            plate: nil, powertrain: .ice, fuelKinds: [.petrol95],
            tankCapacityL: 71, batteryCapacityKWh: nil, homeCurrency: .eur,
            units: Vehicle.Units(distance: .km, volume: volume,
                                 consumption: .lPer100, energy: .kWhPer100),
            photo: nil, archived: false, paceLimitKmPerDay: 1500,
            initialOdometer: 118_000)
    }

    private func fillUp(vehicleId: UUID, volumeL: Double) -> FillUp {
        let now = Date()
        return FillUp(
            id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
            vehicleId: vehicleId, date: now, odometer: 120_000,
            money: Money(amount: decimal("60.00"), currency: .eur, homeCurrency: .eur),
            note: nil, attachments: [], provenance: .manual, conflict: .none,
            purchaseGroupId: nil, volumeL: volumeL, unitPrice: decimal("1.500"),
            fuelKind: .petrol95, fuelGrade: nil, isFull: true, tankLevelAfterPct: 100,
            stationId: nil, crossCheck: .notApplicable, extraction: nil)
    }

    // MARK: - RV.272: the scan pre-fill boundary

    /// A 40 L extraction reads gallons on a gallons car - the exact defect
    /// (`40.00` under a Gallons label). Metric is unchanged.
    func testExtractionVolumePrefillsInTheCarsDisplayUnit() {
        XCTAssertEqual(ManualFillUpFormState.prefillVolumeText(liters: 40, unit: .galUS), "10.57",
                       "a 40 L extraction must pre-fill 10.57 US gallons")
        XCTAssertEqual(ManualFillUpFormState.prefillVolumeText(liters: 40, unit: .galUK), "8.80",
                       "a 40 L extraction must pre-fill 8.80 UK gallons")
        XCTAssertEqual(ManualFillUpFormState.prefillVolumeText(liters: 40, unit: .l), "40.00",
                       "metric is unchanged")
    }

    /// The extraction's price is per litre; the field is labelled per display
    /// unit, so it converts by the inverse factor.
    func testExtractionPricePrefillsPerDisplayUnit() {
        XCTAssertEqual(ManualFillUpFormState.prefillUnitPriceText(perLitre: decimal("1.5"),
                                                                  unit: .galUS),
                       "5.678", "a per-litre price must read per US gallon")
        XCTAssertEqual(ManualFillUpFormState.prefillUnitPriceText(perLitre: decimal("1.5"),
                                                                  unit: .galUK),
                       "6.819", "a per-litre price must read per UK gallon")
        XCTAssertEqual(ManualFillUpFormState.prefillUnitPriceText(perLitre: decimal("1.5"),
                                                                  unit: .l),
                       "1.500", "metric is unchanged")
    }

    /// The one function both pre-fill sites call: the form is in display units,
    /// so the save derives the receipt's own 40 L back out - never 10.57 L.
    func testAPrefilledImperialFormSavesTheExtractionsLitres() {
        var form = ManualFillUpFormState()
        form.applyPrefilledVolumes(liters: 40, unitPrice: decimal("1.5"), volumeUnit: .galUS)
        form.total = "60.00"

        XCTAssertEqual(form.liters, "10.57")
        XCTAssertEqual(form.pricePerL, "5.678")

        let derived = try? XCTUnwrap(form.derived(volumeUnit: .galUS))
        XCTAssertEqual(derived?.volumeL ?? 0, 40, accuracy: 0.02,
                       "the saved volume must be the receipt's 40 L, not 10.57 L")
        XCTAssertEqual(derived?.crossCheck, .verified,
                       "the two converted figures must still multiply up to the total")
    }

    /// A metric car's pre-fill is byte-identical to the extraction.
    func testMetricPrefillIsUnchanged() {
        var form = ManualFillUpFormState()
        form.applyPrefilledVolumes(liters: 40, unitPrice: decimal("1.5"), volumeUnit: .l)
        XCTAssertEqual(form.liters, "40.00")
        XCTAssertEqual(form.pricePerL, "1.500")
        let derived = try? XCTUnwrap(form.derived(volumeUnit: .l))
        XCTAssertEqual(derived?.volumeL ?? 0, 40, accuracy: 0.0001)
    }

    /// A nil extraction field stays blank, never zero (hard rule 13).
    func testNilPrefillLeavesTheFieldBlank() {
        var form = ManualFillUpFormState()
        form.applyPrefilledVolumes(liters: nil, unitPrice: nil, volumeUnit: .galUS)
        XCTAssertTrue(form.liters.isEmpty)
        XCTAssertTrue(form.pricePerL.isEmpty)
    }

    // MARK: - RV.273: the recognised page

    /// The recognised page's volume value converts to the car's unit - its
    /// label is per-unit since RV.234.
    func testRecognisedPageVolumeConvertsToTheCarsUnit() throws {
        let meta = ExtractionMeta(fields: [
            .volume: FieldExtraction(cropRect: nil, confidence: 0.9, userCorrected: false,
                                     value: .number(40.0)),
        ], pipeline: "test")

        let rows = AttachmentValueFormat.rows(from: meta, volumeUnit: .galUS)
        guard case .numeric(let figure, let unit)? = rows.first(where: { $0.ref == .volume })?.value else {
            return XCTFail("the volume row must render as a numeric figure")
        }
        XCTAssertEqual(figure, "10.57", "the recognised 40 L must read 10.57 gal")
        XCTAssertEqual(unit, "gal", "the unit beside it must be the car's own")

        let metric = AttachmentValueFormat.rows(from: meta, volumeUnit: .l)
        guard case .numeric(let metricFigure, _)? = metric.first(where: { $0.ref == .volume })?.value else {
            return XCTFail("the metric volume row must render")
        }
        XCTAssertEqual(metricFigure, "40.00", "metric is unchanged")
    }

    // MARK: - RV.273: the Recently deleted row

    /// The row prints `fill.volumeL` under the car's unit, so it converts.
    func testRecentlyDeletedQuantityConvertsToTheCarsUnit() {
        let us = vehicle(volume: .galUS)
        let fill = fillUp(vehicleId: us.id, volumeL: 42.0)
        XCTAssertEqual(RecentlyDeletedView.quantityText(fill, vehicles: [us.id: us]),
                       "11.1 gal", "42.0 L must read 11.1 gal on a gallons car")

        let metric = vehicle(volume: .l)
        let metricFill = fillUp(vehicleId: metric.id, volumeL: 42.0)
        XCTAssertEqual(RecentlyDeletedView.quantityText(metricFill, vehicles: [metric.id: metric]),
                       "42.0 L", "metric is unchanged")
    }
}

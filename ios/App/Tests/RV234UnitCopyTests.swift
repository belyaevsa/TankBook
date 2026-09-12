import Foundation
import XCTest
import TankbookCore
@testable import Tankbook

/// RV.234: the rest of the unit-in-the-sentence seam. Every sentence that baked
/// a unit in now exists once per unit through `ManualFillUpUnitCopy`'s pattern
/// (hard rule 10: the sentence is the translation unit, never a unit token
/// spliced into a shared stem - RU declines "км"/"миль"/"л"/"гал" differently).
///
/// These are the L1 selectors. They FAIL when the imperial path is reverted to
/// the litre/km key. The catalogue half - the exact EN and RU phrase each key
/// renders - lives beside the RV.134 catalogue suite
/// (`LocalizationGateRV234Tests`).
final class RV234UnitCopyTests: XCTestCase {

    /// The RU bundle of the app under test, so an L1 can read the phrase the
    /// user actually sees without switching the test process's language.
    private var russianBundle: Bundle {
        get throws {
            try XCTUnwrap(Bundle.main.path(forResource: "ru", ofType: "lproj")
                .flatMap(Bundle.init(path:)), "the app must bundle ru.lproj")
        }
    }

    private func ru(_ key: String) throws -> String {
        try russianBundle.localizedString(forKey: key, value: nil, table: nil)
    }

    // MARK: - Volume sentences

    private struct VolumePhrase {
        let name: String
        /// The catalogue key for the litre path (EN is the source language, so
        /// the rendered EN value is also the key the RU lookup uses).
        let litreKey: String
        let gallonKey: String
        let litreRU: String
        let gallonRU: String
        let make: (VolumeUnit) -> String
    }

    private var volumePhrases: [VolumePhrase] {
        [
            VolumePhrase(name: "volume label",
                         litreKey: "Liters", gallonKey: "Gallons",
                         litreRU: "Литры", gallonRU: "Галлоны",
                         make: ManualFillUpUnitCopy.volumeLabel),
            VolumePhrase(name: "disabled-save hint",
                         litreKey: "Enter total and liters to save",
                         gallonKey: "Enter total and gallons to save",
                         litreRU: "Введите сумму и литры, чтобы сохранить",
                         gallonRU: "Введите сумму и галлоны, чтобы сохранить",
                         make: ManualFillUpUnitCopy.enterTotalAndVolume),
            VolumePhrase(name: "CHECK 5 chip",
                         litreKey: "Check litres", gallonKey: "Check gallons",
                         litreRU: "Проверить литры", gallonRU: "Проверить галлоны",
                         make: ManualFillUpUnitCopy.checkVolumeChip),
            VolumePhrase(name: "last-price label",
                         litreKey: "Last price/L", gallonKey: "Last price/gal",
                         litreRU: "Цена за литр", gallonRU: "Цена за галлон",
                         make: ManualFillUpUnitCopy.lastPriceLabel),
            VolumePhrase(name: "field volume label",
                         litreKey: "Litres", gallonKey: "Gallons",
                         litreRU: "Литры", gallonRU: "Галлоны",
                         make: ManualFillUpUnitCopy.fieldVolumeLabel),
            VolumePhrase(name: "field price label",
                         litreKey: "Price/L", gallonKey: "Price/gal",
                         litreRU: "Цена/л", gallonRU: "Цена/гал",
                         make: ManualFillUpUnitCopy.fieldPriceLabel),
            VolumePhrase(name: "missing-capacity hint",
                         litreKey: "Set tank size in Garage to see liters.",
                         gallonKey: "Set tank size in Garage to see gallons.",
                         litreRU: "Укажите объём бака в Garage, чтобы видеть литры.",
                         gallonRU: "Укажите объём бака в Garage, чтобы видеть галлоны.",
                         make: ManualFillUpUnitCopy.setTankSizeHint),
            VolumePhrase(name: "consumption reason",
                         litreKey: "Unusual consumption – check the litres or odometer",
                         gallonKey: "Unusual consumption – check the gallons or odometer",
                         litreRU: "Необычный расход – проверьте литры или пробег",
                         gallonRU: "Необычный расход – проверьте галлоны или пробег",
                         make: ManualFillUpUnitCopy.consumptionReason)
        ]
    }

    /// One table, every volume sentence, metric and imperial, EN and RU. The EN
    /// value is the key; the RU lookup proves each unit has its OWN translation.
    func testVolumeSentencesArePerUnitInEnglishAndRussian() throws {
        for phrase in volumePhrases {
            XCTAssertEqual(phrase.make(.l), phrase.litreKey,
                           "\(phrase.name): EN litre value must be the key")
            XCTAssertEqual(phrase.make(.galUS), phrase.gallonKey,
                           "\(phrase.name): EN US-gallon value")
            XCTAssertEqual(phrase.make(.galUK), phrase.gallonKey,
                           "\(phrase.name): both gallons share the compact label")
            XCTAssertEqual(try ru(phrase.litreKey), phrase.litreRU,
                           "\(phrase.name): RU litre value")
            XCTAssertEqual(try ru(phrase.gallonKey), phrase.gallonRU,
                           "\(phrase.name): RU gallon value")
            XCTAssertNotEqual(phrase.litreKey, phrase.gallonKey,
                              "\(phrase.name): the two units must not render one key")
        }
    }

    /// The two composed volume sentences, whose values are runtime data sharing
    /// the phrase. EN and RU are both asserted on the FORMATTED sentence.
    func testComposedVolumeSentencesArePerUnit() throws {
        let litreTank = ManualFillUpUnitCopy.tankEquivalence(volume: 53, capacity: 71, unit: .l)
        XCTAssertEqual(litreTank, "≈ 53 of 71 L")
        XCTAssertEqual(String(format: try ru("≈ %d of %d L"), 53, 71), "≈ 53 из 71 л")

        let gallonTank = ManualFillUpUnitCopy.tankEquivalence(volume: 14, capacity: 19, unit: .galUS)
        XCTAssertEqual(gallonTank, "≈ 14 of 19 gal")
        XCTAssertEqual(String(format: try ru("≈ %d of %d gal"), 14, 19), "≈ 14 из 19 гал")

        let litreQuote = ManualFillUpUnitCopy.consumptionQuote(
            per100: "1.6", unit: "L/100km", volumeUnit: .l)
        XCTAssertEqual(litreQuote,
                       "This fill implies 1.6 L/100km – check the litres or the odometer.")
        XCTAssertEqual(
            String(format: try ru("This fill implies %1$@ %2$@ – check the litres or the odometer."),
                   "1.6", "L/100km"),
            "Эта заправка даёт 1.6 L/100km – проверьте литры или пробег.")

        let gallonQuote = ManualFillUpUnitCopy.consumptionQuote(
            per100: "32.1", unit: "MPG", volumeUnit: .galUS)
        XCTAssertEqual(gallonQuote,
                       "This fill implies 32.1 MPG – check the gallons or the odometer.")
        XCTAssertEqual(
            String(format: try ru("This fill implies %1$@ %2$@ – check the gallons or the odometer."),
                   "32.1", "MPG"),
            "Эта заправка даёт 32.1 MPG – проверьте галлоны или пробег.")
    }

    // MARK: - Distance sentences

    private struct DistancePhrase {
        let name: String
        let kmKey: String
        let miKey: String
        let kmRU: String
        let miRU: String
        let make: (DistanceUnit) -> String
    }

    func testDistanceSentencesArePerUnitInEnglishAndRussian() throws {
        let phrases: [DistancePhrase] = [
            DistancePhrase(name: "cost label",
                           kmKey: "Cost / km", miKey: "Cost / mi",
                           kmRU: "Стоимость / км", miRU: "Стоимость / миль",
                           make: ManualFillUpUnitCopy.costPerDistanceLabel),
            DistancePhrase(name: "per-distance label",
                           kmKey: "per km", miKey: "per mi",
                           kmRU: "за км", miRU: "за милю",
                           make: ManualFillUpUnitCopy.perDistanceLabel)
        ]
        for phrase in phrases {
            XCTAssertEqual(phrase.make(.km), phrase.kmKey, "\(phrase.name): EN km")
            XCTAssertEqual(phrase.make(.mi), phrase.miKey, "\(phrase.name): EN mi")
            XCTAssertEqual(try ru(phrase.kmKey), phrase.kmRU, "\(phrase.name): RU km")
            XCTAssertEqual(try ru(phrase.miKey), phrase.miRU, "\(phrase.name): RU mi")
            XCTAssertNotEqual(phrase.kmKey, phrase.miKey,
                              "\(phrase.name): the two units must not render one key")
        }
    }

    // MARK: - The VoiceOver verify label (LocalizedStringKey)

    /// `checkVolumeOnReceipt` returns a `LocalizedStringKey`, so its selector is
    /// pinned through the catalogue keys the two cases name.
    func testVerifyLabelKeysArePerUnit() throws {
        XCTAssertEqual(try ru("Check the liters on the receipt"), "Проверьте литры на чеке")
        XCTAssertEqual(try ru("Check the gallons on the receipt"), "Проверьте галлоны на чеке")
        XCTAssertNotEqual("Check the liters on the receipt", "Check the gallons on the receipt")
    }
}

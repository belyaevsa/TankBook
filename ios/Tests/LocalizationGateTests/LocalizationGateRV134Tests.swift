import Foundation
import Testing
@testable import LocalizationGate

/// RV.134 - five more places baked a unit into one shared sentence. RV.126 fixed
/// the F9a odometer quote; this row fixes the volume pair on the SAME Confirm
/// screen (`Price / L` and `fills in from total ÷ liters`), the live delta
/// caption (`+N km since last` for every car), and the service and import
/// odometer quotes that hardcoded `km` the same way.
///
/// The fix is one full localised sentence PER unit, never a unit token spliced
/// onto a shared stem (hard rule 10): RU declines the units differently ("км"
/// indeclinable, "миль" genitive plural, "л"/"гал" abbreviations), so the
/// sentence - not the unit label - is the translation unit. This suite pins the
/// CATALOGUE half (the exact EN and RU phrase each key renders). The selector
/// half - that a gallon/miles vehicle actually picks these keys - is the L1
/// `RV134UnitCopyTests` in the app unit bundle.
@Suite("Unit-aware copy per unit (RV.134)")
struct LocalizationGateRV134Tests {

    /// ios/Tests/LocalizationGateTests/<this file> -> ios/App/Sources
    private static var catalogueURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // ios/Tests/LocalizationGateTests
            .deletingLastPathComponent() // ios/Tests
            .deletingLastPathComponent() // ios
            .appendingPathComponent("App/Sources/Localizable.xcstrings")
    }

    /// One volume-copy row. A struct, not a tuple - the gate's own lint rule
    /// (large_tuple) must not be tripped by the tests that guard the gate.
    private struct VolumePhrase {
        let key: String
        let en: String
        let ru: String
    }

    /// The volume pair: each label is a whole phrase per unit, and the two units
    /// must render differently in both languages.
    @Test("the price label and fill caption render litres and gallons, EN and RU")
    func volumeCopyRendersPerUnit() throws {
        let catalogue = try LocalizationCatalogue.load(at: Self.catalogueURL)

        let expected: [VolumePhrase] = [
            VolumePhrase(key: "Price / L", en: "Price / L", ru: "Цена / л"),
            VolumePhrase(key: "Price / gal", en: "Price / gal", ru: "Цена / гал"),
            VolumePhrase(key: "fills in from total ÷ liters",
                         en: "fills in from total ÷ liters",
                         ru: "считается из суммы ÷ литров"),
            VolumePhrase(key: "fills in from total ÷ gallons",
                         en: "fills in from total ÷ gallons",
                         ru: "считается из суммы ÷ галлонов")
        ]
        for row in expected {
            #expect(catalogue.value(for: row.key, language: "en") == row.en,
                    "EN '\(row.key)': \(String(describing: catalogue.value(for: row.key, language: "en")))")
            #expect(catalogue.value(for: row.key, language: "ru") == row.ru,
                    "RU '\(row.key)': \(String(describing: catalogue.value(for: row.key, language: "ru")))")
        }

        // A gallons car must never be handed the litre label, and vice versa.
        let litreLabel = try #require(catalogue.value(for: "Price / L", language: "ru"))
        let gallonLabel = try #require(catalogue.value(for: "Price / gal", language: "ru"))
        #expect(litreLabel != gallonLabel)
        #expect(gallonLabel.contains("гал"))
        #expect(!gallonLabel.contains(" л"), "the gallons label must not name litres: '\(gallonLabel)'")
    }

    /// The forward delta caption is a real plural per distance unit. The miles
    /// sentence must decline "миля/мили/миль" and never name "км".
    @Test("the +N since last plural renders per distance unit, EN and RU")
    func deltaCaptionPluralRendersPerUnit() throws {
        let catalogue = try LocalizationCatalogue.load(at: Self.catalogueURL)

        let enKM = catalogue.pluralForms(for: "+%lld km since last", language: "en")
        #expect(enKM["one"] == "+%lld km since last")
        #expect(enKM["other"] == "+%lld km since last")

        let enMI = catalogue.pluralForms(for: "+%lld mi since last", language: "en")
        #expect(enMI["one"] == "+%lld mi since last")
        #expect(enMI["other"] == "+%lld mi since last")

        let ruKM = catalogue.pluralForms(for: "+%lld km since last", language: "ru")
        #expect(ruKM["one"] == "+%lld километр с прошлой заправки")
        #expect(ruKM["many"] == "+%lld километров с прошлой заправки")

        let ruMI = catalogue.pluralForms(for: "+%lld mi since last", language: "ru")
        #expect(ruMI["one"] == "+%lld миля с прошлой заправки")
        #expect(ruMI["few"] == "+%lld мили с прошлой заправки")
        #expect(ruMI["many"] == "+%lld миль с прошлой заправки")
        #expect(ruMI["other"] == "+%lld миль с прошлой заправки")

        // The miles sentence names miles, never the indeclinable "км".
        for form in ["one", "few", "many", "other"] {
            let value = try #require(ruMI[form])
            #expect(!value.contains("км"), "RU miles form '\(form)' must not name kilometres: '\(value)'")
        }
    }

    /// Closed decision, pinned structurally: the catalogue holds full sentences
    /// per unit, never a shared stem with a unit slot. The spliced shape would
    /// be "Price / %@" or "fills in from total ÷ %@" with the unit label
    /// interpolated - the concatenation hard rule 10 forbids.
    @Test("no unit-token splice key exists for the fixed sentences")
    func noUnitSpliceVariantExists() throws {
        let catalogue = try LocalizationCatalogue.load(at: Self.catalogueURL)
        for spliced in ["Price / %@", "fills in from total ÷ %@",
                        "+%lld %@ since last"] {
            #expect(catalogue.value(for: spliced, language: "en") == nil,
                    "a unit-token splice key must not exist: '\(spliced)'")
        }
    }
}

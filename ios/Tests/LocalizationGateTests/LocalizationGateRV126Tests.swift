import Foundation
import Testing
@testable import LocalizationGate

/// RV.126 - the F9a odometer-conflict quote baked `km` into one shared string,
/// so a miles-configured car was told about kilometres in the one message whose
/// job is to make the user trust a number they are about to correct. The fix is
/// one full localised sentence PER unit, chosen from `distanceUnit` - never a
/// unit token spliced onto a shared stem (hard rule 10): RU declines the units
/// differently ("км" is indeclinable, "миль" is a genitive plural), so the
/// sentence - not the unit label - is the translation unit.
///
/// These tests pin the CATALOGUE half: each unit's sentence, EN and RU, as it
/// renders. The RENDERED half - that a miles vehicle's quote actually names
/// miles - is the L4 miles-seed suite (`ConfirmF9aQuoteUITests`), the same
/// split as the P1.13b quote tests that live beside this file's sibling suites.
@Suite("Odometer-conflict quote per distance unit (RV.126)")
struct LocalizationGateRV126Tests {

    /// ios/Tests/LocalizationGateTests/<this file> -> ios/App/Sources
    private static var catalogueURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // ios/Tests/LocalizationGateTests
            .deletingLastPathComponent() // ios/Tests
            .deletingLastPathComponent() // ios
            .appendingPathComponent("App/Sources/Localizable.xcstrings")
    }

    /// The catalogue key `OdometerConflict.quote` resolves for a unit - the
    /// same unit -> full-sentence mapping the composer switches on.
    private static func key(for unit: String) -> String {
        "%@ already recorded %@ \(unit)."
    }

    /// Renders a key's value for one language, filling the day slot then the
    /// odometer slot in order - the exact `String(format:)` substitution order
    /// `OdometerConflict.quote` uses.
    private static func render(_ template: String, day: String, groupedOdometer: String) -> String {
        var composed = template
        if let range = composed.range(of: "%@") { composed.replaceSubrange(range, with: day) }
        if let range = composed.range(of: "%@") { composed.replaceSubrange(range, with: groupedOdometer) }
        return composed
    }

    /// The order-conflict quote names the vehicle's OWN unit in both languages.
    /// Asserted on the exact RENDERED sentence: a `km` car is told about km and
    /// a `mi` car about miles, never the reverse and never a shared stem with
    /// the unit bolted on (the RV.126 regression - the old key read "km" for
    /// every car - and the shape the catalog must keep, since RU cannot decline
    /// an interpolated unit label). The day slot carries each language's own
    /// abbreviated day (the runtime formatter's output); the odometer slot the
    /// grouped figure. A struct, not a tuple - the gate's own lint rule
    /// (large_tuple) must not be tripped by the tests that guard the gate.
    struct RenderedQuote {
        let unit: String
        let enDay: String
        let ruDay: String
        let expectedEN: String
        let expectedRU: String
    }

    @Test("the conflict quote renders km for a km car and mi for a miles car, EN and RU")
    func conflictQuoteRendersPerUnitInBothLanguages() throws {
        let catalogue = try LocalizationCatalogue.load(at: Self.catalogueURL)

        let expected: [RenderedQuote] = [
            RenderedQuote(unit: "km",
                          enDay: "Aug 17", ruDay: "17 авг.",
                          expectedEN: "Aug 17 already recorded 119\u{00A0}486 km.",
                          expectedRU: "«17 авг.» уже зафиксирован пробег 119\u{00A0}486 км."),
            RenderedQuote(unit: "mi",
                          enDay: "Aug 17", ruDay: "17 авг.",
                          expectedEN: "Aug 17 already recorded 119\u{00A0}486 mi.",
                          expectedRU: "«17 авг.» уже зафиксирован пробег 119\u{00A0}486 миль.")
        ]

        for row in expected {
            let key = Self.key(for: row.unit)
            let en = try #require(catalogue.value(for: key, language: "en"),
                                  "\(key) has no EN value")
            let renderedEN = Self.render(en, day: row.enDay, groupedOdometer: "119\u{00A0}486")
            #expect(renderedEN == row.expectedEN, "EN rendered for '\(row.unit)': '\(renderedEN)'")

            let ru = try #require(catalogue.value(for: key, language: "ru"),
                                  "\(key) has no RU value")
            let renderedRU = Self.render(ru, day: row.ruDay, groupedOdometer: "119\u{00A0}486")
            #expect(renderedRU == row.expectedRU, "RU rendered for '\(row.unit)': '\(renderedRU)'")
        }

        // The two units must render DIFFERENTLY in each language - a miles car's
        // sentence that collapses onto the km sentence is the defect returning.
        let kmEn = try #require(catalogue.value(for: Self.key(for: "km"), language: "en"))
        let miEn = try #require(catalogue.value(for: Self.key(for: "mi"), language: "en"))
        #expect(miEn != kmEn)
        let kmRu = try #require(catalogue.value(for: Self.key(for: "km"), language: "ru"))
        let miRu = try #require(catalogue.value(for: Self.key(for: "mi"), language: "ru"))
        #expect(miRu != kmRu)

        // RU declines the units: the miles sentence must carry the genitive
        // plural "миль", never the indeclinable "км" that would name the wrong
        // unit entirely.
        #expect(miRu.hasSuffix("миль."), "RU miles sentence must end in 'миль.': '\(miRu)'")
        #expect(!miRu.contains("км"), "RU miles sentence must not name kilometres: '\(miRu)'")
        #expect(kmRu.hasSuffix("км."), "RU km sentence must end in 'км.': '\(kmRu)'")
    }

    /// Closed decision 1, pinned structurally: the catalogue must hold two full
    /// sentences, never a shared stem with a unit slot. The spliced shape would
    /// be "%@ already recorded %@ %@." with the unit label interpolated - the
    /// concatenation hard rule 10 forbids, and the shape whose RU cannot be
    /// right (the label is genitive-plural after a number, which no shared stem
    /// can place).
    @Test("the catalogue holds full per-unit sentences, never a unit-token splice")
    func noUnitSpliceVariantExists() throws {
        let catalogue = try LocalizationCatalogue.load(at: Self.catalogueURL)

        // A spliced variant would need a key with the unit as a third slot.
        #expect(catalogue.value(for: "%@ already recorded %@ %@.", language: "en") == nil,
                "a unit-token splice key must not exist")
        #expect(catalogue.value(for: "%@ already recorded %@", language: "en") == nil,
                "a shared stem without the unit must not exist")

        // Both full-sentence keys are present with EN + RU (the preceding test
        // asserts what they RENDER; this asserts they exist at all).
        for unit in ["km", "mi"] {
            let key = Self.key(for: unit)
            #expect(catalogue.value(for: key, language: "en") != nil, "\(key) missing EN")
            #expect(catalogue.value(for: key, language: "ru") != nil, "\(key) missing RU")
        }
    }
}

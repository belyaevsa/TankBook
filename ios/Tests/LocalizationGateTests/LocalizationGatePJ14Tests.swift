import Foundation
import Testing
@testable import LocalizationGate

/// PJ.14 (docs/DESIGN.md -> the Pump Card; docs/JOURNEYS.md -> Confirm): the
/// live "+N km since last" odometer caption. The caption's number is runtime
/// data (docs/LOCALIZATION.md), so the key is a real plural in BOTH languages
/// - and in Russian the unit is spelled out (километр / километра / километров)
/// precisely so the count governs a declining noun and the 11/21 edge can be
/// asserted. The warn/equal captions are plain literal keys with a full RU
/// phrase each - never concatenation (the P1.4/P4.7 lessons). Owned by its own
/// suite so no test type trips the type_body_length lint rule.
@Suite("Odometer-delta caption strings (PJ.14)")
struct OdometerDeltaCaptionTests {

    /// ios/Tests/LocalizationGateTests/<this file> -> ios/App/Sources
    private static var catalogueURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // ios/Tests/LocalizationGateTests
            .deletingLastPathComponent() // ios/Tests
            .deletingLastPathComponent() // ios
            .appendingPathComponent("App/Sources/Localizable.xcstrings")
    }

    /// The forward caption is `+N km since last` - a plural carrying runtime
    /// data. RU needs one/few/many; the edges are 11 and 21, and 1 and 21 both
    /// take `one`, so a few/many error is invisible at 21. Asserted on the
    /// RENDERED string in EN (one/other) and RU (one/few/many) at all five
    /// counts - the same shape as `deviceCountPluralRendersInBothLanguages`.
    @Test("the +N km since last plural renders at 1, 2, 5, 11 and 21 in EN and RU")
    func odometerDeltaPluralRendersInBothLanguages() throws {
        let catalogue = try LocalizationCatalogue.load(at: Self.catalogueURL)
        let key = "+%lld km since last"
        let counts = [1, 2, 5, 11, 21]

        let expectedEN: [Int: String] = [
            1: "+1 km since last", 2: "+2 km since last", 5: "+5 km since last",
            11: "+11 km since last", 21: "+21 km since last"
        ]
        let expectedRU: [Int: String] = [
            1: "+1 километр с прошлой заправки",
            2: "+2 километра с прошлой заправки",
            5: "+5 километров с прошлой заправки",
            11: "+11 километров с прошлой заправки",
            21: "+21 километр с прошлой заправки"
        ]

        func render(language: String, _ count: Int) -> String {
            let form: String
            switch language {
            case "ru":
                form = count == 1 || count == 21 ? "one"
                    : (count == 2 ? "few" : "many")
            default:
                form = count == 1 ? "one" : "other"
            }
            guard let template = catalogue.pluralForms(for: key, language: language)[form] else {
                return "MISSING-\(form)"
            }
            return template.replacingOccurrences(of: "%lld", with: "\(count)")
        }

        for count in counts {
            let en = render(language: "en", count)
            #expect(en == expectedEN[count],
                    "EN at \(count): rendered '\(en)', expected '\(expectedEN[count]!)'")
            let ru = render(language: "ru", count)
            #expect(ru == expectedRU[count],
                    "RU at \(count): rendered '\(ru)', expected '\(expectedRU[count]!)'")
        }

        // The `other` fallback exists for both languages and is never empty.
        for language in ["en", "ru"] {
            let forms = catalogue.pluralForms(for: key, language: language)
            #expect(!(forms["other"]?.isEmpty ?? true),
                    "\(language) must carry a non-empty `other` form for \(key)")
        }
    }

    /// The equal/backwards/pace captions are plain literals (no runtime slot -
    /// the warn texts deliberately name no number, so no case can be governed).
    /// Each is a full localised phrase per language (hard rule 10).
    @Test("the equal and warn captions resolve in EN and RU")
    func warnAndEqualCaptionsResolve() throws {
        let catalogue = try LocalizationCatalogue.load(at: Self.catalogueURL)
        for key in ["Same as last",
                    "Odometer went backwards – check it.",
                    "Daily pace over the limit – check it."] {
            #expect(catalogue.value(for: key, language: "en") == key, "EN '\(key)'")
            let ru = catalogue.value(for: key, language: "ru")
            #expect(!(ru?.isEmpty ?? true), "RU '\(key)'")
            #expect(ru != key, "RU '\(key)' must be a real translation, not the key")
        }
    }
}

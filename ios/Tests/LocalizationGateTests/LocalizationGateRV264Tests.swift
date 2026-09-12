import Foundation
import Testing
@testable import LocalizationGate

/// RV.264 (docs/TASKS.md; docs/JOURNEYS.md F6b): the import review's intro
/// carries two runtime counts in one sentence, and a String Catalog plural
/// variation pluralises only one argument. Composed as one key, the second
/// count rendered flat: "2 rows are ready. These 1 are missing something" and
/// Russian mis-declined at every count. The fix is one full localised phrase per
/// plural category, per count - two keys, each with its own `%lld` variations.
///
/// This gate is what makes re-composing the two counts into one key a red build
/// rather than a silent regression: drop either key's variations and the phrase
/// no longer has a form for 1, 2 or 5.
@Suite("Import review count phrases carry real plurals (RV.264)")
struct LocalizationGateRV264Tests {

    private static var catalogueURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // ios/Tests/LocalizationGateTests
            .deletingLastPathComponent() // ios/Tests
            .deletingLastPathComponent() // ios
            .appendingPathComponent("App/Sources/Localizable.xcstrings")
    }

    /// The CLDR Russian plural rule (one / few / many), matching what
    /// `String(localized:)` applies against the catalogue's variations.
    private func ruPluralForm(for count: Int) -> String {
        let mod10 = count % 10
        let mod100 = count % 100
        if mod10 == 1 && mod100 != 11 { return "one" }
        if mod10 >= 2 && mod10 <= 4 && !(mod100 >= 12 && mod100 <= 14) { return "few" }
        return "many"
    }

    private func render(_ forms: [String: String], _ count: Int) -> String {
        let form = ruPluralForm(for: count)
        guard let template = forms[form] else { return "MISSING-\(form)" }
        return template.replacingOccurrences(of: "%lld", with: "\(count)")
    }

    @Test("both review-count phrases carry EN one/other and RU one/few/many")
    func reviewCountPhrasesCarryPlurals() throws {
        let catalogue = try LocalizationCatalogue.load(at: Self.catalogueURL)
        let keys = ["%lld rows are ready.",
                    "These %lld are missing something – fix one, or leave it out."]

        for key in keys {
            let en = catalogue.pluralForms(for: key, language: "en")
            #expect(en["one"]?.isEmpty == false, "\(key): EN one")
            #expect(en["other"]?.isEmpty == false, "\(key): EN other")

            let ru = catalogue.pluralForms(for: key, language: "ru")
            for form in ["one", "few", "many", "other"] {
                #expect(ru[form]?.isEmpty == false, "\(key): RU \(form)")
            }
            #expect(ru["one"] != ru["many"], "\(key): RU one must differ from many")
        }
    }

    @Test("the review intro's singular phrase reads correctly in EN and RU")
    func singularPhraseReadsCorrectly() throws {
        let catalogue = try LocalizationCatalogue.load(at: Self.catalogueURL)

        let ready = catalogue.pluralForms(for: "%lld rows are ready.", language: "ru")
        let missing = catalogue.pluralForms(
            for: "These %lld are missing something – fix one, or leave it out.", language: "ru")
        #expect(render(ready, 1) == "1 строка готова.")
        #expect(render(missing, 1) == "Эта 1 строка неполная – исправьте или пропустите.")

        let enReady = catalogue.pluralForms(for: "%lld rows are ready.", language: "en")
        #expect(enReady["one"]?.replacingOccurrences(of: "%lld", with: "1") == "1 row is ready.")
    }
}

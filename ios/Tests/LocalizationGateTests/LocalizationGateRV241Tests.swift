import Foundation
import Testing
@testable import LocalizationGate

/// RV.241 (docs/TASKS.md; docs/JOURNEYS.md J1): the Welcome screen names what
/// the build does, in both directions. The tagline promised EV charging
/// (`PJ.49`, v2 - an EV cannot log a single charge) and the feature row promised
/// pump-display scanning, which ships off (`PumpPhotoGate.allowsPumpPhoto ==
/// false`); the same rule `PJ.51` applied to the store listing. The guest Home's
/// import card promised Fuelio, which the server does not register (`RV.190`
/// names Drivvo and My Fuel Manager).
///
/// The copy was corrected in the same change as this gate. What makes re-adding
/// a claim a DELIBERATE edit rather than a drift is that this gate derives the
/// two Welcome strings from their single source of truth and refuses the
/// tokens in EN and RU: a rewrite that reintroduces one goes red here, so it
/// cannot ship by accident.
@Suite("Welcome copy names only what the build does (RV.241)")
struct LocalizationGateRV241Tests {

    /// ios/Tests/LocalizationGateTests/<this file> -> repo root.
    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // ios/Tests/LocalizationGateTests
            .deletingLastPathComponent() // ios/Tests
            .deletingLastPathComponent() // ios
            .deletingLastPathComponent() // repo root
    }

    private static var appSources: URL {
        repoRoot.appendingPathComponent("ios/App/Sources", isDirectory: true)
    }

    private static var welcomeSource: String? {
        try? String(contentsOf: appSources
            .appendingPathComponent("Welcome", isDirectory: true)
            .appendingPathComponent("WelcomeView.swift"), encoding: .utf8)
    }

    /// The hero tagline: the `Text("…")` that immediately follows the wordmark
    /// `Text("Tankbook")` - the same single source of truth PJ.3b derives.
    private static func tagline(in source: String) -> String? {
        capture(#"Text\("Tankbook"\)[\s\S]*?Text\("([^"]+)"\)"#, in: source)
    }

    /// The first feature row's copy: `featureRow("camera", "…")`.
    private static func featureRow(in source: String) -> String? {
        capture(#"featureRow\("[^"]+",\s*"([^"]+)"\)"#, in: source)
    }

    private static func capture(_ pattern: String, in source: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: source,
                                           range: NSRange(source.startIndex..., in: source)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: source) else {
            return nil
        }
        return String(source[range])
    }

    /// The claims the v1 build does not honour, EN and RU. `charging`/`зарядк`
    /// is `PJ.49` (v2); `pump`/`колон` is pump-display scanning, which ships
    /// off. Matched case-insensitively.
    private static let forbidden = ["charging", "зарядк", "pump", "колон"]

    private static func forbiddenTokens(in text: String) -> [String] {
        let lowered = text.lowercased()
        return forbidden.filter { lowered.contains($0) }
    }

    @Test("the Welcome tagline and feature row name no unshipped capability, EN or RU")
    func welcomeCopyNamesOnlyWhatTheBuildDoes() throws {
        let source = try #require(Self.welcomeSource,
                                  "cannot read WelcomeView.swift")
        let tagline = try #require(Self.tagline(in: source),
                                   "cannot derive the tagline from WelcomeView.swift")
        let feature = try #require(Self.featureRow(in: source),
                                   "cannot derive the first feature row from WelcomeView.swift")

        let catalogue = try LocalizationCatalogue.load(
            at: Self.appSources.appendingPathComponent("Localizable.xcstrings"))

        for key in [tagline, feature] {
            // The derived literal is the catalogue key; the rendered copy is the
            // per-language value. Both are checked, so a restored claim is caught
            // whether it lands in the source literal or in either translation.
            var texts = [key]
            for language in ["en", "ru"] {
                texts.append(try #require(catalogue.value(for: key, language: language),
                                          "\(key) has no \(language) value"))
            }
            for text in texts {
                let found = Self.forbiddenTokens(in: text)
                #expect(found.isEmpty,
                        "Welcome copy '\(text)' names an unshipped capability \(found); re-adding it is a deliberate edit of this gate, not a drift")
            }
        }
    }
}

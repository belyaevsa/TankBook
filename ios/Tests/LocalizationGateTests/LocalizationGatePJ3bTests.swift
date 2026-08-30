import Foundation
import Testing

/// PJ.3b (docs/TASKS.md; design/screens/Welcome.dc.html): the Welcome tagline
/// was "Point. Scan. Done." - a promise that scanning finishes the job. Hard
/// rule 15 exists because the corpus says it does not: receipts extract at
/// 38.3%, pump displays at 0%, Vision misreads a digit at confidence 1.00, and
/// a fiscal QR is on 9 of 16 real receipts carrying 2 of 5 fields. W1's site
/// gate (scripts/check-site.sh) already forbids the same family in site copy;
/// this is the app-side twin, and it scans the ARTBOARDS too - the source of
/// truth the app is told to match, and the half that reintroduced the claim
/// after W6 fixed the doc.
@Suite("Over-promise gate (PJ.3b)")
struct OverPromiseGateTests {

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

    /// Everything the gate reads: every Swift file and the String Catalog under
    /// ios/App/Sources, and both Welcome artboards. A claim hidden in any of the
    /// four passes as shipped - the artboards are the half that matters, because
    /// that is what the next agent will be told to match.
    private static func scannedTexts() throws -> [(name: String, text: String)] {
        var results: [(String, String)] = []
        let enumerator = FileManager.default.enumerator(
            at: appSources,
            includingPropertiesForKeys: [.isRegularFileKey]
        )
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            let text = try String(contentsOf: url, encoding: .utf8)
            results.append((url.lastPathComponent, text))
        }
        let catalogue = try String(
            contentsOf: appSources.appendingPathComponent("Localizable.xcstrings"),
            encoding: .utf8
        )
        results.append(("Localizable.xcstrings", catalogue))
        let dark = try String(
            contentsOf: repoRoot.appendingPathComponent("design/screens/Welcome.dc.html"),
            encoding: .utf8
        )
        results.append(("Welcome.dc.html", dark))
        let light = try String(
            contentsOf: repoRoot.appendingPathComponent("design/screens/LightWelcome.dc.html"),
            encoding: .utf8
        )
        results.append(("LightWelcome.dc.html", light))
        return results
    }

    /// The forbidden family. The first four are W1's site gate, copied so the
    /// app is held to the same bar as the landing page. The last two are the
    /// Welcome completion triptych, EN and RU, that PJ.3b removed. `\bautomatic`
    /// is deliberately NOT here: the app truthfully says things "resume
    /// automatically" and "arrives automatically" about sync/backfill, and the
    /// capture caption's pump promise is PJ.12b's row - its own gate.
    private static let forbidden: [String] = [
        "zero typing",
        "just snap",
        "scans any",
        #"reads.{0,20}perfectly"#,
        #"Point\. Scan\. Done\."#,
        #"Наведи\. Сканируй\. Готово\."#
    ]

    private static func matchingPatterns(in text: String) -> [String] {
        forbidden.compactMap { pattern in
            guard let regex = try? NSRegularExpression(pattern: pattern,
                                                       options: [.caseInsensitive]) else {
                return nil
            }
            let range = NSRange(text.startIndex..., in: text)
            return regex.firstMatch(in: text, range: range) != nil ? pattern : nil
        }
    }

    @Test("the app strings and both artboards carry no scan-completes-the-job over-promise")
    func cleanTreePasses() throws {
        var findings: [String] = []
        for (name, text) in try Self.scannedTexts() {
            for pattern in Self.matchingPatterns(in: text) {
                findings.append("\(name): \(pattern)")
            }
        }
        #expect(findings.isEmpty,
                "forbidden over-promise family found:\n\(findings.joined(separator: "\n"))")
    }

    /// What a text scan cannot see, said plainly: it cannot judge that a
    /// sentence is honest by meaning, cannot read a screenshot's implied
    /// promise, cannot catch a rewording that shares no token with this family,
    /// and cannot see that a capture which fills 2 of 5 fields is over-stated.
    /// This gate is the token half; the screenshot pass and the product-owner
    /// copy review are the halves it cannot be.
    @Test("the matcher detects each reintroduced token - it is not vacuous")
    func matcherDetectsForbiddenTokens() {
        let samples: [(String, [String])] = [
            ("Point. Scan. Done.", [#"Point\. Scan\. Done\."#]),
            ("Наведи. Сканируй. Готово.", [#"Наведи\. Сканируй\. Готово\."#]),
            ("Zero typing, never touch a key", ["zero typing"]),
            ("Just snap a photo and you're done", ["just snap"]),
            ("scans any receipt", ["scans any"]),
            ("reads your receipt perfectly", [#"reads.{0,20}perfectly"#])
        ]
        for (sample, expected) in samples {
            let found = Self.matchingPatterns(in: sample)
            for pattern in expected {
                #expect(found.contains(pattern),
                        "sample '\(sample)' must trip \(pattern), got \(found)")
            }
        }
    }

    /// The gate's positive control: the honest tagline must be present in the
    /// app and both artboards. A path typo or an unread file would otherwise
    /// read as "passed" on an empty scan.
    @Test("the honest tagline is present in the app and both artboards")
    func honestTaglineIsPresent() throws {
        let byName = Dictionary(uniqueKeysWithValues: try Self.scannedTexts())
        for name in ["WelcomeView.swift", "Localizable.xcstrings",
                     "Welcome.dc.html", "LightWelcome.dc.html"] {
            let text = byName[name] ?? ""
            #expect(text.contains("A head start, not an answer"),
                    "\(name) must carry the honest tagline - the gate's positive control")
        }
    }
}

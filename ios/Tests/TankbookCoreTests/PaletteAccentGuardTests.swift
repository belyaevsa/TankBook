import Foundation
import Testing
import SwiftUI
@testable import TankbookCore

/// P6.7 + W8 - the palette's electric/interactive split, enforced.
///
/// `headlight` means *electric* and nothing else (docs/DESIGN.md -> Color
/// rules). Every use of it in the app sources must appear, by file and line,
/// in the allowlist below; anything outside the list is a bug that crept in
/// because someone needed "a blue" and reached for the accent. The list is
/// deliberately short so each addition is a deliberate, reviewable act - an
/// allowlist holding every current use would guard nothing.
///
/// W8: accent contrast is computed, not eyeballed. `action` and `headlight`
/// must clear 4.5:1 on both grounds (`midnight`, `dash`) in both themes -
/// light `headlight` at the old `#0E7FA6` measured 4.22:1 on light `midnight`.
@Suite("Palette accent guard (P6.7 + W8)")
struct PaletteAccentGuardTests {

    // MARK: - The electric allowlist

    /// The only `Theme.Palette.headlight` uses permitted in `ios/App/Sources`:
    /// file (relative to App/Sources) + the exact trimmed source line.
    private static let electricUses: Set<String> = [
        "CarSwitcher/CarSwitcherView.swift: vehicle.powertrain == .ev ? Theme.Palette.headlight : Theme.Palette.taillight",
        "Home/HomeSections.swift: case .charge: return Theme.Palette.headlight",
        "RecentlyDeleted/RecentlyDeletedView.swift: case is ChargeSession: return Theme.Palette.headlight",
        "Trends/TrendsView.swift: vehicle.powertrain == .ev ? Theme.Palette.headlight : Theme.Palette.taillight",
    ]

    private static var appSources: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // TankbookCoreTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // ios
            .appendingPathComponent("App/Sources", isDirectory: true)
    }

    /// Every `Palette.headlight` occurrence in the app sources, as
    /// "relative/path.swift: trimmed line".
    private static func headlightUses() throws -> Set<String> {
        let manager = FileManager.default
        guard let enumerator = manager.enumerator(
            at: appSources,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            Issue.record("cannot enumerate \(appSources.path)")
            return []
        }

        var uses = Set<String>()
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let contents = try String(contentsOf: url, encoding: .utf8)
            let relative = url.path.replacingOccurrences(of: appSources.path + "/", with: "")
            for line in contents.components(separatedBy: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.contains("Palette.headlight") else { continue }
                uses.insert("\(relative): \(trimmed)")
            }
        }
        return uses
    }

    @Test("Palette.headlight appears only at the allowlisted electric uses")
    func headlightUsesMatchTheElectricAllowlist() throws {
        let uses = try Self.headlightUses()
        let allowlist = Self.electricUses

        let unexpected = uses.subtracting(allowlist).sorted()
        #expect(unexpected.isEmpty,
                "Non-electric Palette.headlight uses (use Palette.action, or inkSoft when inert - docs/DESIGN.md): \(unexpected)")

        let missing = allowlist.subtracting(uses).sorted()
        #expect(missing.isEmpty,
                "Allowlisted electric uses not found (the use moved or changed - update the allowlist deliberately): \(missing)")
    }

    // MARK: - Exact hexes (P6.7: the values are the decision)

    private static func assertResolves(_ color: Color, hex: String, isDark: Bool) throws {
        let resolved = color.resolvedSRGBComponents(isDark: isDark)
        let expected = try #require(hexComponents(hex),
                                    "cannot parse expected hex \(hex)")
        #expect(abs(resolved.red - Double(expected.red)) < 0.001, "\(hex) red in \(isDark ? "dark" : "light")")
        #expect(abs(resolved.green - Double(expected.green)) < 0.001, "\(hex) green in \(isDark ? "dark" : "light")")
        #expect(abs(resolved.blue - Double(expected.blue)) < 0.001, "\(hex) blue in \(isDark ? "dark" : "light")")
    }

    /// Reads the expected value out of `design/tokens.json` rather than a hex
    /// literal. Two reasons, and the lint rule that forbids ad-hoc hex is only
    /// the second: a literal here is a TRANSCRIPTION of the source of truth, so
    /// it can agree with a generator that is wrong, while reading the token file
    /// checks the generator against the thing it generates from.
    private static func tokenHex(_ name: String, _ theme: String) throws -> String {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // TankbookCoreTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // ios
            .deletingLastPathComponent()  // repo root
        let data = try Data(contentsOf: repoRoot.appendingPathComponent("design/tokens.json"))
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let colors = root?["color"] as? [String: Any]
        let token = colors?[name] as? [String: String]
        return try #require(token?[theme], "design/tokens.json has no color.\(name).\(theme)")
    }

    @Test("action resolves to the design/tokens.json value in both themes")
    func actionHexes() throws {
        try Self.assertResolves(Theme.Palette.action, hex: Self.tokenHex("action", "dark"), isDark: true)
        try Self.assertResolves(Theme.Palette.action, hex: Self.tokenHex("action", "light"), isDark: false)
    }

    @Test("headlight resolves to the design/tokens.json value in both themes")
    func headlightHexes() throws {
        try Self.assertResolves(Theme.Palette.headlight, hex: Self.tokenHex("headlight", "dark"), isDark: true)
        try Self.assertResolves(Theme.Palette.headlight, hex: Self.tokenHex("headlight", "light"), isDark: false)
    }

    // MARK: - WCAG AA contrast (W8: computed from tokens.json)

    private struct ColorToken: Codable {
        let dark: String
        let light: String
    }

    private struct TokensFile: Codable {
        let color: [String: ColorToken]
    }

    private static func loadTokens() throws -> TokensFile {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // TankbookCoreTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // ios
            .deletingLastPathComponent() // repo root
        let url = repoRoot.appendingPathComponent("design/tokens.json")
        return try JSONDecoder().decode(TokensFile.self, from: Data(contentsOf: url))
    }

    /// WCAG 2.x relative luminance + contrast ratio for two "#RRGGBB" values.
    private static func contrastRatio(_ foreground: String, _ background: String) throws -> Double {
        func luminance(_ hex: String) throws -> Double {
            let components = try #require(hexComponents(hex), "cannot parse \(hex)")
            func channel(_ value: CGFloat) -> Double {
                let v = Double(value)
                return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * channel(components.red)
                + 0.7152 * channel(components.green)
                + 0.0722 * channel(components.blue)
        }
        let l1 = try luminance(foreground)
        let l2 = try luminance(background)
        let (lighter, darker) = max(l1, l2) == l1 ? (l1, l2) : (l2, l1)
        return (lighter + 0.05) / (darker + 0.05)
    }

    /// EVERY accent, not a chosen two. The first version of this test looped
    /// over `action` and `headlight` only - the two W8 happened to touch - while
    /// `docs/DESIGN.md` promises AA for every accent in both themes. It passed,
    /// and `warn` was failing at 3.82:1 on light `midnight` the whole time, used
    /// as caption text in ~15 files. A guard narrower than the rule it enforces
    /// reports success for the part nobody changed.
    @Test("every accent clears 4.5:1 on both grounds in both themes (W8)")
    func accentContrastClearsAA() throws {
        let tokens = try Self.loadTokens()

        for accent in ["action", "headlight", "warn", "taillight"] {
            let token = try #require(tokens.color[accent],
                                     "tokens.json has no '\(accent)' colour")
            for ground in ["midnight", "dash"] {
                let groundToken = try #require(tokens.color[ground],
                                               "tokens.json has no '\(ground)' colour")
                for (foreground, background, theme) in [
                    (token.light, groundToken.light, "light"),
                    (token.dark, groundToken.dark, "dark"),
                ] {
                    let ratio = try Self.contrastRatio(foreground, background)
                    #expect(ratio >= 4.5,
                            """
                            \(accent) \(theme) \(foreground) on \(ground) \(background): \
                            \(String(format: "%.2f", ratio)):1, under the 4.5:1 AA floor \
                            (docs/DESIGN.md -> Accessibility floor)
                            """)
                }
            }
        }
    }
}

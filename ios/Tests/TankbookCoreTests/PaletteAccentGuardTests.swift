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
        "Garage/GarageView.swift: vehicle.powertrain == .ev ? Theme.Palette.headlight : Theme.Palette.taillight",
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
    ///
    /// P6.19: this test still only checks accent-on-BACKGROUND. The dimension
    /// it never covered - and the reason eight white-on-accent sites shipped -
    /// is text drawn ON an accent fill; that is `textOnAccentClearsAA` below.
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

    // MARK: - Text on accent fills (P6.19)

    /// One text-on-accent use: a `.foregroundStyle` token drawn over a solid
    /// accent `.background` in the same view chain.
    private struct TextOnAccentUse: Equatable, CustomStringConvertible {
        let file: String
        let line: Int
        let foreground: String
        let fill: String

        var description: String { "\(file):\(line) \(foreground) on \(fill)" }
    }

    /// The text token a `.foregroundStyle` line draws on an accent fill.
    ///
    /// Swift ternary syntax puts the value that pairs with the accent first:
    /// `saveEnabled ? Theme.Palette.midnight : Theme.Palette.inkSoft` draws
    /// `midnight` when the (same-branch) accent background is showing. So the
    /// FIRST token in the line is the one that lands on the fill. For a plain
    /// `Color.white` / `Theme.Palette.X` there is only one token anyway.
    private static func foregroundToken(in line: String) -> String? {
        let candidates: [(String, String)] = [
            ("Color.white", "white"),
            (".white", "white"),
            ("Theme.Palette.midnight", "midnight"),
            ("Theme.Palette.inkSoft", "inkSoft"),
            ("Theme.Palette.ink", "ink")
        ]
        var earliest = line.endIndex
        var name: String?
        for (pattern, tokenName) in candidates {
            if let range = line.range(of: pattern), range.lowerBound < earliest {
                earliest = range.lowerBound
                name = tokenName
            }
        }
        return name
    }

    /// `Color.white` has no token - it is the pure system colour - so its hex is
    /// derived from the resolved components, never written as a literal (lint:
    /// ad-hoc hex is forbidden, hard rule 5). White is (1,1,1) in both themes.
    private static var whiteHexes: (String, String) {
        let components = Color.white.resolvedSRGBComponents(isDark: false)
        let hex = String(format: "#%02X%02X%02X",
                         Int((components.red * 255).rounded()),
                         Int((components.green * 255).rounded()),
                         Int((components.blue * 255).rounded()))
        return (hex, hex)
    }

    /// The accent a `.background` line fills with, or `nil` if it is not a
    /// solid accent fill.
    ///
    /// A tinted wash - `Theme.Palette.taillight.opacity(0.14)`, the segment
    /// chips, or `warn.opacity(0.08)` - is a selection highlight, not a fill;
    /// its effective colour is the blend with the ground, and ink on it clears
    /// AA (measured 12.05:1 dark). Only solid fills are the class this guard
    /// exists for, so `.opacity(` backgrounds are excluded here.
    private static func accentFill(in line: String) -> String? {
        guard !line.contains(".opacity(") else { return nil }
        let candidates: [(String, String)] = [
            ("Theme.Palette.warn", "warn"),
            ("Theme.Palette.taillight", "taillight"),
            ("Theme.Palette.action", "action"),
            ("Theme.Palette.headlight", "headlight")
        ]
        return candidates.first(where: { line.contains($0.0) })?.1
    }

    /// Every text-on-accent use in `ios/App/Sources`, as a modifier-chain scan.
    ///
    /// A chain is a view expression: the statement line plus its dot-modifiers
    /// until a blank line, a comment, a closing brace, or the next statement.
    /// Within one chain a `.foregroundStyle` token drawn over a `.background`
    /// accent fill is a text-on-accent use.
    ///
    /// What a text scan cannot see, said plainly: it cannot know that a
    /// ternary's two branches render at different times, so it takes the token
    /// that pairs with the accent branch (the first, per the doc on
    /// `foregroundToken`); it cannot resolve computed colours or `.tint()`, so
    /// a `ProgressView().tint(.white)` inside an accent button is invisible to
    /// it (the site is fixed by hand in P6.19); and it cannot read `opacity`,
    /// so tinted washes are excluded rather than judged.
    private static func textOnAccentUses() throws -> [TextOnAccentUse] {
        let manager = FileManager.default
        guard let enumerator = manager.enumerator(
            at: appSources,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            Issue.record("cannot enumerate \(appSources.path)")
            return []
        }

        var uses: [TextOnAccentUse] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let contents = try String(contentsOf: url, encoding: .utf8)
            let relative = url.path.replacingOccurrences(of: appSources.path + "/", with: "")
            var pendingForeground: String?
            for (index, rawLine) in contents.components(separatedBy: "\n").enumerated() {
                let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty
                    || trimmed.hasPrefix("//")
                    || trimmed == "}"
                    || !trimmed.hasPrefix(".") {
                    pendingForeground = nil
                }
                if trimmed.contains(".foregroundStyle") {
                    pendingForeground = Self.foregroundToken(in: trimmed)
                }
                if trimmed.contains(".background"),
                   let fill = Self.accentFill(in: trimmed),
                   let foreground = pendingForeground {
                    uses.append(TextOnAccentUse(file: relative, line: index + 1,
                                                foreground: foreground, fill: fill))
                }
            }
        }
        return uses
    }

    /// P6.19 - the dimension the earlier guards never checked. The first
    /// contrast guard looped over two accents, the widened one over four, and
    /// both only measured accent-on-BACKGROUND, so white-on-accent (2.15:1 dark
    /// on `warn`, 3.47:1 dark on `taillight`) sailed through twice. This checks
    /// text drawn ON an accent fill, over the whole class - every accent fill,
    /// both themes - not just the fill this change happened to touch.
    /// P6.19 - the whole class, computationally. `midnight` must stay the
    /// universally safe text on every accent fill in both themes (whether or
    /// not the source happens to draw it there), and no other text token may
    /// qualify - if one ever does, it is as legal as midnight and the P6.19
    /// substitution has a second option, which needs a deliberate decision.
    @Test("midnight is the only text token safe on every accent fill in both themes (P6.19)")
    func midnightIsTheOnlySafeTextOnAccentFills() throws {
        let tokens = try Self.loadTokens()
        let midnight = try #require(tokens.color["midnight"], "tokens.json has no 'midnight' colour")
        let ink = try #require(tokens.color["ink"], "tokens.json has no 'ink' colour")
        let inkSoft = try #require(tokens.color["inkSoft"], "tokens.json has no 'inkSoft' colour")
        let fillTokens = try ["action", "headlight", "warn", "taillight"].map { fill in
            (fill, try #require(tokens.color[fill], "tokens.json has no '\(fill)' colour"))
        }

        for (fill, token) in fillTokens {
            for (theme, foreground, background) in [
                ("light", midnight.light, token.light),
                ("dark", midnight.dark, token.dark)
            ] {
                let ratio = try Self.contrastRatio(foreground, background)
                #expect(ratio >= 4.5,
                        """
                        midnight on \(fill) \(theme) \(foreground) on \(background): \
                        \(String(format: "%.2f", ratio)):1, under the 4.5:1 AA floor - \
                        midnight must stay the one safe text on an accent fill \
                        (docs/DESIGN.md -> Accessibility floor)
                        """)
            }
        }

        for (name, token) in [("white", Self.whiteHexes),
                              ("ink", (ink.light, ink.dark)),
                              ("inkSoft", (inkSoft.light, inkSoft.dark))] {
            var clearsEverywhere = true
            for (_, fillToken) in fillTokens {
                let lightRatio = try Self.contrastRatio(token.0, fillToken.light)
                let darkRatio = try Self.contrastRatio(token.1, fillToken.dark)
                if lightRatio < 4.5 || darkRatio < 4.5 {
                    clearsEverywhere = false
                    break
                }
            }
            #expect(!clearsEverywhere,
                    """
                    \(name) now clears 4.5:1 on every accent fill in both themes - it is as \
                    legal as midnight; revisit the P6.19 substitution
                    """)
        }
    }

    /// P6.19 - text drawn ON an accent fill, over the whole class of pairs the
    /// sources actually draw. The first contrast guard looped over two accents,
    /// the widened one over four, and both only measured accent-on-BACKGROUND,
    /// so white-on-accent (2.15:1 dark on `warn`, 3.47:1 dark on `taillight`)
    /// sailed through twice. This is what fails at 2.15:1 the moment
    /// `Color.white` is put back on `warn`.
    @Test("text on accent fills clears 4.5:1 in both themes (P6.19)")
    func textOnAccentClearsAA() throws {
        let tokens = try Self.loadTokens()
        let uses = try Self.textOnAccentUses()
        #expect(!uses.isEmpty, "no text-on-accent uses found - the scan is probably broken")

        for use in uses {
            let foreground = use.foreground == "white"
                ? Self.whiteHexes
                : (tokens.color[use.foreground]?.light, tokens.color[use.foreground]?.dark)
            guard let fgLight = foreground.0, let fgDark = foreground.1,
                  let fillToken = tokens.color[use.fill] else {
                Issue.record("unknown foreground '\(use.foreground)' or fill '\(use.fill)' at \(use)")
                continue
            }
            for (theme, fgHex, bgHex) in [
                ("light", fgLight, fillToken.light),
                ("dark", fgDark, fillToken.dark)
            ] {
                let ratio = try Self.contrastRatio(fgHex, bgHex)
                #expect(ratio >= 4.5,
                        """
                        \(use) \(theme) \(fgHex) on \(bgHex): \
                        \(String(format: "%.2f", ratio)):1, under the 4.5:1 AA floor \
                        (docs/DESIGN.md -> Accessibility floor)
                        """)
            }
        }
    }

    /// P6.19 source guard: `Color.white` (and `.white`) must not appear as a
    /// foreground over an accent fill anywhere in `ios/App/Sources`. The one
    /// remaining `Color.white` in the sources is `SignInView.swift:155`, a
    /// BACKGROUND (the Apple Sign-In button), which this scan never matches -
    /// it only pairs a foreground token with an accent background.
    @Test("Color.white never sits as text on an accent fill (P6.19 source guard)")
    func noWhiteForegroundOnAccentFill() throws {
        let uses = try Self.textOnAccentUses()
        let whites = uses.filter { $0.foreground == "white" }
        #expect(whites.isEmpty,
                """
                white text on an accent fill - use Theme.Palette.midnight, the only token \
                clearing 4.5:1 on every accent fill in both themes: \(whites)
                """)
    }
}

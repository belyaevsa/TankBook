#!/usr/bin/env swift
// Tankbook design-token generator (P0.2).
// Reads design/tokens.json and writes ios/Sources/TankbookCore/Design/Theme.generated.swift.
// Run from anywhere: `swift scripts/generate-theme.swift`

import Foundation

struct ColorToken: Codable {
    let dark: String
    let light: String
}

struct SpacingToken: Codable {
    let base: Int
    let screenMargin: Int
    let cardPadding: Int
}

struct RadiusToken: Codable {
    let card: Int
}

struct HairlineToken: Codable {
    let color: String
    let opacity: Double
}

struct BorderToken: Codable {
    let hairline: HairlineToken
}

struct TokensFile: Codable {
    let color: [String: ColorToken]
    let spacing: SpacingToken
    let radius: RadiusToken
    let border: BorderToken
}

func die(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

func formatDouble(_ value: Double) -> String {
    if value == value.rounded() {
        return String(format: "%.1f", value)
    }
    return String(value)
}

let scriptURL = URL(fileURLWithPath: #filePath).standardizedFileURL
let repoRoot = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
let tokensURL = repoRoot.appendingPathComponent("design/tokens.json")
let outputURL = repoRoot
    .appendingPathComponent("ios/Sources/TankbookCore/Design/Theme.generated.swift")

guard let data = try? Data(contentsOf: tokensURL) else {
    die("cannot read \(tokensURL.path)")
}

let tokens: TokensFile
do {
    tokens = try JSONDecoder().decode(TokensFile.self, from: data)
} catch {
    die("cannot parse \(tokensURL.path): \(error)")
}

let colorNames = tokens.color.keys.sorted()

var lines: [String] = []
lines.append("// GENERATED FILE \u{2013} do not edit. Source: design/tokens.json")
lines.append("// Regenerate with: swift scripts/generate-theme.swift")
lines.append("")
lines.append("import SwiftUI")
lines.append("")
lines.append("/// The Tankbook design system (Night Drive palette).")
lines.append("/// All values derive from `design/tokens.json`; do not hand-edit.")
lines.append("public enum Theme {")
lines.append("    /// Semantic colours, resolved per system colour scheme.")
lines.append("    public enum Palette {")
for name in colorNames {
    let token = tokens.color[name]!
    lines.append("        public static let \(name) = Color(themeHexLight: \"\(token.light)\", themeHexDark: \"\(token.dark)\")")
}
lines.append("        /// Hairline border: `\(tokens.border.hairline.color)` at \(formatDouble(tokens.border.hairline.opacity)) opacity.")
lines.append("        public static let hairline = Theme.Palette.\(tokens.border.hairline.color).opacity(\(formatDouble(tokens.border.hairline.opacity)))")
lines.append("        static let hairlineOpacity: Double = \(formatDouble(tokens.border.hairline.opacity))")
lines.append("")
lines.append("        /// Every palette colour keyed by token name.")
lines.append("        public static let all: [String: Color] = [")
for name in colorNames {
    lines.append("            \"\(name)\": \(name),")
}
lines.append("        ]")
lines.append("    }")
lines.append("")
lines.append("    public enum Spacing {")
lines.append("        public static let base: CGFloat = \(tokens.spacing.base)")
lines.append("        public static let screenMargin: CGFloat = \(tokens.spacing.screenMargin)")
lines.append("        public static let cardPadding: CGFloat = \(tokens.spacing.cardPadding)")
lines.append("    }")
lines.append("")
lines.append("    public enum Radius {")
lines.append("        public static let card: CGFloat = \(tokens.radius.card)")
lines.append("    }")
lines.append("}")

let output = lines.joined(separator: "\n") + "\n"
do {
    try output.write(to: outputURL, atomically: true, encoding: .utf8)
} catch {
    die("cannot write \(outputURL.path): \(error)")
}
print("wrote \(outputURL.path)")

#!/usr/bin/env swift
// Tankbook site design-token generator (W1).
// Reads design/tokens.json and writes site/assets/css/tokens.generated.css.
// Run from anywhere: `swift scripts/generate-site-tokens.swift`
// Pass `--check` to verify the committed file matches without writing: exit 1 on any difference.

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

// "inkSoft" -> "ink-soft", "tabBarBorder" -> "tab-bar-border"
func kebab(_ name: String) -> String {
    var result = ""
    for ch in name {
        if ch.isUppercase {
            result.append("-")
            result.append(Character(ch.lowercased()))
        } else {
            result.append(ch)
        }
    }
    return result
}

func hexRGB(_ hex: String) -> String {
    var body = hex
    if body.hasPrefix("#") {
        body.removeFirst()
    }
    guard body.count == 6, let value = UInt64(body, radix: 16) else {
        die("cannot parse colour hex \(hex)")
    }
    let red = (value >> 16) & 0xFF
    let green = (value >> 8) & 0xFF
    let blue = value & 0xFF
    return "\(red), \(green), \(blue)"
}

let checkOnly = CommandLine.arguments.contains("--check")

let scriptURL = URL(fileURLWithPath: #filePath).standardizedFileURL
let repoRoot = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
let tokensURL = repoRoot.appendingPathComponent("design/tokens.json")
let outputURL = repoRoot
    .appendingPathComponent("site/assets/css/tokens.generated.css")

guard let data = try? Data(contentsOf: tokensURL) else {
    die("cannot read \(tokensURL.path)")
}

let tokens: TokensFile
do {
    tokens = try JSONDecoder().decode(TokensFile.self, from: data)
} catch {
    die("cannot parse \(tokensURL.path): \(error)")
}

// Sorted so the diff stays stable when tokens.json is reordered.
let colorNames = tokens.color.keys.sorted()

let hairlineName = tokens.border.hairline.color
guard let hairlineToken = tokens.color[hairlineName] else {
    die("hairline references unknown colour token \(hairlineName)")
}
let hairlineOpacity = formatDouble(tokens.border.hairline.opacity)

func customProperties(scheme: String) -> [String] {
    var lines: [String] = []
    for name in colorNames {
        let token = tokens.color[name]!
        let value = scheme == "light" ? token.light : token.dark
        lines.append("  --\(kebab(name)): \(value);")
    }
    let hairlineHex = scheme == "light" ? hairlineToken.light : hairlineToken.dark
    let hairlineRGB = hexRGB(hairlineHex)
    lines.append("  --border-hairline: rgba(\(hairlineRGB), \(hairlineOpacity));")
    lines.append("  --radius-card: \(tokens.radius.card)px;")
    lines.append("  --spacing-base: \(tokens.spacing.base)px;")
    lines.append("  --spacing-card-padding: \(tokens.spacing.cardPadding)px;")
    lines.append("  --spacing-screen-margin: \(tokens.spacing.screenMargin)px;")
    return lines
}

var lines: [String] = []
lines.append("/* GENERATED FILE \u{2013} do not edit. Source: design/tokens.json */")
lines.append("/* Regenerate with: swift scripts/generate-site-tokens.swift */")
lines.append("")
lines.append("/* The Tankbook design system (Night Drive palette) for the web.")
lines.append("   Dark values on :root, light values under prefers-color-scheme: light.")
lines.append("   All values derive from design/tokens.json; do not hand-edit. */")
lines.append(":root {")
lines.append("  color-scheme: dark light;")
lines.append(contentsOf: customProperties(scheme: "dark"))
lines.append("}")
lines.append("")
lines.append("@media (prefers-color-scheme: light) {")
lines.append("  :root {")
lines.append(contentsOf: customProperties(scheme: "light"))
lines.append("  }")
lines.append("}")

let output = lines.joined(separator: "\n") + "\n"

if checkOnly {
    // Compare what we would render against what is on disk. Never write during --check.
    guard let onDisk = try? Data(contentsOf: outputURL) else {
        die("--check: cannot read \(outputURL.path); run once without --check to generate it")
    }
    if Data(output.utf8) == onDisk {
        print("--check: \(outputURL.path) matches design/tokens.json")
    } else {
        let message = "--check: \(outputURL.path) differs from design/tokens.json\n" +
            "regenerate with: swift scripts/generate-site-tokens.swift\n"
        FileHandle.standardError.write(Data(message.utf8))
        exit(1)
    }
} else {
    let outputDir = outputURL.deletingLastPathComponent()
    do {
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
    } catch {
        die("cannot create \(outputDir.path): \(error)")
    }
    do {
        try output.write(to: outputURL, atomically: true, encoding: .utf8)
    } catch {
        die("cannot write \(outputURL.path): \(error)")
    }
    print("wrote \(outputURL.path)")
}

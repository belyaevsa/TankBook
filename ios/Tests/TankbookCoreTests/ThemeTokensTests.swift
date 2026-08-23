import Testing
import Foundation
import SwiftUI
@testable import TankbookCore

/// Parses design/tokens.json (mirror of the generator's `TokensFile`).
private struct TokensFile: Codable {
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

    let color: [String: ColorToken]
    let spacing: SpacingToken
    let radius: RadiusToken
    let border: BorderToken
}

private func loadTokens() throws -> TokensFile {
    let testFile = URL(fileURLWithPath: #filePath)
    let repoRoot = testFile
        .deletingLastPathComponent() // TankbookCoreTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // ios
        .deletingLastPathComponent() // repo root
    let url = repoRoot.appendingPathComponent("design/tokens.json")
    let data = try Data(contentsOf: url)
    return try JSONDecoder().decode(TokensFile.self, from: data)
}

private func isClose(_ lhs: Double, _ rhs: Double) -> Bool {
    abs(lhs - rhs) < 0.001
}

private func expectedComponents(_ hex: String) -> (red: Double, green: Double, blue: Double)? {
    hexComponents(hex).map {
        (red: Double($0.red), green: Double($0.green), blue: Double($0.blue))
    }
}

@Test func generatedPaletteMatchesTokensJSON() throws {
    let tokens = try loadTokens()

    #expect(tokens.color.count == Theme.Palette.all.count,
            "Every colour in tokens.json must be exposed by Theme.Palette.all")

    for (name, token) in tokens.color {
        let color = try #require(Theme.Palette.all[name],
                                 "Colour '\(name)' from tokens.json is missing from Theme.Palette")

        let light = color.resolvedSRGBComponents(isDark: false)
        let expectedLight = expectedComponents(token.light)
        #expect(isClose(light.red, expectedLight?.red ?? -1), "\(name) light red mismatch")
        #expect(isClose(light.green, expectedLight?.green ?? -1), "\(name) light green mismatch")
        #expect(isClose(light.blue, expectedLight?.blue ?? -1), "\(name) light blue mismatch")

        let dark = color.resolvedSRGBComponents(isDark: true)
        let expectedDark = expectedComponents(token.dark)
        #expect(isClose(dark.red, expectedDark?.red ?? -1), "\(name) dark red mismatch")
        #expect(isClose(dark.green, expectedDark?.green ?? -1), "\(name) dark green mismatch")
        #expect(isClose(dark.blue, expectedDark?.blue ?? -1), "\(name) dark blue mismatch")
    }
}

@Test func generatedSpacingAndRadiusMatchTokensJSON() throws {
    let tokens = try loadTokens()

    #expect(Theme.Spacing.base == CGFloat(tokens.spacing.base))
    #expect(Theme.Spacing.screenMargin == CGFloat(tokens.spacing.screenMargin))
    #expect(Theme.Spacing.cardPadding == CGFloat(tokens.spacing.cardPadding))
    #expect(Theme.Radius.card == CGFloat(tokens.radius.card))
}

@Test func generatedHairlineMatchesTokensJSON() throws {
    let tokens = try loadTokens()

    // The hairline border is the palette colour at the encoded opacity
    // (docs/DESIGN.md: 1px hairline border, `ink` at 8%).
    #expect(Theme.Palette.hairlineOpacity == tokens.border.hairline.opacity)
    #expect(Theme.Palette.all[tokens.border.hairline.color] != nil,
            "hairline references '\(tokens.border.hairline.color)', which is not a palette colour")
}

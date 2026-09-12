import Foundation
import Testing
@testable import TankbookCore

// RV.228 - the `units` ambiguity is reserved, not a v1 question. No v1 parser
// emits it, so its presence must not gate the commit, and every text that
// describes it (the `ImportAmbiguity` doc comment, docs/API.md, docs/JOURNEYS.md
// F6/F6a, docs/ERRORS.md, docs/SCHEMA.md) must agree that it is reserved - so
// one cannot be edited without the others. This is the RV.210-shaped guard for
// this exact drift.

@Suite("Import `units` ambiguity is reserved (RV.228)")
struct RV228ReservedUnitsTests {

    // MARK: - Source location

    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // TankbookCoreTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // ios
            .deletingLastPathComponent()  // repo root
    }

    private static func text(_ relative: String) throws -> String {
        try String(contentsOf: repoRoot.appendingPathComponent(relative), encoding: .utf8)
    }

    private static func parse(ambiguities: [ImportAmbiguity]) -> ImportParseResponse {
        ImportParseResponse(importId: "id", format: "mfm", scope: "vehicle",
                            candidates: [], unparsed: [], ambiguities: ambiguities)
    }

    /// The contiguous `///` block immediately above `public struct ImportAmbiguity`.
    private static func ambiguityDocComment(in source: String) -> String? {
        guard let structRange = source.range(of: "public struct ImportAmbiguity") else { return nil }
        let before = source[source.startIndex..<structRange.lowerBound]
        var lines: [String] = []
        for line in before.split(separator: "\n", omittingEmptySubsequences: false).reversed() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("///") {
                lines.append(trimmed)
            } else if trimmed.isEmpty {
                continue
            } else {
                break
            }
        }
        return lines.reversed().joined(separator: "\n")
    }

    private static func section(in doc: String, from start: String, to end: String) -> String? {
        guard let startRange = doc.range(of: start),
              let endRange = doc.range(of: end, range: startRange.upperBound..<doc.endIndex) else {
            return nil
        }
        return String(doc[startRange.lowerBound..<endRange.lowerBound])
    }

    // MARK: - L1: the commit gate treats `units` as reserved

    /// A `units` ambiguity does NOT block the commit, by design: the kind is
    /// reserved and no v1 parser emits it (both shipped importers are metric).
    /// If an imperial importer (P5.4b) starts emitting it, this test must be
    /// replaced by one asserting the question blocks until answered.
    @Test func aUnitsAmbiguityDoesNotBlockTheCommitBecauseNoV1ParserEmitsIt() {
        let parse = Self.parse(ambiguities: [
            ImportAmbiguity(kind: "units", options: ["MPG", "L/100km"], rowCount: 3)
        ])
        #expect(parse.canCommit(dateFormatAnswer: nil, currencyAnswer: nil) == true,
                "`units` is reserved; canCommit must keep passing so a stray kind cannot gate v1")
    }

    // MARK: - L1: the three texts agree it is reserved

    @Test func theReservedUnitsContractAgreesAcrossTheTexts() throws {
        let model = try Self.text("ios/Sources/TankbookCore/Import/ImportModels.swift")
        let api = try Self.text("docs/API.md")
        let journeys = try Self.text("docs/JOURNEYS.md")

        let modelComment = try #require(Self.ambiguityDocComment(in: model),
            "the `ImportAmbiguity` doc comment must exist for the guard to read")
        #expect(modelComment.contains("reserved"),
                "the ImportAmbiguity comment must call `units` reserved")

        let apiWireLine = try #require(api.split(separator: "\n").map(String.init)
            .first { $0.contains("kind: \"dateFormat\"") },
            "docs/API.md must carry the ambiguity wire shape")
        #expect(apiWireLine.contains("reserved"),
                "docs/API.md's ambiguity shape must call `units` reserved")
        #expect(api.contains("`units`: **reserved"),
                "docs/API.md's `units` bullet must call the kind reserved")

        let f6 = try #require(Self.section(in: journeys, from: "### F6 · ", to: "### F6a · "),
            "docs/JOURNEYS.md must carry the F6 section")
        #expect(f6.contains("reserved") && f6.contains("N/A for v1"),
                "F6 must mark the units half N/A for v1 and call `units` reserved")

        let f6a = try #require(Self.section(in: journeys, from: "### F6a · ", to: "### F6b · "),
            "docs/JOURNEYS.md must carry the F6a section")
        let f6aMarkers = f6a.components(separatedBy: "N/A for v1").count - 1
        #expect(f6aMarkers >= 2,
                "F6a's two units bullets must both carry the N/A marker - found \(f6aMarkers)")

        let errors = try Self.text("docs/ERRORS.md")
        let importWizard = try #require(
            Self.section(in: errors, from: "### Import wizard", to: "### About & feedback"),
            "docs/ERRORS.md must carry the import-wizard section")
        #expect(importWizard.contains("`units` reserved"),
                "the import-wizard error catalog must mark `units` reserved")

        let schema = try Self.text("docs/SCHEMA.md")
        #expect(schema.contains("`units` is reserved"),
                "docs/SCHEMA.md's import rules must mark `units` reserved")
    }

    // MARK: - L1: the preview hint names what is actually adjustable

    /// The hint above the derived-consumption figure must not point at a units
    /// row (none is adjustable in v1); it names the date format and the currency
    /// question, which the preview does offer.
    @Test func thePreviewHintNamesWhatTheUserCanActuallyChange() throws {
        let preview = try Self.text("ios/App/Sources/Import/ImportPreviewView.swift")
        #expect(!preview.contains("check the units below"),
                "the hint must not promise an adjustable units row")
        #expect(preview.contains("check the date format or currency"),
                "the hint must name the date-format and currency questions the preview offers")
    }
}

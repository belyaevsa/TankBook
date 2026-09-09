import Foundation
import Testing

// RV.167 - the source-scan guard for money aggregation. The zero-summing defect
// (a rate-pending row's missing `homeAmount` banked as zero) was fixed on six
// surfaces one row at a time - RV.106, RV.112, RV.145, RV.147, RV.166 - and a
// seventh (RV.148, the monthly-summary push) is parked by the product owner.
// What made the siblings possible is that nothing failed when a new surface
// summed money its own way: prose in a brief cannot fail a build, and a doc
// comment once asserted the bug was not there one line above `?? Decimal.zero`.
//
// The guard is a pure function over source text - `HomeSideSumScanner` - that
// flags a `.reduce` whose closure reads a `Money`'s home side (`homeAmount`).
// That is the discriminator, and it is not the word `reduce`: the look-alike
// sums in the tree accumulate a plain `Decimal` off a receipt (OCR line
// amounts), the ORIGINAL amount of a `Money` pair that always exists when the
// money does (import), or a draft's untyped cost - in none of them is a missing
// value a rate waiting to be known, so a nil genuinely is zero. Only the home
// side of a `Money` pair has the "not known yet" meaning, and the one place
// allowed to decide what such a row contributes to a figure is
// `LogStream.MonthTotal.Accumulator.add(_:)`.
//
// `MonthlySummaryNotification.swift` (RV.148) is the ONE known live violation,
// parked with a reasoned allowlist entry below, not licensed. The park has
// teeth: delete the entry and the walk fails on that file and line, and when
// RV.148 lands the stale-entry check fails until the row is removed. The
// scanner's own file is implicitly allowed - it IS the rule.
@Suite("Money home-side sums route through the shared accumulator (RV.167)")
struct MoneyHomeSideSumGuardTests {

    // MARK: - The allowlist (deliberate, reasoned exceptions only)

    /// One parked row: the monthly-summary push's month figure still banks a
    /// rate-pending row as zero. Deferred by the product owner (RV.148); it is
    /// a park, not a licence - route it through the accumulator when that row
    /// lands, and delete this entry in the same change. A bare path entry with
    /// no reason is a skip list and fails `reasonProblem` below.
    private struct Exception {
        let file: String
        let signature: String
        let reason: String
    }

    private static let allowlistedExceptions: [Exception] = [
        Exception(
            file: "Sources/TankbookCore/Service/MonthlySummaryNotification.swift",
            signature: "let total = inMonth.reduce(Decimal.zero) { partial, entry in",
            reason: "RV.148 - the monthly-summary push, deferred by the product owner. " +
                "Parks the last home-side sum; route it through the accumulator when it lands.")
    ]

    /// The accumulator's own file is the definition of the rule, so it is the
    /// implicit allowlist - any summation inside it is the policy itself.
    private static let accumulatorFile = "Sources/TankbookCore/Consumption/LogStream+Accumulator.swift"

    private static func reasonProblem(in exception: Exception) -> String? {
        let trimmed = exception.reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty else { return nil }
        return "allowlist exception for \(exception.file) carries no reason - " +
            "a bare path entry is a skip list, not a deliberate exception"
    }

    // MARK: - Source location

    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // TankbookCoreTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // ios
            .deletingLastPathComponent()  // repo root
    }

    private static var scannedRoots: [(prefix: String, url: URL)] {
        let core = repoRoot.appendingPathComponent("ios/Sources/TankbookCore")
        let app = repoRoot.appendingPathComponent("ios/App/Sources")
        return [("Sources/TankbookCore/", core), ("App/Sources/", app)]
    }

    private static func source(under prefix: String, path: String) throws -> String {
        let root = try #require(scannedRoots.first { prefix.hasPrefix($0.prefix) }?.url,
                                "no scanned root for \(prefix)")
        let url = root.appendingPathComponent(path)
        return try String(contentsOf: url, encoding: .utf8)
    }

    // MARK: - The tree walk

    /// Every flagged site across both source roots, as "scanned-label + site".
    /// A site's identity is `HomeSideSumScanner.Site` - the reduce's line and
    /// the trimmed text of that line, so a park survives edits above it but
    /// dies when the reduce itself is rewritten or removed.
    private static func flaggedSitesInTree() throws -> [(file: String, site: HomeSideSumScanner.Site)] {
        var all: [(file: String, site: HomeSideSumScanner.Site)] = []
        let manager = FileManager.default
        for (prefix, root) in scannedRoots {
            guard let enumerator = manager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else {
                Issue.record("cannot enumerate \(root.path)")
                continue
            }
            for case let url as URL in enumerator where url.pathExtension == "swift" {
                let contents = try String(contentsOf: url, encoding: .utf8)
                let relative = url.path.replacingOccurrences(of: root.path + "/", with: "")
                for site in HomeSideSumScanner.flaggedSites(in: contents) {
                    all.append((file: prefix + relative, site: site))
                }
            }
        }
        return all.sorted { ($0.file, $0.site.line) < ($1.file, $1.site.line) }
    }

    // MARK: - L1: the scanner fails on the known row, today

    /// RV.148's parked row is the witness that the scanner has teeth: it is the
    /// one live home-side sum, and if it were ever not flagged (fixed in place
    /// without the allowlist entry going away) both this test and the walk's
    /// stale check below fail. Delete this test when RV.148 lands.
    @Test func scannerFlagsTheDeferredMonthlySummaryRow() throws {
        let source = try Self.source(under: "Sources/TankbookCore/",
                                     path: "Service/MonthlySummaryNotification.swift")
        let hits = HomeSideSumScanner.flaggedSites(in: source)
        #expect(hits.contains { $0.line == 178 && $0.signature.hasPrefix("let total = inMonth.reduce") },
                "the deferred monthly-summary row must be flagged at line 178 - got \(hits)")
    }

    // MARK: - L1: the look-alikes are NOT the shape

    /// The look-alike classes must pass through the same function with their
    /// real source as input: the importer, the two draft forms, and the
    /// extraction/OCR line sums. Each accumulates a plain `Decimal` (an OCR line
    /// amount, or the ORIGINAL amount of a `Money` that always exists) or a
    /// draft's untyped cost - in no case is there a home-currency side whose nil
    /// means "the rate is not known yet", so a missing value genuinely is zero.
    /// A guard that flagged these would need an allowlist entry per site, which
    /// is exactly how a guard degrades into a skip list.
    @Test func scannerLeavesTheLookAlikeMoneySumsAlone() throws {
        let lookAlikes: [(prefix: String, path: String)] = [
            ("Sources/TankbookCore/", "Import/ImportConversion.swift"),
            ("Sources/TankbookCore/", "Service/ServiceEntryDraft.swift"),
            ("App/Sources/", "ServiceEntry/ServiceEntryFormState.swift"),
            ("Sources/TankbookCore/", "Extraction/InvoiceSplitter.swift"),
            ("Sources/TankbookCore/", "Extraction/MixedReceipt.swift"),
            ("App/Sources/", "ConfirmManual/MixedReceiptSection.swift")
        ]
        for lookAlike in lookAlikes {
            let source = try Self.source(under: lookAlike.prefix, path: lookAlike.path)
            let hits = HomeSideSumScanner.flaggedSites(in: source)
            #expect(hits.isEmpty,
                    """
                    \(lookAlike.prefix)\(lookAlike.path) must not be flagged - it sums a plain \
                    Decimal or an always-known original amount, not a rate-pending home side; \
                    got \(hits)
                    """)
        }
    }

    // MARK: - L1: the shape, not the one line

    /// A newly written reduce-over-homeAmount, supplied as raw source text, is
    /// flagged. This is the case that proves the scanner matches the shape and
    /// not the one known line: the walk test above can only ever see today's
    /// tree, this one can be shown any future violation.
    @Test func scannerFlagsANewlyWrittenReduceOverHomeAmount() {
        let hits = HomeSideSumScanner.flaggedSites(in: Self.newlyWrittenHomeSideReduce)
        #expect(hits.contains { $0.line == 1 && $0.signature.hasPrefix("let monthSpend") },
                "a new reduce over homeAmount must be flagged at its reduce line - got \(hits)")
    }

    /// The inverse of the fixture above: the same money routed through
    /// `LogStream.MonthTotal.Accumulator` is not the shape and must not flag.
    /// This is the unit-level form of the second mutation the row demands.
    @Test func scannerLeavesAccumulatorRoutedSourceAlone() {
        let hits = HomeSideSumScanner.flaggedSites(in: Self.accumulatorRoutedFixture)
        #expect(hits.isEmpty,
                "accumulator-routed money must not flag - got \(hits)")
    }

    // MARK: - L1: the walk over both source roots

    /// Every flagged site in `ios/Sources/TankbookCore` AND `ios/App/Sources`
    /// must route through the accumulator or carry a reasoned allowlist entry.
    /// Three of the six fixed instances lived in the app target, so a core-only
    /// scan would be a vacuous pass. The failure names `file:line` and the
    /// accumulator, so the person who sees it knows what to do instead.
    @Test func everyHomeSideSumRoutesThroughTheAccumulatorOrIsParked() throws {
        let sites = try Self.flaggedSitesInTree()

        for exception in Self.allowlistedExceptions {
            if let problem = Self.reasonProblem(in: exception) {
                Issue.record("allowlist self-check: \(problem)")
            }
        }

        let covered = { (site: (file: String, site: HomeSideSumScanner.Site)) -> Bool in
            if site.file == Self.accumulatorFile { return true }
            return Self.allowlistedExceptions.contains {
                $0.file == site.file && $0.signature == site.site.signature
            }
        }
        for site in sites where !covered(site) {
            Issue.record("""
                \(site.file):\(site.site.line) sums a Money's home side directly - \
                "\(site.site.signature)". A rate-pending row's homeAmount is not known, so \
                this reduce banks it as zero. Route every money pair through \
                LogStream.MonthTotal.Accumulator.add(_:) - the one place that decides what \
                a rate-pending row contributes - or park the site as a reasoned allowlist \
                entry above.
                """)
        }

        let stale = Self.allowlistedExceptions.filter { exception in
            !sites.contains { $0.file == exception.file && $0.site.signature == exception.signature }
        }
        for exception in stale {
            Issue.record("""
                allowlisted exception \(exception.file) "\(exception.signature)" no longer \
                matches a flagged sum - the site moved or was fixed. Update the table \
                deliberately; removing the RV.148 park is how that row's fix lands.
                """)
        }
    }

    // MARK: - L1: the allowlist self-check

    /// A bare allowlist entry - a path with no reason - must fail. The walk
    /// above checks the real table through `reasonProblem`; this test pins the
    /// rule itself so a future table edit cannot quietly degrade into a skip
    /// list while every site happens to be covered.
    @Test func aReasonlessAllowlistEntryFailsTheSelfCheck() {
        let bare = Exception(file: "Sources/TankbookCore/Somewhere/Future.swift",
                             signature: "let spend = rows.reduce(Decimal.zero) { ... }",
                             reason: " \n  ")
        #expect(Self.reasonProblem(in: bare) != nil,
                "an allowlist entry with no reason must fail the self-check")
    }

    // MARK: - Fixtures

    private static let newlyWrittenHomeSideReduce = """
        let monthSpend = entries.reduce(Decimal.zero) { partial, entry in
            guard let homeAmount = entry.money?.homeAmount else { return partial }
            return partial + homeAmount
        }
        """

    private static let accumulatorRoutedFixture = """
        var accumulator = LogStream.MonthTotal.Accumulator(vehicleHome: vehicle.homeCurrency)
        accumulator.add(contentsOf: inMonth.map { $0.money })
        return accumulator.monthTotal
        """
}

/// The scanner: a pure function over source text, so a test can feed it any
/// string (the tree, a single file, or a hand-written fixture). It flags a
/// `.reduce` whose closure reads `homeAmount` - the home-currency side of a
/// `Money` pair whose absence means "the rate is not known yet". Strings and
/// comments are masked before scanning so prose that mentions `.reduce(` can
/// never be mistaken for code.
enum HomeSideSumScanner {
    struct Site: Equatable {
        let line: Int
        let signature: String
    }

    static func flaggedSites(in source: String) -> [Site] {
        let characters = Array(source)
        let mask = Array(Self.codeMask(for: source))
        var lineStarts = [0]
        for (index, character) in characters.enumerated() where character == "\n" {
            lineStarts.append(index + 1)
        }
        func lineNumber(at offset: Int) -> Int {
            var low = 0
            var high = lineStarts.count - 1
            while low <= high {
                let mid = (low + high) / 2
                if lineStarts[mid] <= offset { low = mid + 1 } else { high = mid - 1 }
            }
            return high + 1
        }
        func signature(at offset: Int) -> String {
            var start = offset
            while start > 0, characters[start - 1] != "\n" { start -= 1 }
            var end = start
            while end < characters.count, characters[end] != "\n" { end += 1 }
            return String(characters[start..<end]).trimmingCharacters(in: .whitespaces)
        }

        var sites: [Site] = []
        var cursor = 0
        while cursor < mask.count {
            guard mask[cursor] == ".",
                  let wordEnd = Self.match("reduce", in: mask, from: cursor + 1) else {
                cursor += 1
                continue
            }
            let open = Self.firstNonSpace(in: mask, from: wordEnd)
            guard open < mask.count, mask[open] == "(",
                  let close = Self.matchingDelimiter(in: mask, from: open, open: "(", close: ")") else {
                cursor += 1
                continue
            }
            let brace = Self.firstNonSpace(in: mask, from: close + 1)
            guard brace < mask.count, mask[brace] == "{",
                  let endBrace = Self.matchingDelimiter(in: mask, from: brace, open: "{", close: "}") else {
                cursor += 1
                continue
            }
            let body = String(mask[(brace + 1)..<endBrace])
            if body.contains("homeAmount") {
                sites.append(Site(line: lineNumber(at: cursor), signature: signature(at: cursor)))
            }
            cursor = endBrace + 1
        }
        return sites
    }

    /// Matches `word` starting at `from`, returning the index just past it, or
    /// nil. The character after the word must not be an identifier letter, so
    /// `.reduceSum(...)` never reads as `.reduce`.
    private static func match(_ word: String, in mask: [Character], from: Int) -> Int? {
        let letters = Array(word)
        let end = from + letters.count
        guard end <= mask.count, Array(mask[from..<end]) == letters else { return nil }
        if end < mask.count, Self.isIdentifierCharacter(mask[end]) { return nil }
        return end
    }

    private static func isIdentifierCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_"
    }

    private static func firstNonSpace(in mask: [Character], from: Int) -> Int {
        var index = from
        while index < mask.count,
              mask[index] == " " || mask[index] == "\t"
              || mask[index] == "\n" || mask[index] == "\r" {
            index += 1
        }
        return index
    }

    /// The index of the delimiter that balances `open` at `from`, or nil when
    /// the source ends first.
    private static func matchingDelimiter(in mask: [Character], from: Int,
                                          open: Character, close: Character) -> Int? {
        var depth = 0
        var index = from
        while index < mask.count {
            if mask[index] == open {
                depth += 1
            } else if mask[index] == close {
                depth -= 1
                if depth == 0 { return index }
            }
            index += 1
        }
        return nil
    }

    /// A copy of the source with string literals and comments blanked out,
    /// same length and same newlines, so bracket counting and `.reduce`/
    /// `homeAmount` matching only ever see code.
    private static func codeMask(for source: String) -> String {
        let characters = Array(source)
        var output = characters
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if character == "/", index + 1 < characters.count, characters[index + 1] == "/" {
                while index < characters.count, characters[index] != "\n" {
                    output[index] = " "
                    index += 1
                }
                continue
            }
            if character == "/", index + 1 < characters.count, characters[index + 1] == "*" {
                output[index] = " "
                output[index + 1] = " "
                index += 2
                var closed = false
                while index < characters.count {
                    if characters[index] == "*", index + 1 < characters.count,
                       characters[index + 1] == "/" {
                        output[index] = " "
                        output[index + 1] = " "
                        index += 2
                        closed = true
                        break
                    }
                    output[index] = " "
                    index += 1
                }
                if !closed { break }
                continue
            }
            if character == "\"" {
                index = Self.maskString(in: characters, output: &output, index: index)
                continue
            }
            index += 1
        }
        return String(output)
    }

    private static func maskString(in characters: [Character], output: inout [Character],
                                   index start: Int) -> Int {
        var index = start
        if index + 2 < characters.count,
           characters[index + 1] == "\"", characters[index + 2] == "\"" {
            // Multiline literal: blank through the closing triple quote.
            for offset in 0..<3 { output[index + offset] = " " }
            index += 3
            while index < characters.count {
                if index + 2 < characters.count,
                   characters[index] == "\"", characters[index + 1] == "\"",
                   characters[index + 2] == "\"" {
                    for offset in 0..<3 { output[index + offset] = " " }
                    index += 3
                    return index
                }
                output[index] = " "
                index += 1
            }
            return index
        }
        output[index] = " "
        index += 1
        while index < characters.count {
            if characters[index] == "\\" {
                output[index] = " "
                if index + 1 < characters.count {
                    output[index + 1] = " "
                    index += 2
                } else {
                    index += 1
                }
                continue
            }
            if characters[index] == "\"" {
                output[index] = " "
                return index + 1
            }
            output[index] = " "
            index += 1
        }
        return index
    }
}

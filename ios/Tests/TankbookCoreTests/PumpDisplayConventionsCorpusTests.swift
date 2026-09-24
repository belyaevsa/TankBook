import Foundation
import Testing
@testable import TankbookCore

/// The measured conventions table against the corpus it was measured on: for
/// every reviewed transaction window with a non-zero asserted value the CSV does
/// not dispute, a decimal placement that reproduces the value from the displayed
/// digits must be in the table's read set, and every displayed cell count must be
/// one the table admits.
/// An intake that shows a new convention fails here and names the window,
/// instead of the law silently refusing that display.
@Suite("Pump display conventions against the corpus")
struct PumpDisplayConventionsCorpusTests {
    @Test("every reviewed window's placement and cell count is in its currency's measured row", .pumpFixturesPresent)
    func tableCoversTheCorpus() throws {
        let expected = try CorpusScorer.loadExpected(
            PumpReaderTestSupport.pumpFixturesRoot.appendingPathComponent("expected.csv"))
        let data = try Data(contentsOf: PumpReaderTestSupport.windowsURL)
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        var misses: [String] = []
        var windows = 0
        var derived: [String: Set<Int>] = [:]
        var byCells: [String: [Int: Set<Int>]] = [:]
        for (name, value) in root.sorted(by: { $0.key < $1.key }) {
            guard name != "_about", let ann = value as? [String: Any], ann["reviewed"] as? Bool == true,
                  let want = expected[name] else { continue }
            let conventions = PumpDisplayConventions.forCurrency(want.currency)
            guard conventions.isMeasured else {
                misses.append("\(name): currency \(want.currency?.rawValue ?? "none") has no row")
                continue
            }
            let disputed = Set((ann["csvDisagrees"] as? [String: Any])?.keys.map { $0 } ?? [])
            for raw in ann["windows"] as? [[String: Any]] ?? [] {
                guard let fieldName = raw["field"] as? String, let field = PumpField(rawValue: fieldName),
                      [.liters, .unitPrice, .total].contains(field), let text = raw["text"] as? String else { continue }
                let digits = text.filter(\.isNumber)
                guard !digits.isEmpty else { continue }
                windows += 1
                if !conventions.admits(field, cells: digits.count) {
                    misses.append("\(name) \(fieldName): \(digits.count) cells not admitted")
                }
                let asserted: Double? = field == .liters ? want.liters : field == .unitPrice ? want.unitPrice : want.total
                guard let value = asserted, value != 0, !disputed.contains(fieldName),
                      let integer = Double(digits) else { continue }
                let reproducing = (0...4).filter { abs(integer / pow(10, Double($0)) - value) < 1e-9 }
                let read = conventions.decimals(field, cells: digits.count)
                // A value the digits reproduce exactly is READ at that placement;
                // the truncated tier is for a total that reproduces at none
                // (skipped above, the derived-total exemption).
                let allowed = Set(read)
                if let code = want.currency?.rawValue {
                    derived["\(code) \(fieldName)", default: []].formUnion(reproducing)
                    byCells["\(code) \(fieldName)", default: [:]][digits.count, default: []].formUnion(reproducing)
                }
                if !reproducing.isEmpty, allowed.isDisjoint(with: reproducing) {
                    misses.append("\(name) \(fieldName): reproduces at \(reproducing), row allows \(allowed.sorted())")
                }
            }
        }
        print("PU.74 conventions vs corpus: \(windows) windows, \(misses.count) misses")
        // Equality, not only membership, where the corpus is large enough to
        // bound a currency (three or more stills - the same currencies the
        // cell-count audit covers): a read placement the corpus never shows
        // is a widening that would admit a tenfold misread.
        for code in ["EUR", "RUB", "KZT", "GBP", "AUD", "BYN"] {
            let conventions = PumpDisplayConventions.forCurrency(CurrencyCode(rawValue: code))
            for (fieldName, read) in [("liters", conventions.volumeDecimals), ("unitPrice", conventions.priceDecimals),
                                      ("total", conventions.totalDecimals)] {
                let measured = derived["\(code) \(fieldName)"] ?? []
                if Set(read) != measured {
                    misses.append("\(code) \(fieldName): table reads \(read.sorted()), corpus shows \(measured.sorted())")
                }
                // Where the table ties placements to cell counts, it names
                // exactly the placements each count shows on the corpus.
                guard let field = PumpField(rawValue: fieldName),
                      let tied = conventions.placementsByCells[field] else { continue }
                for (count, shown) in byCells["\(code) \(fieldName)"] ?? [:] where Set(tied[count] ?? []) != shown {
                    misses.append("\(code) \(fieldName) \(count) cells: table reads \(tied[count] ?? []), corpus shows \(shown.sorted())")
                }
            }
        }
        #expect(windows > 500)
        #expect(misses.isEmpty, Comment(stringLiteral: misses.joined(separator: "\n")))
    }

    /// Every closing (liters, price, total) the law can build from a fixture's
    /// annotated strings under `conventions`, with the table's cell-count audit
    /// applied the way `PumpReadingLaw.resolve` applies it.
    private static func closes(_ texts: [PumpField: String],
                               conventions: PumpDisplayConventions) -> [PumpReadingLaw.Triple] {
        guard let l = texts[.liters], let p = texts[.unitPrice], let t = texts[.total] else { return [] }
        let windows = [(PumpField.liters, l), (.unitPrice, p), (.total, t)].map {
            PumpLocatedWindow(field: $0.0, cells: PumpReadingLawTests.cells(for: $0.1))
        }
        if windows.allSatisfy({ $0.cells.count <= PumpReadingLaw.maxCells }),
           windows.contains(where: { !conventions.admits($0.field, cells: $0.cells.count) }) {
            return []
        }
        func top(_ window: PumpLocatedWindow, _ decimals: [Int]) -> [PumpReadingLaw.Candidate] {
            PumpReadingLaw.candidates(window, decimals: decimals).filter { $0.substitutions == 0 && $0.value > 0 }
        }
        return PumpReadingLaw.closingTriples(
            liters: top(windows[0], conventions.volumeDecimals), prices: top(windows[1], conventions.priceDecimals),
            totals: top(windows[2], conventions.totalDecimals),
            truncated: top(windows[2], conventions.truncatedTotalDecimals))
    }

    private static func isTrue(_ triple: PumpReadingLaw.Triple, _ want: ExpectedRow) -> Bool {
        guard let liters = want.liters, let price = want.unitPrice, let total = want.total else { return false }
        return abs(triple.liters - liters) < CorpusScorer.tolerance
            && abs(triple.price - price) < CorpusScorer.tolerance
            && abs(triple.total - total) < (triple.totalDerived ? 0.1 : CorpusScorer.tolerance)
    }

    /// The reviewed three-window fixtures with all three values asserted and none
    /// disputed by the CSV, as field -> annotated text.
    private static func sweepFixtures() throws -> [(name: String, texts: [PumpField: String], want: ExpectedRow)] {
        let expected = try CorpusScorer.loadExpected(
            PumpReaderTestSupport.pumpFixturesRoot.appendingPathComponent("expected.csv"))
        let data = try Data(contentsOf: PumpReaderTestSupport.windowsURL)
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        var out: [(name: String, texts: [PumpField: String], want: ExpectedRow)] = []
        for (name, value) in root.sorted(by: { $0.key < $1.key }) {
            guard name != "_about", let ann = value as? [String: Any], ann["csvDisagrees"] == nil,
                  let want = expected[name], want.liters != nil, want.unitPrice != nil, want.total != nil
            else { continue }
            var texts: [PumpField: String] = [:]
            for raw in ann["windows"] as? [[String: Any]] ?? [] {
                guard let fieldName = raw["field"] as? String, let field = PumpField(rawValue: fieldName),
                      [.liters, .unitPrice, .total].contains(field), texts[field] == nil,
                      raw["legibility"] as? String != "partial",
                      let text = raw["text"] as? String, !text.isEmpty else { continue }
                texts[field] = text
            }
            if texts.count == 3 { out.append((name, texts, want)) }
        }
        return out
    }

    /// Wrong refusals: a fixture whose true triple closes when every placement
    /// is allowed must still close under its currency's measured row.
    @Test("the measured table refuses no true close the permissive placements find", .pumpFixturesPresent)
    func tableRefusesNoTrueClose() throws {
        let permissive = PumpDisplayConventions(volumeDecimals: [0, 1, 2, 3], priceDecimals: [0, 1, 2, 3],
                                                totalDecimals: [0, 1, 2, 3], truncatedTotalDecimals: [1])
        let fixtures = try Self.sweepFixtures()
        var trueCloses = 0
        var refused: [String] = []
        for fixture in fixtures where Self.closes(fixture.texts, conventions: permissive)
            .contains(where: { Self.isTrue($0, fixture.want) }) {
            trueCloses += 1
            let conventions = PumpDisplayConventions.forCurrency(fixture.want.currency)
            if !Self.closes(fixture.texts, conventions: conventions).contains(where: { Self.isTrue($0, fixture.want) }) {
                refused.append(fixture.name)
            }
        }
        print("PU.74 close sweep: \(fixtures.count) fixtures, \(trueCloses) true closes, "
              + "\(refused.count) refused by the table")
        #expect(trueCloses > 200)
        #expect(refused.isEmpty, "true closes the table refuses: \(refused)")
    }

    /// The fixtures where every-placement arithmetic closes a tenfold-shrunk or
    /// -grown triple beside the true one; the measured row leaves only the true one.
    /// Not listed: pump-190 (KZT, a disputed one-decimal total that still closes a
    /// tenfold-grown price beside the true one, so the law abstains on those two
    /// fields) and pump-310 (a partial total annotation).
    @Test("the measured table leaves one close on the tenfold-ambiguous fixtures", .pumpFixturesPresent)
    func tableDisambiguatesTenfoldCloses() throws {
        let named = ["pump-137", "pump-145", "pump-173", "pump-180", "pump-185", "pump-217",
                     "pump-308", "pump-309", "pump-311", "pump-312", "pump-314", "pump-316"]
        let fixtures = try Self.sweepFixtures()
        var failures: [String] = []
        for prefix in named {
            guard let fixture = fixtures.first(where: { $0.name.hasPrefix(prefix + "-") }) else {
                failures.append("\(prefix): not in the sweep"); continue
            }
            let conventions = PumpDisplayConventions.forCurrency(fixture.want.currency)
            let found = Self.closes(fixture.texts, conventions: conventions)
            let distinct = Set(found.map { "\($0.liters)|\($0.price)|\($0.total)" })
            if distinct.count != 1 || !found.contains(where: { Self.isTrue($0, fixture.want) }) {
                failures.append("\(fixture.name): \(distinct.sorted())")
            }
        }
        #expect(failures.isEmpty, Comment(stringLiteral: failures.joined(separator: "\n")))
    }
}

import Foundation
import Testing
@testable import TankbookCore

/// How much of the pump law's reading the currency decides (PU.99). The glyph
/// read is currency-free; the currency enters the law through its display
/// conventions (`PumpDisplayConventions.forCurrency`) and its price band. This
/// resolves every reviewed still's annotated strings - the PU.21 oracle, no
/// model - under every currency the conventions table measures, and reports
/// per still whether the committing currencies agree.
///
/// Opt-in (`PUMP_CURRENCY_SWEEP=1`): a measurement for a decision, not a gate.
@Suite("Pump currency invariance", .pumpFixturesPresent,
       .enabled(if: ProcessInfo.processInfo.environment["PUMP_CURRENCY_SWEEP"] == "1", "PUMP_CURRENCY_SWEEP=1"))
struct PumpCurrencyInvarianceTests {
    /// The currencies `PumpDisplayConventions` has a measured row for.
    private static let measured = ["EUR", "RUB", "KZT", "GBP", "AUD", "BYN", "KGS", "BGN", "BRL", "ISK",
                                   "NOK", "PHP", "PLN", "SEK", "TMT"].compactMap { CurrencyCode(rawValue: $0) }
    private static let fieldNames = ["liters", "unitPrice", "total"]

    /// One currency's committed fields, in `fieldNames` order, and which of
    /// them the law derived rather than read.
    private struct Values: Equatable {
        var fields: [Decimal?] = [nil, nil, nil]
        var derived: Set<Int> = []
        var isEmpty: Bool { fields.allSatisfy { $0 == nil } }
    }

    private struct Tally {
        var committed = 0
        var correct = 0
    }

    @Test("the law under every measured currency, per still")
    func sweep() throws {
        let expected = try CorpusScorer.loadExpected(
            PumpReaderTestSupport.windowsURL.deletingLastPathComponent().appendingPathComponent("expected.csv"))
        let root = try JSONSerialization.jsonObject(
            with: Data(contentsOf: PumpReaderTestSupport.windowsURL)) as? [String: Any] ?? [:]
        let pack = try FuelPriceBandStore.bundledPack()

        var counts: [String: Int] = [:]
        var own = Tally()
        var agreed = Tally()
        var asserted = 0
        var stills = 0
        for (name, value) in root.sorted(by: { $0.key < $1.key }) {
            guard name != "_about", let ann = value as? [String: Any], let want = expected[name],
                  let ownCurrency = want.currency else { continue }
            let windows = Self.windows(ann)
            guard !windows.isEmpty else { continue }
            stills += 1
            var byCurrency: [String: Values] = [:]
            for currency in Self.measured {
                let values = Self.read(windows, currency: currency, pack: pack)
                if !values.isEmpty { byCurrency[currency.rawValue] = values }
            }
            let ownValues = byCurrency[ownCurrency.rawValue] ?? Values()
            let rule = Self.agreement(byCurrency)
            let category = Self.category(byCurrency, own: ownCurrency.rawValue)
            counts[category, default: 0] += 1

            let derived = byCurrency.values.reduce(into: ownValues.derived) { $0.formUnion($1.derived) }
            let truths = [want.liters, want.unitPrice, want.total]
            asserted += truths.compactMap { $0 }.count
            Self.score(ownValues, truths: truths, derived: derived, into: &own)
            let ruleWrong = Self.score(rule, truths: truths, derived: derived, into: &agreed)
            if category == "conflicting" || category == "other-currency-only" || !ruleWrong.isEmpty {
                print("PU99 \(category) \(name.prefix(8)) own \(ownCurrency.rawValue)"
                    + (ruleWrong.isEmpty ? "" : " RULE-WRONG \(ruleWrong)") + ": " + Self.describe(byCurrency))
            }
        }
        print("PU99 stills \(stills): " + counts.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }
            .joined(separator: ", "))
        print("PU99 own currency: committed \(own.committed), correct \(own.correct) of \(asserted) asserted cells")
        print("PU99 agreement rule: committed \(agreed.committed), correct \(agreed.correct) of \(asserted)")
        #expect(stills > 0)
    }

    /// The annotation's readable windows, as the PU.21 oracle builds them.
    private static func windows(_ ann: [String: Any]) -> [PumpLocatedWindow] {
        (ann["windows"] as? [[String: Any]] ?? []).compactMap { raw in
            guard let field = (raw["field"] as? String).flatMap(PumpField.init(rawValue:)),
                  let text = raw["text"] as? String, !text.isEmpty,
                  raw["legibility"] as? String != "partial" else { return nil }
            return PumpLocatedWindow(field: field, cells: PumpReadingLawTests.cells(for: text))
        }
    }

    private static func read(_ windows: [PumpLocatedWindow], currency: CurrencyCode,
                             pack: FuelPriceBandPack) -> Values {
        let reading = PumpReadingLaw.resolve(windows: windows, currency: currency,
                                             priceBand: pack.currencyBand(currency: currency))
        let fields = [reading.liters, reading.unitPrice, reading.total]
        var values = Values(fields: fields.map(\.value))
        for (index, field) in fields.enumerated() {
            if case .derived? = field.provenance { values.derived.insert(index) }
        }
        return values
    }

    /// A field commits when at least one currency commits it and every
    /// committing currency gives the same value.
    private static func agreement(_ byCurrency: [String: Values]) -> Values {
        Values(fields: (0..<3).map { index in
            let seen = Set(byCurrency.values.compactMap { $0.fields[index] })
            return seen.count == 1 ? seen.first : nil
        })
    }

    private static func category(_ byCurrency: [String: Values], own: String) -> String {
        if byCurrency.isEmpty { return "none" }
        let agreeing = (0..<3).allSatisfy { index in
            Set(byCurrency.values.compactMap { $0.fields[index] }).count <= 1
        }
        if !agreeing { return "conflicting" }
        if byCurrency[own] == nil { return "other-currency-only" }
        return byCurrency.count == 1 ? "own-currency-only" : "invariant"
    }

    /// Scores one set of committed fields against the truth; returns the
    /// names of the fields it got wrong.
    @discardableResult
    private static func score(_ values: Values, truths: [Double?], derived: Set<Int>,
                              into tally: inout Tally) -> [String] {
        var wrong: [String] = []
        for (index, truth) in truths.enumerated() {
            guard let truth, let value = values.fields[index] else { continue }
            tally.committed += 1
            if close(value, truth, derived.contains(index) ? 0.1 : CorpusScorer.tolerance) {
                tally.correct += 1
            } else {
                wrong.append(fieldNames[index])
            }
        }
        return wrong
    }

    private static func close(_ value: Decimal, _ truth: Double, _ slack: Double) -> Bool {
        abs(NSDecimalNumber(decimal: value).doubleValue - truth) < slack
    }

    private static func describe(_ byCurrency: [String: Values]) -> String {
        byCurrency.sorted { $0.key < $1.key }.map { code, values in
            code + "=" + values.fields.map { $0.map { "\($0)" } ?? "-" }.joined(separator: "/")
        }.joined(separator: " ")
    }
}

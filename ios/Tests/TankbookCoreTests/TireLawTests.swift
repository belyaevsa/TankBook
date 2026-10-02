import Foundation
import Testing
@testable import TankbookCore

@Suite("Tire law table")
struct TireLawTests {
    private let calendar = Calendar(identifier: .gregorian)

    @Test("a verified dated rule applies inside and within thirty days before its window")
    func datedWindow() {
        let table = table(kind: .dated)
        expectRequired(table.law(country: "EE", on: day(2026, 11, 1), calendar: calendar),
                       from: day(2026, 12, 1), to: day(2027, 3, 1))
        expectRequired(table.law(country: "EE", on: day(2027, 2, 20), calendar: calendar),
                       from: day(2026, 12, 1), to: day(2027, 3, 1))
        #expect(table.law(country: "EE", on: day(2027, 3, 2), calendar: calendar) == .noDatedRule)
        #expect(table.law(country: "EE", on: day(2026, 10, 31), calendar: calendar) == .noDatedRule)
    }

    @Test("a December to March window works on both sides of New Year")
    func newYear() {
        let table = table(kind: .dated)
        for date in [day(2026, 12, 31), day(2027, 1, 1)] {
            expectRequired(table.law(country: "EE", on: date, calendar: calendar),
                           from: day(2026, 12, 1), to: day(2027, 3, 1))
        }
    }

    @Test("a conditional rule never claims a fixed requirement")
    func conditional() {
        let verdict = table(kind: .conditional)
            .law(country: "EE", on: day(2027, 1, 1), calendar: calendar)
        #expect(verdict == .conditional(from: day(2026, 12, 1), to: day(2027, 3, 1)))
    }

    @Test("review due and withdrawn dated rules remain unknown")
    func unverified() {
        for status in [TireLaw.Status.reviewDue, .withdrawn] {
            let verdict = table(kind: .dated, status: status)
                .law(country: "EE", on: day(2026, 12, 1), calendar: calendar)
            #expect(verdict == .unknown)
        }
    }

    @Test("an unknown country remains unknown")
    func unknownCountry() {
        #expect(table(kind: .dated).law(country: "ZZ", on: day(2026, 12, 1),
                                         calendar: calendar) == .unknown)
    }

    @Test("unknown kind and status rows are skipped without failing the pack")
    func unknownRawValues() throws {
        let data = Data("""
        {"version":1,"rows":[
          {"country":"XX","vehicleClass":"M1","kind":"futureKind",
           "from":"12-01","to":"03-01","criteria":"test",
           "seasonGate":{"autumnFrom":"09-01","autumnTo":"12-15",
                         "springFrom":"03-01","springTo":"05-15"},
           "sourceURL":"https://example.org/law","checked":"2026-10-02",
           "status":"verified","note":"test","futureKey":42},
          {"country":"YY","vehicleClass":"M1","kind":"dated",
           "from":"12-01","to":"03-01","criteria":"test",
           "seasonGate":{"autumnFrom":"09-01","autumnTo":"12-15",
                         "springFrom":"03-01","springTo":"05-15"},
           "sourceURL":"https://example.org/law","checked":"2026-10-02",
           "status":"futureStatus","note":"test"}
        ]}
        """.utf8)
        let decoded = try TireLawTable.decode(data: data)
        #expect(decoded.rows.isEmpty)
        #expect(decoded.law(country: "XX", on: day(2026, 12, 1), calendar: calendar) == .unknown)
    }

    @Test("the bundled table decodes with a source and checked date on every row")
    func bundled() throws {
        let table = try TireLawTable.bundled()
        #expect(table.version == 1)
        #expect(table.rows.count == 12)
        for row in table.rows {
            #expect(row.sourceURL.scheme == "https")
            #expect(ISO8601DateFormatter().date(from: "\(row.checked)T00:00:00Z") != nil)
        }
        #expect(table.seasonGate(country: "EE") != nil)
    }

    @Test("a December through February rule includes leap day")
    func leapDay() throws {
        let table = try TireLawTable.bundled()
        expectRequired(table.law(country: "RU", on: day(2028, 2, 29), calendar: calendar),
                       from: day(2027, 12, 1), to: day(2028, 2, 29))
        #expect(table.law(country: "RU", on: day(2028, 3, 1), calendar: calendar) == .noDatedRule)
    }

    @Test("a rule ending on 29 February ends on the 28th in a common year")
    func commonYearEnd() throws {
        let table = try TireLawTable.bundled()
        expectRequired(table.law(country: "RU", on: day(2027, 2, 28), calendar: calendar),
                       from: day(2026, 12, 1), to: day(2027, 2, 28))
        #expect(table.law(country: "RU", on: day(2027, 3, 1), calendar: calendar) == .noDatedRule)
    }

    private func table(kind: TireLaw.Kind, status: TireLaw.Status = .verified) -> TireLawTable {
        let row = TireLaw(country: "EE", vehicleClass: "M1", kind: kind,
                          from: "12-01", to: "03-01", criteria: "test",
                          seasonGate: SeasonGate(autumnFrom: "09-01", autumnTo: "12-15",
                                                 springFrom: "03-01", springTo: "05-15"),
                          sourceURL: URL(string: "https://example.org/law")!,
                          checked: "2026-10-02", status: status, note: "test")
        return TireLawTable(version: 1, rows: [row])
    }

    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func expectRequired(_ verdict: TireLawVerdict, from: Date, to: Date) {
        guard case let .required(actualFrom, actualTo, source) = verdict else {
            Issue.record("Expected a verified dated requirement")
            return
        }
        #expect(actualFrom == from)
        #expect(actualTo == to)
        #expect(source.absoluteString == "https://example.org/law" || source.host == "government.ru")
    }
}

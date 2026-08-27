import Foundation
import Testing
@testable import TankbookCore

// MARK: - P6.1a: the anomaly engine (docs/JOURNEYS.md J9, docs/SCHEMA.md ->
// Derived: consumption -> ANOMALY). The detector's job is to stay quiet:
// the winter test below is the headline test, the one the journey exists to
// prevent. Every assertion here treats silence as a first-class outcome.

// MARK: - Fixtures

private enum UTC {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    static func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }
}

/// A derived segment directly (the anomaly engine takes segments, so the
/// fixture is a schedule of close dates, km and per100 - not raw fills).
private func segment(closes: Date, km: Double = 400, per100: Double) -> Segment {
    Segment(closes: closes, km: km, litres: per100 * km / 100,
            openingFillID: UUID.v7(), closingFillID: UUID.v7())
}

/// Segments at a steady cadence, all at the same per100.
private func steadySegments(from start: Date, to end: Date, every days: Int,
                            per100: Double) -> [Segment] {
    var result: [Segment] = []
    var date = start
    while date <= end {
        result.append(segment(closes: date, per100: per100))
        date = date.addingTimeInterval(Double(days) * 86_400)
    }
    return result
}

/// Segments that rise to `winterPer100` every December-February and return to
/// `normalPer100` every spring, across the given span - the pattern a naive
/// month-over-month rule would fire on every winter.
private func seasonalSegments(from start: Date, to end: Date, every days: Int,
                              winterPer100: Double = 12, normalPer100: Double = 8) -> [Segment] {
    var result: [Segment] = []
    var date = start
    while date <= end {
        let month = UTC.calendar.component(.month, from: date)
        let isWinter = month == 12 || month == 1 || month == 2
        result.append(segment(closes: date, per100: isWinter ? winterPer100 : normalPer100))
        date = date.addingTimeInterval(Double(days) * 86_400)
    }
    return result
}

/// A baseline year of steady 8 L/100km, then a sustained rise to 10 L/100km
/// from January 2026 - the drift every firing test uses.
private func driftSegments() -> [Segment] {
    var result: [Segment] = []
    result += steadySegments(from: UTC.day(2025, 1, 1), to: UTC.day(2025, 12, 18),
                             every: 14, per100: 8)
    result += steadySegments(from: UTC.day(2026, 1, 1), to: UTC.day(2026, 7, 1),
                             every: 14, per100: 10)
    return result
}

/// The distance-weighted value over the trailing `days` ending at `asOf` - the
/// same Σ litres / Σ km x 100 the engine uses, recomputed here only to prove
/// the fixture really swings with the seasons (the non-vacuity control).
private func rollingValue(_ segments: [Segment], asOf: Date, days: Int = 90) -> Double {
    let start = asOf.addingTimeInterval(-Double(days) * 86_400)
    let win = segments.filter { $0.closes > start && $0.closes <= asOf }
    let litres = win.reduce(0) { $0 + $1.litres }
    let km = win.reduce(0) { $0 + $1.km }
    return litres / km * 100
}

// MARK: - Test 1: winter never false-fires (the headline test)

@Test func winterNeverFalseFiresAcrossMoreThanTwoYears() {
    // Three winters of rising consumption: 12 L/100km every December-February,
    // back to 8 L/100km every spring. A +50% seasonal swing - a month-over-month
    // comparison would fire at the winter onset every year.
    let segments = seasonalSegments(from: UTC.day(2024, 1, 1), to: UTC.day(2027, 4, 1),
                                    every: 14)

    let winterDays: [Date] = [
        UTC.day(2024, 12, 15), UTC.day(2025, 1, 15), UTC.day(2025, 2, 15),
        UTC.day(2025, 12, 15), UTC.day(2026, 1, 15), UTC.day(2026, 2, 15),
        UTC.day(2026, 12, 15), UTC.day(2027, 1, 15), UTC.day(2027, 2, 15)
    ]
    for asOf in winterDays {
        let anomaly = AnomalyEngine.detect(segments: segments, asOf: asOf, calendar: UTC.calendar)
        #expect(anomaly == nil, "winter \(asOf) must stay silent")
    }

    // Non-vacuity control: the seasonal swing is real, so only the
    // seasonally-aligned baseline - not a high threshold or a flat fixture -
    // is what keeps those winters quiet. The first winters (2024/25) are silent
    // because there is no prior year to compare against yet; the later ones
    // because this winter matches last winter.
    let febRolling = rollingValue(segments, asOf: UTC.day(2026, 2, 15))
    let junRolling = rollingValue(segments, asOf: UTC.day(2026, 6, 15))
    #expect(febRolling - junRolling > 2.0,
            "the fixture really swings with the seasons: \(febRolling) vs \(junRolling)")
}

// MARK: - Test 2: a real sustained drift fires, with the correct magnitude

@Test func sustainedDriftFiresWithCorrectMagnitude() {
    let segments = driftSegments()
    let asOf = UTC.day(2026, 6, 15)

    let anomaly = AnomalyEngine.detect(segments: segments, asOf: asOf, calendar: UTC.calendar)
    #expect(anomaly != nil, "a sustained +25% drift must fire")
    guard let anomaly else { return }

    #expect(anomaly.metric == .consumption)
    #expect(abs(anomaly.rollingValue - 10.0) < 0.001, "rolling value is the recent 90 days")
    #expect(abs(anomaly.baselineValue - 8.0) < 0.001, "baseline is the same window one year earlier")
    #expect(abs(anomaly.magnitude - 0.25) < 0.001, "magnitude is (10 - 8) / 8 = 0.25")
    #expect(anomaly.cause == AnomalyCause(metric: .consumption, evaluatedYear: 2026, evaluatedMonth: 6))
}

// MARK: - Tests 3 & 4: dismissal suppresses its own cause, never all causes

@Test func dismissalSuppressesSameCauseAcrossRecompute() {
    let segments = driftSegments()
    let asOf = UTC.day(2026, 6, 15)
    let cause = AnomalyCause(metric: .consumption, evaluatedOn: asOf, calendar: UTC.calendar)

    // Without a dismissal the drift fires.
    #expect(AnomalyEngine.detect(segments: segments, asOf: asOf, calendar: UTC.calendar) != nil)

    let dismissal = AnomalyDismissal(cause: cause, reason: "winter tires", dismissedAt: asOf)
    // A recompute with the dismissal present stays silent...
    #expect(AnomalyEngine.detect(segments: segments, asOf: asOf, dismissals: [dismissal],
                                 calendar: UTC.calendar) == nil)
    // ...a second recompute (the caller re-runs on every entry change) too...
    #expect(AnomalyEngine.detect(segments: segments, asOf: asOf, dismissals: [dismissal],
                                 calendar: UTC.calendar) == nil)
    // ...and a recompute a few days later, still inside the same evaluation
    // month: the cause is the same, so the suppression holds.
    let later = UTC.day(2026, 6, 20)
    #expect(AnomalyEngine.detect(segments: segments, asOf: later, dismissals: [dismissal],
                                 calendar: UTC.calendar) == nil)
}

@Test func differentCauseStillFiresAfterDismissal() {
    let segments = driftSegments()
    let juneCause = AnomalyCause(metric: .consumption, evaluatedOn: UTC.day(2026, 6, 15),
                                 calendar: UTC.calendar)
    let dismissal = AnomalyDismissal(cause: juneCause, reason: "winter tires",
                                     dismissedAt: UTC.day(2026, 6, 15))

    // The drift persists into July; July is a different evaluation month, so a
    // new cause. Dismissing June must not mute it - "dismiss" is per-cause,
    // never "mute everything".
    let nextMonth = AnomalyEngine.detect(segments: segments, asOf: UTC.day(2026, 7, 15),
                                         dismissals: [dismissal], calendar: UTC.calendar)
    #expect(nextMonth != nil, "dismissing June must not mute July")
    guard let nextMonth else { return }
    #expect(nextMonth.cause == AnomalyCause(metric: .consumption, evaluatedYear: 2026,
                                            evaluatedMonth: 7))
    #expect(abs(nextMonth.magnitude - 0.25) < 0.001)
}

// MARK: - Test 5: insufficient history yields nothing

@Test func insufficientHistoryYieldsNothing() {
    // A new user with a few months of data: a rolling value may exist, but
    // there is no seasonally-aligned baseline to compare against - silence.
    let newUser = steadySegments(from: UTC.day(2026, 3, 1), to: UTC.day(2026, 6, 1),
                                 every: 14, per100: 8)
    #expect(AnomalyEngine.detect(segments: newUser, asOf: UTC.day(2026, 6, 15),
                                 calendar: UTC.calendar) == nil)

    // Below the segment floor inside the rolling window.
    let sparse = steadySegments(from: UTC.day(2025, 1, 1), to: UTC.day(2026, 6, 1),
                                every: 100, per100: 8)
    #expect(AnomalyEngine.detect(segments: sparse, asOf: UTC.day(2026, 6, 15),
                                 calendar: UTC.calendar) == nil)

    // No segments at all.
    #expect(AnomalyEngine.detect(segments: [], asOf: UTC.day(2026, 6, 15),
                                 calendar: UTC.calendar) == nil)
}

// MARK: - Test 6: the D1-D4 golden vectors are untouched and stay quiet

private struct GoldenFill: Decodable {
    let date: Date
    let odometer: Int
    let litres: Double
    let isFull: Bool
}

private struct GoldenHeadline: Decodable {
    let value: Double
}

private struct GoldenDriver: Decodable {
    let id: String
    let fills: [GoldenFill]
    let expectedHeadline: GoldenHeadline
}

private struct GoldenFixture: Decodable {
    let asOf: Date
    let model: GoldenModel
    let drivers: [GoldenDriver]
}

private struct GoldenModel: Decodable {
    let windowDays: Int
    let floorSegments: Int
}

private func loadGoldenFixture() throws -> GoldenFixture {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "UTC")
    formatter.dateFormat = "yyyy-MM-dd"
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .formatted(formatter)

    var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    for _ in 0..<6 {
        let candidate = directory.appendingPathComponent("docs/fixtures/consumption-golden.json")
        if FileManager.default.fileExists(atPath: candidate.path) {
            return try decoder.decode(GoldenFixture.self, from: Data(contentsOf: candidate))
        }
        directory = directory.deletingLastPathComponent()
    }
    throw CocoaError(.fileNoSuchFile)
}

private func makeGoldenFill(_ fill: GoldenFill, vehicleID: UUID) -> FillUp {
    FillUp(id: UUID.v7(), createdAt: fill.date, updatedAt: fill.date, deletedAt: nil,
           vehicleId: vehicleID, date: fill.date, odometer: fill.odometer, money: nil,
           note: nil, attachments: [], provenance: .manual, conflict: .none,
           purchaseGroupId: nil, volumeL: fill.litres, unitPrice: nil,
           fuelKind: .petrol95, fuelGrade: nil, isFull: fill.isFull,
           tankLevelAfterPct: nil, stationId: nil, crossCheck: .notApplicable,
           extraction: nil)
}

private func round1(_ value: Double) -> Double {
    (value * 10).rounded() / 10
}

@Test func goldenDriversD1ThroughD4StaySilentAndUnchanged() throws {
    let fixture = try loadGoldenFixture()
    let vehicleID = UUID.v7()

    for driver in fixture.drivers {
        let fills = driver.fills.map { makeGoldenFill($0, vehicleID: vehicleID) }
        let segments = ConsumptionEngine.segments(for: fills)

        // The consumption numbers must not move (docs/SCHEMA.md -> the four
        // drivers are the golden vectors). The full vector assertion lives in
        // ConsumptionGoldenTests; this re-pins the headline, the number the
        // anomaly engine must never disturb.
        let headline = ConsumptionEngine.headline(segments: segments, asOf: fixture.asOf,
                                                  windowDays: fixture.model.windowDays,
                                                  floor: fixture.model.floorSegments)
        #expect(round1(headline?.value ?? -1) == driver.expectedHeadline.value,
                "\(driver.id) headline unchanged")

        // The golden corpus stays quiet: stable histories (D1-D3 have no
        // 12-month baseline at the golden date; D4 is below the floor) - the
        // anomaly engine adds no noise to the reference corpus.
        let anomaly = AnomalyEngine.detect(segments: segments, asOf: fixture.asOf,
                                           calendar: UTC.calendar)
        #expect(anomaly == nil, "\(driver.id) - the golden corpus must stay quiet")
    }
}

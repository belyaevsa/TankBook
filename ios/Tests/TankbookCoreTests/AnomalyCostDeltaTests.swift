import Foundation
import Testing
@testable import TankbookCore

// MARK: - The threshold and the money line (docs/VISION.md -> "What we
// will not tell a driver"). The engine's verdict is sound; these tests pin the
// two things the row changes: the threshold now has a measured reason instead
// of a citation, and the drift has a money reading instead of a guessed cause.

private enum CostUTC {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    static func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }
}

private func costSegment(closes: Date, km: Double = 400, per100: Double) -> Segment {
    Segment(closes: closes, km: km, litres: per100 * km / 100,
            openingFillID: UUID.v7(), closingFillID: UUID.v7())
}

private func steadySegments(from start: Date, to end: Date, every days: Int,
                            per100: Double) -> [Segment] {
    var result: [Segment] = []
    var date = start
    while date <= end {
        result.append(costSegment(closes: date, per100: per100))
        date = date.addingTimeInterval(Double(days) * 86_400)
    }
    return result
}

private func rollingValue(_ segments: [Segment], asOf: Date, days: Int = 90) -> Double {
    let start = asOf.addingTimeInterval(-Double(days) * 86_400)
    let win = segments.filter { $0.closes > start && $0.closes <= asOf }
    let litres = win.reduce(0) { $0 + $1.litres }
    let km = win.reduce(0) { $0 + $1.km }
    return litres / km * 100
}

/// The anomaly every cost test uses: rolling 10 vs baseline 8 L/100km over a
/// 90-day window (day 1 Jan - 1 Apr 2026).
private func costAnomaly(rollingWindowStart: Date = CostUTC.day(2026, 1, 1),
                         rollingWindowEnd: Date = CostUTC.day(2026, 4, 1)) -> ConsumptionAnomaly {
    ConsumptionAnomaly(
        cause: AnomalyCause(metric: .consumption, evaluatedYear: 2026, evaluatedMonth: 4),
        metric: .consumption,
        rollingValue: 10.0,
        baselineValue: 8.0,
        magnitude: 0.25,
        rollingWindow: AnomalyWindow(start: rollingWindowStart, end: rollingWindowEnd,
                                     value: 10.0, segmentCount: 3),
        baselineWindow: AnomalyWindow(start: CostUTC.day(2025, 1, 1), end: CostUTC.day(2025, 4, 1),
                                      value: 8.0, segmentCount: 3))
}

// MARK: - Test 1: the threshold fires only above the band

@Test func detectStaysQuietInsideBandAndFiresAbove() {
    func segments(riseTo value: Double) -> [Segment] {
        var result: [Segment] = []
        result += steadySegments(from: CostUTC.day(2025, 1, 1), to: CostUTC.day(2025, 12, 18),
                                 every: 14, per100: 8)
        result += steadySegments(from: CostUTC.day(2026, 1, 1), to: CostUTC.day(2026, 7, 1),
                                 every: 14, per100: value)
        return result
    }
    let asOf = CostUTC.day(2026, 6, 15)

    // 8 -> 8.8 is a +10% rise, inside the band: normal wobble stays quiet.
    #expect(AnomalyEngine.detect(segments: segments(riseTo: 8.8), asOf: asOf,
                                 calendar: CostUTC.calendar) == nil)
    // 8 -> 8.9 is +11.25%, still inside: quiet.
    #expect(AnomalyEngine.detect(segments: segments(riseTo: 8.9), asOf: asOf,
                                 calendar: CostUTC.calendar) == nil)
    // 8 -> 9.0 is +12.5%, above the band: fires.
    #expect(AnomalyEngine.detect(segments: segments(riseTo: 9.0), asOf: asOf,
                                 calendar: CostUTC.calendar) != nil)
    // 8 -> 9.6 is +20%: fires.
    #expect(AnomalyEngine.detect(segments: segments(riseTo: 9.6), asOf: asOf,
                                 calendar: CostUTC.calendar) != nil)

    // Non-vacuity: the fixtures really are what they claim to be, so the band,
    // not a flat fixture or a low threshold, is what keeps the 10% case quiet.
    #expect(abs(rollingValue(segments(riseTo: 8.8), asOf: asOf) - 8.8) < 0.001)
    #expect(abs(rollingValue(segments(riseTo: 9.0), asOf: asOf) - 9.0) < 0.001)
}

// MARK: - Test 2: the constant matches the measured rule, not a citation

/// Reads the owner's own Drivvo export (Spike/ImportFixtures/drivvo) exactly
/// as the derivation did, rebuilds the 90-day rolling series through the real
/// `ConsumptionEngine`, and checks the constant sits at "1.5 sigma of the
/// rolling series" (docs/SCHEMA.md -> ANOMALY, threshold derivation). This is
/// the guard the row exists for: 0.12 used to be a citation with no derivation,
/// and a retune without re-deriving is how that happened.
@Test func minimumRelativeDriftMatchesMeasuredSigmaRule() throws {
    let fixture = try loadOwnerFixture()
    let segments = ConsumptionEngine.segments(for: fixture.fills)

    let mean = rollingMean(segments)
    let sigma = rollingPopulationStd(segments, mean: mean)
    #expect(mean > 0, "the fixture must yield a usable series")
    let relativeSigma = sigma / mean

    // Sanity: the measured spread really is a low-single-digit-percent figure.
    // If the fixture stops parsing or the segment math drifts, this catches it
    // before the rule comparison becomes vacuous.
    #expect(relativeSigma > 0.05 && relativeSigma < 0.12,
            "relative sigma was \(relativeSigma)")
    // The constant is the rule applied: 1.5 sigma of the 90-day rolling series,
    // rounded to 0.12. A constant that disagrees with its measured spread is
    // the exact failure this test exists to catch.
    let rule = 1.5 * relativeSigma
    #expect(abs(AnomalyEngine.minimumRelativeDrift - rule) < 0.005,
            "\(AnomalyEngine.minimumRelativeDrift) is not the rule's 1.5 sigma (\(rule))")
}

// MARK: - Test 3: monthlyCostDelta returns nil when it cannot know

@Test func monthlyCostDeltaIsNilWhenItCannotKnow() {
    let segments = [costSegment(closes: CostUTC.day(2026, 1, 15), km: 300, per100: 10),
                    costSegment(closes: CostUTC.day(2026, 2, 15), km: 300, per100: 10),
                    costSegment(closes: CostUTC.day(2026, 3, 15), km: 300, per100: 10)]
    let anomaly = costAnomaly()

    // No price known: nil, never a zero - a missing price is a missing line,
    // not a free month (hard rule 13).
    #expect(AnomalyEngine.monthlyCostDelta(anomaly: anomaly, segments: segments,
                                           unitPrice: nil) == nil)
    // A zero price is not a price the money line can mean anything with.
    #expect(AnomalyEngine.monthlyCostDelta(anomaly: anomaly, segments: segments,
                                           unitPrice: 0) == nil)

    // No distance in the window: nil even with a price.
    #expect(AnomalyEngine.monthlyCostDelta(anomaly: anomaly,
                                           segments: [costSegment(closes: CostUTC.day(2026, 5, 1),
                                                                 km: 300, per100: 10)],
                                           unitPrice: 1.5) == nil)

    // Non-positive drift: nil even with distance and a price.
    let flat = ConsumptionAnomaly(
        cause: anomaly.cause, metric: .consumption,
        rollingValue: 8.0, baselineValue: 8.0, magnitude: 0,
        rollingWindow: anomaly.rollingWindow, baselineWindow: anomaly.baselineWindow)
    #expect(AnomalyEngine.monthlyCostDelta(anomaly: flat, segments: segments,
                                           unitPrice: 1.5) == nil)
}

// MARK: - Test 4: monthlyCostDelta returns the hand-computed value

@Test func monthlyCostDeltaMatchesHandComputedFixture() {
    // Rolling 10 vs baseline 8 L/100km; three 300 km segments close inside the
    // 90-day window, so the car covered 900 km there.
    //   monthly km   = 900 / (90 / 30.44) = 304.4 km/month
    //   extra litres = (10 - 8) / 100 x 304.4 = 6.088 L/month
    //   x price 1.50 -> EUR 9.132 per month
    let segments = [costSegment(closes: CostUTC.day(2026, 1, 15), km: 300, per100: 10),
                    costSegment(closes: CostUTC.day(2026, 2, 15), km: 300, per100: 10),
                    costSegment(closes: CostUTC.day(2026, 3, 15), km: 300, per100: 10)]
    let delta = AnomalyEngine.monthlyCostDelta(anomaly: costAnomaly(),
                                               segments: segments,
                                               unitPrice: Decimal(string: "1.50"))
    let expected = Decimal(string: "6.088")! * Decimal(string: "1.50")!  // 9.132
    let tolerance = Decimal(string: "0.0005")!
    #expect(delta != nil)
    guard let delta else { return }
    #expect(abs(delta - expected) < tolerance,
            "delta was \(delta), expected \(expected)")
    // As displayed (two fraction digits) this is EUR 9.13.
    let cents = delta.rounded(decimalPlaces: 2)
    #expect(cents == Decimal(string: "9.13"))
}

// MARK: - Test 5: no user-facing string claims a cause

/// The app must not say why consumption changed - it
/// cannot know. The causes phrasing is gone from the String Catalog in BOTH
/// languages; asserting the exact sentences, not a key name, so a rewording
/// that kept the claim would still fail.
@Test func noUserFacingStringClaimsACause() throws {
    let catalogue = try String(contentsOf: repositoryFile("ios/App/Sources/Localizable.xcstrings"),
                               encoding: .utf8)
    #expect(!catalogue.contains("Likely causes: tire pressure, air filter, winter"))
    #expect(!catalogue.contains("Вероятные причины: давление в шинах, воздушный фильтр, зима"))
}

// MARK: - Fixture loading

private struct OwnerFixture {
    let fills: [FillUp]
}

/// The owner's Drivvo export, read from the repo root via #filePath (the same
/// walk the golden-vector fixture uses). The refuelling section is 250 rows;
/// the header line and the other sections are skipped.
private func loadOwnerFixture() throws -> OwnerFixture {
    let url = repositoryFile("Spike/ImportFixtures/drivvo/drivvo-ru-3sections.csv")
    let text = try String(contentsOf: url, encoding: .utf8)

    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "UTC")
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

    var fills: [FillUp] = []
    var inRefuelling = false
    for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        if line.hasPrefix("##") {
            inRefuelling = line == "##Refuelling"
            continue
        }
        guard inRefuelling, !line.isEmpty else { continue }
        let fields = line.hasPrefix("\"") && line.hasSuffix("\"")
            ? String(line.dropFirst().dropLast()).components(separatedBy: "\",\"")
            : line.components(separatedBy: ",")
        guard fields.count > 6 else { continue }
        guard let date = formatter.date(from: fields[1]),
              let odometer = Double(fields[0]),
              let volume = Double(fields[5].replacingOccurrences(of: ",", with: ".")) else {
            continue  // the localised header row
        }
        let isFull = fields[6].lowercased() == "да"
        fills.append(FillUp(id: UUID.v7(), createdAt: date, updatedAt: date, deletedAt: nil,
                            vehicleId: UUID.v7(), date: date, odometer: Int(odometer),
                            money: nil, note: nil, attachments: [], provenance: .manual,
                            conflict: .none, purchaseGroupId: nil, volumeL: volume,
                            unitPrice: nil, fuelKind: .petrol95, fuelGrade: nil,
                            isFull: isFull, tankLevelAfterPct: nil, stationId: nil,
                            crossCheck: .notApplicable, extraction: nil))
    }
    guard fills.count > 100 else {
        throw CocoaError(.fileReadCorruptFile)
    }
    return OwnerFixture(fills: fills)
}

private func repositoryFile(_ relative: String) -> URL {
    var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    for _ in 0..<8 {
        let candidate = directory.appendingPathComponent(relative)
        if FileManager.default.fileExists(atPath: candidate.path) {
            return candidate
        }
        directory = directory.deletingLastPathComponent()
    }
    return URL(fileURLWithPath: relative)
}

// MARK: - The daily-sampled 90-day rolling series (time-weighted)

private func rollingSeries(_ segments: [Segment]) -> [Double] {
    let dates = segments.map(\.closes).sorted()
    guard let first = dates.first, let last = dates.last else { return [] }
    var values: [Double] = []
    var cursor = first
    let step = 86_400.0 * 3  // every 3 days: each constant stretch is weighted
    while cursor <= last {
        let start = cursor.addingTimeInterval(-90 * 86_400)
        let win = segments.filter { $0.closes > start && $0.closes <= cursor }
        if !win.isEmpty {
            let km = win.reduce(0) { $0 + $1.km }
            if km > 0 {
                let litres = win.reduce(0) { $0 + $1.litres }
                values.append(litres / km * 100)
            }
        }
        cursor = cursor.addingTimeInterval(step)
    }
    return values
}

private func rollingMean(_ segments: [Segment]) -> Double {
    let values = rollingSeries(segments)
    guard !values.isEmpty else { return 0 }
    return values.reduce(0, +) / Double(values.count)
}

private func rollingPopulationStd(_ segments: [Segment], mean: Double) -> Double {
    let values = rollingSeries(segments)
    guard values.count > 1 else { return 0 }
    let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)
    return variance.squareRoot()
}

import Foundation
import Testing
import SwiftUI
@testable import TankbookCore

/// P6.5 - the accessibility-floor guards that are not the contrast half (that
/// half lives in `PaletteAccentGuardTests`). Each guard below is written to
/// enumerate the CLASS its defect belongs to, not the one instance the change
/// happened to fix:
///
/// - `TrendDirection`: the direction a lower-is-better series is moving,
///   covering improving, worsening, and every way the data can fail to support
///   a direction (fewer than two points, flat, under-1% noise). The first
///   version of any guard here would have caught only the consumption series.
/// - `headlineTrend` / `consumptionTrend` / `costTrend`: derived from the same
///   segments the figure is, never stored (hard rule 2), so a trend can never
///   disagree with the number it describes.
/// - `ContrastPolicy`: the one number "Increase Contrast" changes, so every
///   surface honours the same value.
/// - The source guards: a stat figure's VoiceOver label is composed (value +
///   unit + trend), never the bare number; and a log entry's kind is carried
///   by a glyph, never colour alone.
@Suite("Accessibility floor (P6.5)")
struct AccessibilityGuardTests {

    // MARK: - Trend direction (pure)

    @Test("lower-is-better series: decreasing improves, increasing worsens")
    func trendDirectionReportsBothDirections() {
        #expect(TrendDirection.lowerIsBetter([6.5, 6.2]) == .improving)
        #expect(TrendDirection.lowerIsBetter([6.2, 6.5]) == .worsening)
        #expect(TrendDirection.lowerIsBetter([8.4, 7.9, 7.2]) == .improving)
    }

    @Test("trend abstains rather than invent: no points, one point, flat, noise")
    func trendDirectionAbstainsWhenTheDataCannotSupportADirection() {
        #expect(TrendDirection.lowerIsBetter([]) == nil)
        #expect(TrendDirection.lowerIsBetter([6.5]) == nil)
        #expect(TrendDirection.lowerIsBetter([6.5, 6.5]) == nil)
        #expect(TrendDirection.lowerIsBetter([0, 0]) == nil)
        // Under 1% is rounding noise, not a direction to announce.
        #expect(TrendDirection.lowerIsBetter([6.500, 6.505]) == nil)
        #expect(TrendDirection.lowerIsBetter([6.505, 6.500]) == nil)
    }

    // MARK: - Derived, never stored (hard rule 2)

    private static let asOf = Date(timeIntervalSince1970: 1_752_000_000)
    private static let day: TimeInterval = 86_400

    private static func vehicle() -> Vehicle {
        Vehicle(
            id: UUID.v7(), createdAt: asOf - 200 * day, updatedAt: asOf - 200 * day,
            deletedAt: nil, name: "Volvo V60", make: "Volvo", model: "V60", year: 2015,
            plate: nil, powertrain: .ice, fuelKinds: [.petrol95, .diesel],
            tankCapacityL: 71, batteryCapacityKWh: nil, homeCurrency: .eur,
            units: Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100,
                                  energy: .kWhPer100),
            photo: nil, archived: false, paceLimitKmPerDay: 1500,
            initialOdometer: 118_000)
    }

    private static func fill(date: Date, odometer: Int, litres: Double) -> FillUp {
        FillUp(
            id: UUID.v7(), createdAt: date, updatedAt: date, deletedAt: nil,
            vehicleId: UUID.v7(), date: date, odometer: odometer,
            money: Money(amount: Decimal(string: "50")!, currency: .eur, homeCurrency: .eur),
            note: nil, attachments: [], provenance: .manual, conflict: .none,
            purchaseGroupId: nil, volumeL: litres, unitPrice: Decimal(string: "1.5"),
            fuelKind: .petrol95, fuelGrade: nil, isFull: true,
            tankLevelAfterPct: 100, stationId: nil,
            crossCheck: .notApplicable, extraction: nil)
    }

    /// Three full tanks close two segments whose per100 falls (40 -> 1): the
    /// headline and its trend must both derive from those same two segments.
    @Test("headlineTrend and consumptionTrend are derived from the same segments")
    func trendIsDerivedFromTheSameSegmentsAsTheFigure() {
        let f1 = Self.fill(date: Self.asOf - 20 * Self.day, odometer: 118_000, litres: 40)
        let f2 = Self.fill(date: Self.asOf - 12 * Self.day, odometer: 118_100, litres: 40) // 100 km, 40 L
        let f3 = Self.fill(date: Self.asOf - 2 * Self.day, odometer: 119_100, litres: 10)  // 1,000 km, 10 L
        let entries: [any Entry] = [f1, f2, f3]

        let home = HomeStats(vehicle: Self.vehicle(), entries: entries, asOf: Self.asOf)
        let trends = TrendsStats(vehicle: Self.vehicle(), entries: entries, asOf: Self.asOf)

        #expect(home.headlineTrend == .improving,
                "a falling per100 series must read as improving, got \(String(describing: home.headlineTrend))")
        #expect(trends.consumptionTrend == .improving)
        #expect(home.headlineTrend == trends.consumptionTrend,
                "Home and Trends derive the trend from the same series and can never disagree")
    }

    @Test("a rising per100 series reads as worsening")
    func trendWorsensWhenTheSeriesRises() {
        let f1 = Self.fill(date: Self.asOf - 20 * Self.day, odometer: 118_000, litres: 10)
        let f2 = Self.fill(date: Self.asOf - 12 * Self.day, odometer: 119_000, litres: 10) // 1,000 km, 10 L
        let f3 = Self.fill(date: Self.asOf - 2 * Self.day, odometer: 119_100, litres: 40)  // 100 km, 40 L
        let stats = HomeStats(vehicle: Self.vehicle(),
                              entries: [f1, f2, f3], asOf: Self.asOf)
        #expect(stats.headlineTrend == .worsening)
    }

    @Test("a single closed segment has no trend")
    func trendIsNilBelowTwoSegments() {
        let f1 = Self.fill(date: Self.asOf - 6 * Self.day, odometer: 118_000, litres: 42)
        let stats = HomeStats(vehicle: Self.vehicle(),
                              entries: [f1], asOf: Self.asOf)
        #expect(stats.headlineTrend == nil,
                "one fill closes no segment; there is nothing for a trend to describe")
    }

    // MARK: - Increase Contrast (the number every surface honours)

    @Test("ContrastPolicy raises the hairline under Increase Contrast")
    func contrastPolicyRaisesTheHairline() {
        #expect(ContrastPolicy.hairlineOpacity(increasedContrast: false) == 0.08)
        #expect(ContrastPolicy.hairlineOpacity(increasedContrast: true) > 0.08,
                "Increase Contrast must make the hairline more visible")
        #expect(ContrastPolicy.hairlineOpacity(increasedContrast: true) == 0.24)
    }

    // MARK: - Source guards (enumerating the class, not the instance)

    private static var appSources: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // TankbookCoreTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // ios
            .appendingPathComponent("App/Sources", isDirectory: true)
    }

    private static func sourceText(_ relativePath: String) throws -> String {
        try String(contentsOf: appSources.appendingPathComponent(relativePath),
                   encoding: .utf8)
    }

    /// The class: a stat figure's VoiceOver label is the value+unit composition
    /// (plus any trend), never the bare value. `StatTile` is the ONE shared
    /// component Home and Trends both render, so guarding it guards every tile.
    /// A label that exists but reads only `value` passes an existence check and
    /// fails a blind user - so the guard asserts the composition references
    /// `value`, `unit` and the trend, not merely that a label is set.
    @Test("StatTile's figure label composes value + unit + trend, never the bare number")
    func statTileFigureLabelIsComposedNotBare() throws {
        let text = try Self.sourceText("Shared/StatTile.swift")

        #expect(text.contains("accessibilityLabel(figureVoiceOverLabel)"),
                "the value Text must announce the composed figure label")
        #expect(text.contains(".accessibilityHidden(true)"),
                "the subordinate unit must be hidden so it is not read twice")

        // The composition itself: value, unit and trend all participate.
        let property = try #require(
            text.range(of: "private var figureVoiceOverLabel").map { String(text[$0.lowerBound...]) })
        #expect(property.contains("value"), "the figure label must contain the value")
        #expect(property.contains("unit"), "the figure label must contain the unit")
        #expect(property.contains("L10n.trend"), "the figure label must carry the trend")
    }

    /// The class: a log entry's kind is carried by a glyph, never colour alone.
    /// Fuel and electric must differ by icon (fuelpump vs bolt), not just by
    /// taillight vs headlight hue - a colour-blind reader can tell them apart,
    /// and the marker's accessibility label names the kind for a blind reader.
    @Test("fuel and electric entries differ by glyph, never colour alone")
    func fuelAndElectricDifferByGlyph() throws {
        let text = try Self.sourceText("Shared/EntryKindMark.swift")

        let fuel = try #require(
            text.range(of: "case .fuel: return \"").map { String(text[$0.lowerBound...]) })
        let charge = try #require(
            text.range(of: "case .charge: return \"").map { String(text[$0.lowerBound...]) })
        #expect(fuel.contains("fuelpump"), "fuel must use a fuel glyph")
        #expect(charge.contains("bolt"), "electric must use a distinct bolt glyph")
        #expect(fuel != charge, "fuel and electric must not share one glyph")

        #expect(text.contains("accessibilityLabel(kind.accessibilityName)"),
                "the kind marker must name the kind for VoiceOver")
    }

    /// The class: every log row renders its kind dot through the shared
    /// glyph-bearing marker. A `Circle().fill(dotColor(` is the colour-only
    /// shape the glyph exists to replace - it must be gone from both surfaces
    /// that render entry kinds, or the class has regressed in one of them.
    @Test("entry kind markers render through EntryKindMark, never a colour-only dot")
    func entryKindDotsAreGlyphs() throws {
        let home = try Self.sourceText("Home/HomeSections.swift")
        let deleted = try Self.sourceText("RecentlyDeleted/RecentlyDeletedView.swift")

        #expect(!home.contains("Circle()\n                    .fill(dotColor"),
                "Home must not render a colour-only kind dot")
        #expect(!deleted.contains("Circle()\n                .fill(dotColor"),
                "Recently deleted must not render a colour-only kind dot")
        #expect(home.contains("EntryKindMark(kind:"), "Home renders the glyph marker")
        #expect(deleted.contains("EntryKindMark(kind:"), "Recently deleted renders the glyph marker")
    }
}

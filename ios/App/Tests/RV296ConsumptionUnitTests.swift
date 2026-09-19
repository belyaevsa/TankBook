import TankbookCore
import XCTest
@testable import Tankbook

/// RV.296 + RV.297 - the app-side renderers over the core conversion. The
/// Trends delta's arrow follows the DISPLAYED figure (an improving MPG car
/// shows a rising figure), the after-save and edit toasts speak in the car's
/// unit, and the price caption treats a sub-noise move as no move.
final class RV296ConsumptionUnitTests: XCTestCase {

    func testTheTrendsArrowFollowsTheDisplayedFigure() {
        // 10 -> 8 L/100km is improving: a falling L/100 figure, a rising MPG one.
        let change = HeadlineChange(direction: .improving, percent: 20, previousPer100: 10, currentPer100: 8)
        XCTAssertEqual(TrendsFormat.headlineDelta(change, unit: .consumption(.lPer100)), "▼20%")
        XCTAssertEqual(TrendsFormat.headlineDelta(change, unit: .consumption(.mpgUS)), "▲25%",
                       "MPG rises by the inverse's percent, and the arrow says so")
        XCTAssertEqual(TrendsFormat.headlineDelta(change, unit: .consumption(.kmPerL)), "▲25%")
        XCTAssertTrue(TrendsFormat.headlineDeltaSpoken(change, unit: .consumption(.mpgUS))?.contains("25") == true)
    }

    func testTheToastsSpeakTheCarsUnit() {
        let text = AfterSaveInsightMessage.text(for: .segmentClosed(per100: 6.0, isBestThisYear: false),
                                                unit: .consumption(.mpgUS))
        XCTAssertTrue(text.hasPrefix("39.2 "), "6.0 L/100km is 39.2 MPG (US): \(text)")
        let metric = AfterSaveInsightMessage.text(for: .segmentClosed(per100: 6.0, isBestThisYear: false),
                                                  unit: .consumption(.lPer100))
        XCTAssertTrue(metric.hasPrefix("6.0 "))

        let before = Headline(value: 10, segmentCount: 3, spanDays: 90, windowExtended: false,
                              totalLitres: 100, totalKm: 1000, label: .window(months: 3))
        let after = Headline(value: 8, segmentCount: 3, spanDays: 90, windowExtended: false,
                             totalLitres: 80, totalKm: 1000, label: .window(months: 3))
        let delta = EditConsumptionDelta.message(before: before, after: after, unit: .mpgUS)
        XCTAssertNotNil(delta)
        XCTAssertTrue(delta?.contains("23.5") == true && delta?.contains("29.4") == true,
                      "10 -> 8 L/100km reads 23.5 -> 29.4 MPG: \(delta ?? "nil")")
    }

    func testAnUnchangedPriceIsNotARise() {
        let day = Date(timeIntervalSince1970: 1_750_000_000)
        let later = day.addingTimeInterval(86_400)
        let flat = [TrendPoint(date: day, value: 1.679), TrendPoint(date: later, value: 1.679)]
        XCTAssertEqual(TrendsFormat.priceCaption(series: flat), HomeFormat.day(flat[1].date),
                       "no move falls back to the date caption")
        let noise = [TrendPoint(date: day, value: 1.679), TrendPoint(date: later, value: 1.684)]
        XCTAssertEqual(TrendsFormat.priceCaption(series: noise), HomeFormat.day(noise[1].date),
                       "a sub-1% move is noise, not an arrow")
        let rise = [TrendPoint(date: day, value: 1.60), TrendPoint(date: later, value: 1.648)]
        XCTAssertEqual(TrendsFormat.priceCaption(series: rise), "▲3.0%")
    }
}

import Testing
import Foundation
@testable import TankbookCore

/// RV.147 - the windowed cost-per-km figure must never be built on a
/// rate-pending row summed as zero. This is the FOURTH surface with the shape
/// (RV.106 fixed the divider, RV.112 the vitals tile and both Trends series),
/// and the first that is a RATIO: a partial numerator over a complete odometer
/// denominator is low by an unknown amount while looking plausible.
///
/// The decided treatment (docs/SCHEMA.md -> COST/KM): the figure exists ONLY
/// when the window's money is exact - the shared accumulator classifies the
/// window `.complete`, every money-bearing row converted and the known figures
/// homed in one currency. A window holding a rate-pending row (or known
/// figures in more than one home currency) reports NO figure, and
/// `costPerKmSpanMonths` reports no span for a figure that is not there.
struct CostPerKmPendingWindowTests {

    private static func calendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private static func date(_ year: Int, _ month: Int, _ day: Int,
                             _ hour: Int = 12) -> Date {
        calendar().date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    /// A fixed "now" (2026-08-20) so the 90-day cost window is deterministic.
    private static let asOf = date(2026, 8, 20)
    private static let day: TimeInterval = 86_400

    private static func vehicle() -> Vehicle {
        Vehicle(
            id: UUID.v7(), createdAt: Self.date(2025, 6, 1), updatedAt: Self.date(2025, 6, 1),
            deletedAt: nil, name: "Volvo V60", make: "Volvo", model: "V60", year: 2015,
            plate: nil, powertrain: .ice, fuelKinds: [.petrol95],
            tankCapacityL: 71, batteryCapacityKWh: nil, homeCurrency: .eur,
            units: Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100,
                                  energy: .kWhPer100),
            photo: nil, archived: false, paceLimitKmPerDay: 1500,
            initialOdometer: 118_000)
    }

    private static func homeMoney(_ amount: String) -> Money {
        Money(amount: Decimal(string: amount)!, currency: .eur, homeCurrency: .eur)
    }

    /// A rate-pending pair: known in its original currency (PLN), no home
    /// figure yet - the RV.147 shape.
    private static func pendingMoney(_ amount: String) -> Money {
        Money(amount: Decimal(string: amount)!, currency: .pln, homeCurrency: .eur)
    }

    /// A converted pair homed in a NON-vehicle currency (left over from an old
    /// car home, RV.145) - how a window becomes `.mixed`.
    private static func usdHomeMoney(_ amount: String) -> Money {
        Money(amount: Decimal(string: amount)!, currency: .usd, homeCurrency: .usd)
    }

    private static func fill(_ date: Date, odo: Int, amount: String,
                             vehicleID: UUID = UUID.v7(), money: Money? = nil) -> FillUp {
        FillUp(
            id: UUID.v7(), createdAt: date, updatedAt: date, deletedAt: nil,
            vehicleId: vehicleID, date: date, odometer: odo,
            money: money ?? Self.homeMoney(amount), note: nil, attachments: [],
            provenance: .manual, conflict: .none, purchaseGroupId: nil,
            volumeL: 42, unitPrice: nil, fuelKind: .petrol95, fuelGrade: nil,
            isFull: true, tankLevelAfterPct: 100, stationId: nil,
            crossCheck: .verified, extraction: nil)
    }

    // MARK: - A pending row in the window means NO figure, on every surface

    @Test func windowWithAPendingRowReportsNoCostPerKm() {
        // A km span exists (1600 km) and two rows are converted, but one row in
        // the window is still waiting on a rate: the old code returned
        // 208.96 / 1600 = 0.13 as if the pending PLN row cost nothing.
        let entries: [any Entry] = [
            Self.fill(Self.asOf - 80 * Self.day, odo: 118_000, amount: "107.25"),
            Self.fill(Self.asOf - 60 * Self.day, odo: 118_800, amount: "289.50",
                      money: Self.pendingMoney("289.50")),
            Self.fill(Self.asOf - 40 * Self.day, odo: 119_600, amount: "101.71")
        ]

        let engineFigure = ConsumptionEngine.costPerKm(entries: entries, asOf: Self.asOf,
                                                       homeCurrency: .eur)
        #expect(engineFigure == nil,
                "a window holding a pending row must not report a cost-per-km figure")

        let home = HomeStats(vehicle: Self.vehicle(), entries: entries,
                             asOf: Self.asOf, calendar: Self.calendar())
        #expect(home.costPerKm == nil,
                "HomeStats must not expose a bare cost-per-km for a pending window")
        #expect(home.pendingRateCount == 1)

        let trends = TrendsStats(vehicle: Self.vehicle(), entries: entries,
                                 asOf: Self.asOf, calendar: Self.calendar())
        #expect(trends.home.costPerKm == nil)
        #expect(trends.costPerKmSpanMonths == nil,
                "no figure, so no span label may describe one")
    }

    @Test func fullyPendingWindowAlsoReportsNoFigure() {
        let entries: [any Entry] = [
            Self.fill(Self.asOf - 70 * Self.day, odo: 118_000, amount: "289.50",
                      money: Self.pendingMoney("289.50")),
            Self.fill(Self.asOf - 50 * Self.day, odo: 118_800, amount: "294.00",
                      money: Self.pendingMoney("294.00"))
        ]
        let figure = ConsumptionEngine.costPerKm(entries: entries, asOf: Self.asOf,
                                                 homeCurrency: .eur)
        #expect(figure == nil)
        let home = HomeStats(vehicle: Self.vehicle(), entries: entries,
                             asOf: Self.asOf, calendar: Self.calendar())
        #expect(home.costPerKm == nil)
    }

    // MARK: - A fully converted window is unchanged, to the cent (regression guard)

    @Test func fullyConvertedWindowIsUnchangedToTheCent() {
        let entries: [any Entry] = [
            Self.fill(Self.asOf - 30 * Self.day, odo: 118_000, amount: "107.25"),
            Self.fill(Self.asOf - 3 * Self.day, odo: 118_800, amount: "101.71")
        ]
        let exact = Decimal(string: "107.25")! + Decimal(string: "101.71")!

        let figure = ConsumptionEngine.costPerKm(entries: entries, asOf: Self.asOf,
                                                 homeCurrency: .eur)
        #expect(figure?.amount == exact,
                "the figure's amount must be the exact converted sum, to the cent")
        #expect(figure?.currency == .eur)
        #expect(figure?.km == 800)
        #expect(abs((figure?.perKm ?? 0) - (exact as NSDecimalNumber).doubleValue / 800) < 0.000_001,
                "the displayed ratio must be amount over the km span, unchanged")

        let home = HomeStats(vehicle: Self.vehicle(), entries: entries,
                             asOf: Self.asOf, calendar: Self.calendar())
        #expect(home.costPerKm == figure)
    }

    // MARK: - The figure agrees with the accumulator through the shared seam

    /// The engine must route the window's money through the SAME accumulator the
    /// divider and the month tiles use (RV.112), so the figure and the tile can
    /// never disagree about what is known. Asserted here against the shared seam
    /// type - the test feeds the identical money pairs to the identical
    /// accumulator - not against a parallel hand-written sum.
    @Test func figureAgreesWithAccumulatorClassificationForTheSameEntries() {
        let scenarios: [(name: String, entries: [any Entry])] = [
            ("fully converted", [
                Self.fill(Self.asOf - 20 * Self.day, odo: 118_000, amount: "107.25"),
                Self.fill(Self.asOf - 10 * Self.day, odo: 118_800, amount: "101.71")
            ]),
            ("one pending among converted", [
                Self.fill(Self.asOf - 80 * Self.day, odo: 118_000, amount: "107.25"),
                Self.fill(Self.asOf - 60 * Self.day, odo: 118_800, amount: "289.50",
                          money: Self.pendingMoney("289.50")),
                Self.fill(Self.asOf - 40 * Self.day, odo: 119_600, amount: "101.71")
            ]),
            ("all pending", [
                Self.fill(Self.asOf - 70 * Self.day, odo: 118_000, amount: "289.50",
                          money: Self.pendingMoney("289.50")),
                Self.fill(Self.asOf - 50 * Self.day, odo: 118_800, amount: "294.00",
                          money: Self.pendingMoney("294.00"))
            ]),
            ("known figures homed in two currencies", [
                Self.fill(Self.asOf - 20 * Self.day, odo: 118_000, amount: "68.46",
                          money: Self.usdHomeMoney("68.46")),
                Self.fill(Self.asOf - 10 * Self.day, odo: 118_600, amount: "101.71")
            ])
        ]

        for scenario in scenarios {
            let figure = ConsumptionEngine.costPerKm(entries: scenario.entries,
                                                     asOf: Self.asOf, homeCurrency: .eur)
            let inWindow = scenario.entries.filter {
                $0.date >= Self.asOf - 90 * Self.day && $0.date <= Self.asOf
            }
            var accumulator = LogStream.MonthTotal.Accumulator(vehicleHome: .eur)
            accumulator.add(contentsOf: inWindow.map(\.money))
            let odometers = inWindow.compactMap(\.odometer)
            let span = (odometers.max() ?? 0) - (odometers.min() ?? 0)

            switch accumulator.monthTotal {
            case .complete(let amount, let currency):
                if span > 0 {
                    #expect(figure != nil, "\(scenario.name): a complete window with a km span must report")
                    #expect(figure?.amount == amount,
                            "\(scenario.name): the figure's amount must be the accumulator's exact amount")
                    #expect(figure?.currency == currency,
                            "\(scenario.name): the figure carries the accumulator's currency")
                } else {
                    #expect(figure == nil, "\(scenario.name): no km span, no figure")
                }
            case .partial, .mixed, .pending:
                #expect(figure == nil,
                        "\(scenario.name): a window the accumulator does not call .complete must report no figure")
            }
        }
    }

    // MARK: - The span label never disagrees with the figure about the window

    @Test func spanLabelNeverDescribesAFullyKnownShortWindow() {
        // Two weeks of converted data: the figure exists and the label says the
        // real span ("last month"), never the full 90-day window.
        let entries: [any Entry] = [
            Self.fill(Self.asOf - 12 * Self.day, odo: 118_000, amount: "107.25"),
            Self.fill(Self.asOf - 2 * Self.day, odo: 118_800, amount: "101.71")
        ]
        let trends = TrendsStats(vehicle: Self.vehicle(), entries: entries,
                                 asOf: Self.asOf, calendar: Self.calendar())
        #expect(trends.home.costPerKm != nil)
        #expect(trends.costPerKmSpanMonths == 1)
    }
}

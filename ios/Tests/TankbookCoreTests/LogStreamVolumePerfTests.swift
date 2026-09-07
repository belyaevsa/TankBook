import Testing
import Foundation
@testable import TankbookCore

// RV.103 - the Log's new reveal must not be the thing that makes a long log
// slow. LogStream is rebuilt on every Home load (hard rule 2), so the number
// this suite prints is the per-render cost of showing the log at the owner's
// real volume (the 513-row MFM export, `Spike/ImportFixtures/mfm/parsed.json`).
//
// It is a MEASUREMENT, not a wall-clock gate: no machine-speed assert (a hard
// bound would go red on a loaded box and prove nothing), so the only assertions
// are the correctness ones - the reveal never drops, duplicates or splits a row
// at volume, which is what a silent off-by-one at a page boundary would do. The
// printed medians are the deliverable; the orchestrator reads them from the run.

@Suite("RV.103 log-stream volume (L2/perf)")
struct LogStreamVolumePerfTests {

    private static let repoRoot = URL(fileURLWithPath: #filePath).standardizedFileURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    private static let parsedFixture = repoRoot
        .appendingPathComponent("Spike/ImportFixtures/mfm/parsed.json")

    /// A parsed MFM candidate, kept to the fields a FillUp seed needs. The JSON
    /// is the server import parser's REAL output for the owner's export - the
    /// same rows a committed import would write.
    private struct Candidate: Decodable {
        struct Money: Decodable {
            let amount: String
            let currency: String
        }
        let entityType: String
        let date: Date
        let odometer: Int
        let volumeL: Double
        let money: Money
        let vehicleName: String
    }

    private struct ParseWrapper: Decodable {
        let candidates: [Candidate]
    }

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    private static func vehicle() -> Vehicle {
        Vehicle(
            id: UUID.v7(), createdAt: Date(), updatedAt: Date(), deletedAt: nil,
            name: "Audi A4", make: "Audi", model: "A4", year: 2009,
            plate: nil, powertrain: .ice, fuelKinds: [.diesel],
            tankCapacityL: 70, batteryCapacityKWh: nil, homeCurrency: .usd,
            units: Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100,
                                  energy: .kWhPer100),
            photo: nil, archived: false, paceLimitKmPerDay: 1500,
            initialOdometer: 179_000)
    }

    private static func fillUp(_ candidate: Candidate, vehicleID: UUID) -> FillUp {
        let currency = CurrencyCode(rawValue: candidate.money.currency) ?? .usd
        return FillUp(
            id: UUID.v7(), createdAt: candidate.date, updatedAt: candidate.date,
            deletedAt: nil, vehicleId: vehicleID, date: candidate.date,
            odometer: candidate.odometer,
            money: Money(amount: Decimal(string: candidate.money.amount)!,
                         currency: currency, homeCurrency: currency),
            note: nil, attachments: [], provenance: .manual, conflict: .none,
            purchaseGroupId: nil, volumeL: candidate.volumeL, unitPrice: nil,
            fuelKind: .diesel, fuelGrade: nil, isFull: true,
            tankLevelAfterPct: 100, stationId: nil,
            crossCheck: .notApplicable, extraction: nil)
    }

    private static func loadCandidates() throws -> [Candidate] {
        let data = try Data(contentsOf: parsedFixture)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ParseWrapper.self, from: data)
            .candidates
            .filter { $0.entityType == "fillUp" }
    }

    /// Median wall time in milliseconds over `samples` runs.
    private static func medianMillis(_ samples: Int, _ body: () -> Void) -> Double {
        let clock = ContinuousClock()
        var times: [Double] = []
        for _ in 0..<samples {
            let start = clock.now
            body()
            let elapsed = clock.now - start
            let seconds = Double(elapsed.components.seconds)
                + Double(elapsed.components.attoseconds) / 1e18
            times.append(seconds * 1000)
        }
        times.sort()
        return times[times.count / 2]
    }

    @Test("reveal at the owner's real volume: correct and its cost measured")
    func revealAtTheOwnersRealVolume() throws {
        let all = try Self.loadCandidates()
        #expect(all.count == 513,
                "the MFM fixture must keep its 513 rows - it is the measured volume")
        #expect(all.contains { $0.vehicleName.contains("AUDI A4") },
                "the fixture must carry the owner's main car")
        let audiCount = all.filter { $0.vehicleName.contains("AUDI A4") }.count

        // The whole export treated as one car is the upper bound; the AUDI A4
        // subset (the export's largest single car) is what one selected car's
        // Home actually builds. Both are measured against the same volume.
        for (label, rows) in [("513 rows (whole export, one car)", all),
                              ("\(audiCount) rows (AUDI A4, one selected car)",
                               all.filter { $0.vehicleName.contains("AUDI A4") })] {
            let vehicle = Self.vehicle()
            let entries: [any Entry] = rows.map { Self.fillUp($0, vehicleID: vehicle.id) }

            // Correctness at volume first: the reveal must keep the stream
            // whole and atomic whether or not it is fast.
            let stream = LogStream(vehicle: vehicle, entries: entries,
                                   calendar: Self.calendar)
            let pages = stream.revealPages()
            var revealedIDs: [UUID] = []
            for page in pages {
                revealedIDs.append(contentsOf: page.months.flatMap(\.rows).map(\.id))
            }
            #expect(revealedIDs == stream.allRows.map(\.id),
                    "the reveal at \(label) must reproduce the whole stream in order")
            #expect(Set(revealedIDs).count == Set(stream.allRows.map(\.id)).count,
                    "the reveal at \(label) must not drop or duplicate a row")
            #expect(pages.last?.hiddenEntryCount == 0,
                    "fully revealed at \(label) must hide nothing")

            // The per-render cost Home pays today (LogStream + revealPages, the
            // whole-month slice it shows) against the old path it replaced
            // (LogStream + previewRows, the row-capped cut). Both rebuild the
            // stream every load (hard rule 2).
            let revealPath = Self.medianMillis(15) {
                let built = LogStream(vehicle: vehicle, entries: entries,
                                      calendar: Self.calendar)
                _ = built.revealPages()
            }
            let oldPath = Self.medianMillis(15) {
                let built = LogStream(vehicle: vehicle, entries: entries,
                                      calendar: Self.calendar)
                _ = built.previewRows(20)
            }
            // Single visible page for the reveal render - the extra cost of
            // flattening the shown months for the VStack.
            let flatten = Self.medianMillis(15) {
                let built = LogStream(vehicle: vehicle, entries: entries,
                                      calendar: Self.calendar)
                _ = built.revealPages().prefix(1).flatMap(\.months)
            }
            print("RV.103 perf [\(label)]: reveal path median \(String(format: "%.2f", revealPath)) ms, "
                  + "old previewRows path \(String(format: "%.2f", oldPath)) ms, "
                  + "reveal+flatten \(String(format: "%.2f", flatten)) ms")
        }
    }
}

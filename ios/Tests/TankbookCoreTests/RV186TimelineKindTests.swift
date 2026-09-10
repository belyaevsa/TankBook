import Testing
import Foundation
@testable import TankbookCore

// RV.186: the strict odometer increase applies between the kinds that MEASURE
// travel (FillUp, ChargeSession). A ServiceRecord or an Expense is an
// annotation at a point - work done at the pump without moving - so it may
// share a reading with a neighbour; a falling reading stays a conflict for
// every kind (docs/SCHEMA.md, Validation).

private let kindDay: TimeInterval = 86_400
private let kindEpoch = Date(timeIntervalSince1970: 1_752_000_000)

private func kindVehicle(paceLimit: Double = 1500) -> Vehicle {
    Vehicle(
        id: UUID.v7(), createdAt: kindEpoch, updatedAt: kindEpoch, deletedAt: nil,
        name: "Kind car", make: nil, model: nil, year: nil, plate: nil,
        powertrain: .ice, fuelKinds: [.petrol95], tankCapacityL: nil,
        batteryCapacityKWh: nil, homeCurrency: .eur,
        units: Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100, energy: .kWhPer100),
        photo: nil, paceLimitKmPerDay: paceLimit)
}

private func kindFill(date: Date, odometer: Int?, id: UUID = UUID.v7()) -> FillUp {
    FillUp(
        id: id, createdAt: date, updatedAt: date, deletedAt: nil, vehicleId: UUID.v7(),
        date: date, odometer: odometer, money: nil, note: nil, attachments: [],
        provenance: .manual, conflict: .none, purchaseGroupId: nil, volumeL: 40,
        unitPrice: nil, fuelKind: .petrol95, fuelGrade: nil, isFull: true,
        tankLevelAfterPct: nil, stationId: nil, crossCheck: .notApplicable, extraction: nil)
}

private func kindService(date: Date, odometer: Int?, id: UUID = UUID.v7()) -> ServiceRecord {
    ServiceRecord(
        id: id, createdAt: date, updatedAt: date, deletedAt: nil, vehicleId: UUID.v7(),
        date: date, odometer: odometer, money: nil, note: nil, attachments: [],
        provenance: .manual, conflict: .none, purchaseGroupId: nil, vendor: nil,
        items: [], usedParts: [], tireSetId: nil, proposedReminderId: nil)
}

private func kindExpense(date: Date, odometer: Int?, id: UUID = UUID.v7()) -> Expense {
    Expense(
        id: id, createdAt: date, updatedAt: date, deletedAt: nil, vehicleId: UUID.v7(),
        date: date, odometer: odometer, money: nil, note: nil, attachments: [],
        provenance: .manual, conflict: .none, purchaseGroupId: nil, category: .toll,
        title: "Toll")
}

private func kindCharge(date: Date, odometer: Int?, id: UUID = UUID.v7()) -> ChargeSession {
    ChargeSession(
        id: id, createdAt: date, updatedAt: date, deletedAt: nil, vehicleId: UUID.v7(),
        date: date, odometer: odometer, provenance: .manual, energyKWh: 40,
        chargeType: .acPublic)
}

/// The flags the validator reports for `id`.
private func kindFlags(_ entries: [any Entry], _ id: UUID,
                       limit: Double = 1500) -> [TimelineValidator.Flag] {
    TimelineValidator.validate(entries: entries, vehicle: kindVehicle(paceLimit: limit))
        .first { $0.entryID == id }?.flags ?? []
}

/// Stamps each entry's `conflict` from the validator, as every write path does,
/// so the exclusion derivation sees the same verdict the badge would.
private func stamped(_ entries: [any Entry]) -> [any Entry] {
    let validations = TimelineValidator.validate(entries: entries, vehicle: kindVehicle())
    var result = entries
    for validation in validations {
        guard let index = result.firstIndex(where: { $0.id == validation.entryID }) else { continue }
        result[index].conflict = validation.conflict
    }
    return result
}

// MARK: - The fix: an annotation may share a reading

@Suite("RV.186 the odometer rule per entry kind")
struct RV186TimelineKindTests {

    /// The defect: a service at the pump shares the fill-up's reading. It is not
    /// flagged AND it stays in the stats - both, because asserting the flag is
    /// gone without the exclusion would pass on a row that was still dropped.
    @Test func serviceSharingAFillReadingIsNotFlaggedAndStaysInTheStats() {
        let fill = kindFill(date: kindEpoch, odometer: 100_000)
        let service = kindService(date: kindEpoch + 3600, odometer: 100_000)

        let validation = TimelineValidator.validate(entries: [fill, service], vehicle: kindVehicle())
            .first { $0.entryID == service.id }
        #expect(validation?.flags.isEmpty == true)
        #expect(validation?.conflict == ConflictState.none)

        let excluded = ExcludedEntries.derive(in: stamped([fill, service]), duplicatePairs: [])
        #expect(!excluded.contains { $0.id == service.id },
                "the shared-reading service must stay in the derived figures")
    }

    /// The owner's 396 930 pair: two services at one reading.
    @Test func twoServicesAtOneReadingAreNotFlagged() {
        let first = kindService(date: kindEpoch, odometer: 396_930)
        let second = kindService(date: kindEpoch + 48, odometer: 396_930)

        #expect(kindFlags([first, second], first.id).isEmpty)
        #expect(kindFlags([first, second], second.id).isEmpty)
    }

    /// An expense may share the fill's reading (the owner's 377 733 case).
    @Test func expenseSharingAFillReadingIsNotFlagged() {
        let fill = kindFill(date: kindEpoch, odometer: 377_733)
        let expense = kindExpense(date: kindEpoch + 44, odometer: 377_733)

        #expect(kindFlags([fill, expense], fill.id).isEmpty)
        #expect(kindFlags([fill, expense], expense.id).isEmpty)
    }

    /// Two fill-ups at one reading still conflict: they claim travel that did
    /// not happen. The relaxation must not swallow this.
    @Test func twoFillUpsAtOneReadingAreStillFlagged() {
        let first = kindFill(date: kindEpoch, odometer: 100_000)
        let second = kindFill(date: kindEpoch + 3600, odometer: 100_000)

        #expect(kindFlags([first, second], first.id).contains { $0.kind == .order })
        #expect(kindFlags([first, second], second.id).contains { $0.kind == .order })
    }

    /// Two charge sessions at one reading are travel entries too.
    @Test func twoChargeSessionsAtOneReadingAreStillFlagged() {
        let first = kindCharge(date: kindEpoch, odometer: 50_000)
        let second = kindCharge(date: kindEpoch + 3600, odometer: 50_000)

        #expect(kindFlags([first, second], first.id).contains { $0.kind == .order })
        #expect(kindFlags([first, second], second.id).contains { $0.kind == .order })
    }

    /// A falling reading stays a conflict for every kind - the half of the rule
    /// that must not regress. Each kind is the falling entry below a fill.
    @Test func fallingOdometerIsStillFlaggedForEveryKind() {
        let anchor = kindFill(date: kindEpoch, odometer: 100_000)
        let later = kindEpoch + 10 * kindDay

        let fallingFill = kindFill(date: later, odometer: 99_000)
        let fallingService = kindService(date: later, odometer: 99_000)
        let fallingExpense = kindExpense(date: later, odometer: 99_000)
        let fallingCharge = kindCharge(date: later, odometer: 99_000)

        for falling in [fallingFill as any Entry, fallingService, fallingExpense, fallingCharge] {
            let flags = kindFlags([anchor, falling], falling.id)
            #expect(flags.contains { $0.kind == .order },
                    "\(type(of: falling)) falling below its neighbour must flag")
        }
    }

    /// The invariant agrees with the per-entry check: a shared annotation
    /// reading holds, two travel entries at one reading do not.
    @Test func invariantHoldsForAnnotationsAndBreaksForTwoFills() {
        #expect(TimelineValidator.invariantHolds(entries: [
            kindFill(date: kindEpoch, odometer: 100_000),
            kindService(date: kindEpoch + 3600, odometer: 100_000),
        ]))
        #expect(!TimelineValidator.invariantHolds(entries: [
            kindFill(date: kindEpoch, odometer: 100_000),
            kindFill(date: kindEpoch + 3600, odometer: 100_000),
        ]))
    }

    /// The valid range mirrors the relaxed order bound: an annotation sharing a
    /// fill's reading has an inclusive lower end, a fill below a fill does not.
    @Test func validRangeIsInclusiveForAnAnnotationNeighbour() {
        func lowerBound(_ range: ValidRange<Int>?) -> Int? {
            if case .bounded(let lower, _) = range { return lower }
            return nil
        }
        let fill = kindFill(date: kindEpoch, odometer: 100_000)

        let service = kindService(date: kindEpoch + 3600, odometer: 100_000)
        let serviceRange = TimelineValidator.validate(entries: [fill, service], vehicle: kindVehicle())
            .first { $0.entryID == service.id }?.validRange
        #expect(lowerBound(serviceRange?.odometer) == 100_000)

        let secondFill = kindFill(date: kindEpoch + 3600, odometer: 100_000)
        let fillRange = TimelineValidator.validate(entries: [fill, secondFill], vehicle: kindVehicle())
            .first { $0.entryID == secondFill.id }?.validRange
        #expect(lowerBound(fillRange?.odometer) == 100_001)
    }
}

// MARK: - The owner's real export

private enum DrivvoFixture {
    static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    static func url() -> URL {
        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<8 {
            let candidate = directory.appendingPathComponent("Spike/ImportFixtures/drivvo/drivvo-ru-3sections.csv")
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            directory = directory.deletingLastPathComponent()
        }
        return URL(fileURLWithPath: "Spike/ImportFixtures/drivvo/drivvo-ru-3sections.csv")
    }

    /// Every odometer-bearing entry the import would write: fills, services and
    /// expenses. `0`/`0.0` maps to `nil` exactly as the import maps it, and
    /// localised header rows are skipped by the date parse.
    static func entries() throws -> [any Entry] {
        let text = try String(contentsOf: url(), encoding: .utf8)
        var entries: [any Entry] = []
        var section = ""
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("##") { section = String(line.dropFirst(2)); continue }
            guard !line.isEmpty else { continue }
            let fields = line.hasPrefix("\"") && line.hasSuffix("\"")
                ? String(line.dropFirst().dropLast()).components(separatedBy: "\",\"")
                : line.components(separatedBy: ",")
            guard fields.count > 1, let date = formatter.date(from: fields[1]) else { continue }
            let raw = Double(fields[0]) ?? 0
            let odometer = raw == 0 ? nil : Int(raw)
            switch section {
            case "Refuelling":
                guard fields.count > 6,
                      let volume = Double(fields[5].replacingOccurrences(of: ",", with: ".")) else { continue }
                var fill = kindFill(date: date, odometer: odometer)
                fill.volumeL = volume
                entries.append(fill)
            case "Service":
                entries.append(kindService(date: date, odometer: odometer))
            case "Expense":
                entries.append(kindExpense(date: date, odometer: odometer))
            default:
                continue
            }
        }
        return entries
    }
}

@Suite("RV.186 against the owner's Drivvo export")
struct RV186DrivvoFixtureTests {

    /// The owner's first case: the imported services at 396 930 and the expense
    /// sharing the 377 733 fill-up are no longer order-flagged. Before RV.186
    /// every equal reading flagged, so these sat on the Excluded page and the
    /// spend and service history silently left the figures.
    @Test func ownerFirstCaseEqualReadingsAreNotOrderFlagged() throws {
        let entries = try DrivvoFixture.entries()
        let validations = TimelineValidator.validate(entries: entries, vehicle: kindVehicle())
        let byID = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })

        let equalReadingAnnotations = validations.filter { validation in
            guard let entry = byID[validation.entryID],
                  entry.odometer == 396_930 || entry.odometer == 377_733 else { return false }
            return entry is ServiceRecord || entry is Expense
        }
        #expect(!equalReadingAnnotations.isEmpty, "the fixture must carry the owner's rows")
        #expect(equalReadingAnnotations.allSatisfy { validation in
            !validation.flags.contains { $0.kind == .order }
        }, "annotations sharing a fill reading must not be order-flagged")
    }

    /// The owner's second case, now RV.192's: two fill-ups on 20 Sep 2020 at
    /// 360 200 and 360 519 are NOT order-flagged (CHECK 1 passes) and - since
    /// RV.192 made the pace guard a CALENDAR-DAY rule - not pace-flagged either.
    /// RV.186 correctly left the pace half alone, and this test recorded the
    /// defect: 2 h 27 min and 319 km apart is an implied 3 124 km/day under the
    /// old fractional-instant guard. RV.192's decision is that a same-day
    /// neighbour contributes no pace bound (docs/SCHEMA.md, Validation), so the
    /// pair is clean. The fixture dates are parsed in UTC, so the check pins a
    /// UTC calendar rather than inheriting the machine's.
    @Test func ownerSecondCaseIsSameDayAndNotPaceFlagged() throws {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let entries = try DrivvoFixture.entries()
        let validations = TimelineValidator.validate(entries: entries, vehicle: kindVehicle(),
                                                     calendar: utc)
        let byID = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })

        let secondCase = validations.filter { validation in
            byID[validation.entryID]?.odometer == 360_200 || byID[validation.entryID]?.odometer == 360_519
        }
        #expect(secondCase.count == 2, "the fixture must carry both 20 Sep fills")
        #expect(secondCase.allSatisfy { validation in
            !validation.flags.contains { $0.kind == .order }
        }, "CHECK 1 is not what flags the pair (RV.186 holds)")
        #expect(secondCase.allSatisfy { validation in
            !validation.flags.contains { $0.kind == .pace }
        }, "RV.192: a same-day pair contributes no pace bound, so the pair is clean")
    }
}

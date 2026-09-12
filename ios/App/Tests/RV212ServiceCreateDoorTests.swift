import Foundation
import XCTest
import TankbookCore
@testable import Tankbook

/// RV.212 / RV.213 / RV.224 - the service CREATE door catches up with the edit
/// door (docs/JOURNEYS.md J7, J7d).
///
/// Three behaviours the edit screen got from PJ.22/PJ.23 and the create screen
/// did not: the per-item lifetime editor, one save rule shared by both doors,
/// and a date provenance caption that clears once the user edits the date. The
/// tests drive the app's own form types so a divergence between the two doors
/// is caught here rather than in the simulator.
@MainActor
final class RV212ServiceCreateDoorTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func makeVehicle() throws -> (TankbookRepository, Vehicle) {
        let repository = try TankbookRepository(database: TankbookDatabase.inMemory())
        let now = Date()
        let vehicle = Vehicle(
            id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
            name: "Volvo V60", make: "Volvo", model: "V60", year: 2015,
            plate: nil, powertrain: .ice, fuelKinds: [.petrol95],
            tankCapacityL: 71, batteryCapacityKWh: nil, homeCurrency: .eur,
            units: Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100,
                                 energy: .kWhPer100),
            photo: nil, archived: false, paceLimitKmPerDay: 1500,
            initialOdometer: 118_579)
        try repository.upsertVehicle(vehicle)
        return (repository, vehicle)
    }

    // MARK: - RV.213 the offer fires at the FIRST save

    /// A service created WITH a stated lifetime raises the offer at its first
    /// save. The create card now renders the same editor the edit door uses, so
    /// the interval reaches the saved record and the proposal in one visit.
    func testCreateDoorWithAStatedLifetimeProposesAtFirstSave() throws {
        let (_, vehicle) = try makeVehicle()
        var form = ServiceEntryFormState()
        form.items = [ServiceEntryItemDraft(
            title: "Brake pads front", category: .brakes, cost: "59.00",
            lifetime: ServiceItem.Lifetime(km: 30_000, months: 24))]

        let record = form.draft(vehicle: vehicle)
            .build(vehicleId: vehicle.id, homeCurrency: vehicle.homeCurrency)
        let proposal = ReminderOffer.propose(afterService: record, liveReminders: [])
        XCTAssertNotNil(proposal, "a stated lifetime must raise the offer at the first save")
        XCTAssertEqual(proposal?.everyKm, 30_000)
        XCTAssertEqual(proposal?.everyMonths, 24)
    }

    /// A service created WITHOUT a lifetime on a category that has no curated
    /// interval proposes nothing - the offer responds to a stated interval, not
    /// to every service save.
    func testCreateDoorWithoutALifetimeProposesNothing() throws {
        let (_, vehicle) = try makeVehicle()
        var form = ServiceEntryFormState()
        form.items = [ServiceEntryItemDraft(
            title: "Brake pads front", category: .brakes, cost: "59.00")]

        let record = form.draft(vehicle: vehicle)
            .build(vehicleId: vehicle.id, homeCurrency: vehicle.homeCurrency)
        XCTAssertNil(ReminderOffer.propose(afterService: record, liveReminders: []))
    }

    /// The two screens render the SAME editor view - one view, two doors. A
    /// second lifetime editor on either card is the defect this guards.
    func testBothServiceCardsRenderTheOneLifetimeEditor() throws {
        let sources = try Self.sourcesDirectory()
        let cards = [
            "ServiceEntry/ServiceEntrySections.swift",
            "EditEntry/EditEntryNonFillView.swift"
        ]
        for relative in cards {
            let text = try String(contentsOf: sources.appendingPathComponent(relative),
                                  encoding: .utf8)
            XCTAssertTrue(text.contains("ServiceItemLifetimeFields(lifetime:"),
                          "\(relative) must render the shared ServiceItemLifetimeFields")
        }
    }

    // MARK: - RV.212 one save rule, both doors

    /// The (lifetime, odometer) pair is accepted identically by both doors.
    /// RV.212 decided NEITHER refuses: a km lifetime with a blank odometer is a
    /// fact the user states and the app cannot use yet, so the entry saves and
    /// the offer names the missing odometer.
    func testBothDoorsAcceptAKmLifetimeWithNoOdometer() {
        var create = ServiceEntryFormState()
        create.items = [ServiceEntryItemDraft(
            title: "Oil service", category: .oil,
            lifetime: ServiceItem.Lifetime(km: 15_000, months: nil))]

        var edit = EditEntryNonFillForm()
        edit.items = [ServiceEntryItemDraft(
            title: "Oil service", category: .oil,
            lifetime: ServiceItem.Lifetime(km: 15_000, months: nil))]

        XCTAssertEqual(create.saveReadiness, edit.saveReadiness,
                       "the two doors must agree on the (lifetime, odometer) pair")
        XCTAssertEqual(create.saveReadiness, .ready,
                       "a km lifetime with no odometer is not a refusal on either door")
    }

    /// The one remaining refusal is a mounted tire set with a blank odometer -
    /// its mileage span anchors on the odometer, and it is a create-only state.
    func testAMountedTireSetWithNoOdometerStillRefuses() {
        var create = ServiceEntryFormState()
        // A set is mounted only in tires mode (`tireSetId`'s own doc); the
        // create rule branches on the mode first (RV.214).
        create.mode = .tires
        create.tireSetId = UUID.v7()
        XCTAssertEqual(create.saveReadiness, .odometerRequired)
        XCTAssertEqual(ServiceEntryDraft.saveReadiness(odometer: nil, tireSetId: nil), .ready)
    }

    // MARK: - RV.224 the invoice caption clears on a manual edit

    /// Editing the scanned date makes the date the user's own, so the "· invoice"
    /// caption clears and never returns (hard rule 13). A same-value set - the
    /// graphical picker re-applies its value on appear - is not an edit.
    func testEditingTheScannedDateClearsTheInvoiceCaption() {
        var form = ServiceEntryFormState()
        let invoiceDate = ConfirmDate.parse("09.08.2026")!
        form.date = invoiceDate
        form.dateFromInvoice = true

        form.userChangedDate(to: invoiceDate)
        XCTAssertTrue(form.dateFromInvoice,
                      "a same-value set must leave the invoice caption alone")

        form.userChangedDate(to: invoiceDate.addingTimeInterval(86_400))
        XCTAssertFalse(form.dateFromInvoice,
                       "a manual date edit must clear the invoice caption")
    }

    // MARK: - Source tree (mirrors RV181ShareSeamSourceTests)

    private static func sourcesDirectory() throws -> URL {
        let thisFile = URL(fileURLWithPath: #filePath).standardizedFileURL
        var candidate = thisFile.deletingLastPathComponent() // ios/App/Tests
        for _ in 0..<3 { candidate = candidate.deletingLastPathComponent() } // -> repo root
        let sources = candidate.appendingPathComponent("ios/App/Sources", isDirectory: true)
        guard FileManager.default.fileExists(atPath: sources.path) else {
            throw NSError(
                domain: "RV212ServiceCreateDoorTests", code: 1,
                userInfo: [NSLocalizedDescriptionKey:
                    "app source tree not found at \(sources.path) - the seam gate cannot run"])
        }
        return sources
    }
}

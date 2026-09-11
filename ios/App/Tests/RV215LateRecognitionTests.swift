import TankbookCore
import UIKit
import XCTest
@testable import Tankbook

/// RV.215 - the deferred service and expense recognition. Before this row both
/// reads ran inline before their form opened, so a reading could never arrive
/// after the save and the inbox only ever held fill-up items. These tests drive
/// the REAL sessions (`ServiceInvoiceSession`, `ExpenseEntrySession`) and the
/// REAL `AppInbox`: a reading that completes after `markSaved` becomes an item
/// through `GatewayInboxPolicy.item`, one that completes before it fills the
/// form and makes no item, and a reading for a since-deleted entry is absorbed.
///
/// The boundary is asserted from both sides, and the agreeing case is the one
/// the named mutation (a direct insert instead of the policy) turns red: a
/// reading that AGREES is not worth an item, and only the policy knows that.
@MainActor
final class RV215LateRecognitionTests: XCTestCase {

    /// A one-shot async gate, so a test can hold the read open while it saves and
    /// then release it - deterministic, no timing race.
    @MainActor
    private final class Gate {
        private var continuation: CheckedContinuation<Void, Never>?
        private var isOpen = false

        func wait() async {
            if isOpen { return }
            await withCheckedContinuation { self.continuation = $0 }
        }

        func open() {
            isOpen = true
            continuation?.resume()
            continuation = nil
        }
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        UserDefaults.standard.removeObject(forKey: AppInbox.storageKey)
    }

    override func tearDownWithError() throws {
        UserDefaults.standard.removeObject(forKey: AppInbox.storageKey)
    }

    private func makeVehicle() throws -> (TankbookRepository, Vehicle) {
        let repository = try AppStore.repository()
        let now = Date()
        let vehicle = Vehicle(
            id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
            name: "RV215 Volvo", make: "Volvo", model: "V60", year: 2015,
            plate: nil, powertrain: .ice, fuelKinds: [.petrol95],
            tankCapacityL: 71, batteryCapacityKWh: nil, homeCurrency: .eur,
            units: Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100,
                                 energy: .kWhPer100),
            photo: nil, archived: false, paceLimitKmPerDay: 1500,
            initialOdometer: 118_930)
        try repository.upsertVehicle(vehicle)
        return (repository, vehicle)
    }

    private func makeService(vehicle: Vehicle, vendor: String = "Old Garage") throws -> ServiceRecord {
        let now = Date()
        let service = ServiceRecord(
            id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
            vehicleId: vehicle.id, date: now, odometer: 120_000,
            money: Money(amount: Decimal(string: "200.00")!, currency: .eur, homeCurrency: .eur),
            note: nil, attachments: [], provenance: .manual, conflict: .none,
            purchaseGroupId: nil, vendor: vendor, items: [], usedParts: [], tireSetId: nil)
        try AppStore.repository().upsertServiceRecord(service)
        return service
    }

    private func makeExpense(vehicle: Vehicle, category: ExpenseCategory = .accessory) throws -> Expense {
        let now = Date()
        let expense = Expense(
            id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
            vehicleId: vehicle.id, date: now, odometer: nil,
            money: Money(amount: Decimal(string: "12.40")!, currency: .eur, homeCurrency: .eur),
            note: nil, attachments: [], provenance: .manual, conflict: .none,
            purchaseGroupId: nil, category: category, title: "Shop")
        try AppStore.repository().upsertExpense(expense)
        return expense
    }

    private func serviceOutcome(vendor: String) -> ServiceScanOutcome {
        ServiceScanOutcome(
            prefill: ServiceEntryPrefill(),
            recognition: ServiceRecognition(vendor: .init(value: vendor, confidence: 0.9)))
    }

    private func expenseOutcome(category: ExpenseCategory) -> ExpenseScanOutcome {
        let capture = ExpenseScanCapture(image: UIImage(), extraction: FuelExtraction(),
                                         ocrLines: [])
        return ExpenseScanOutcome(
            prefill: ExpensePrefill(),
            preset: category,
            capture: capture,
            recognition: ExpenseRecognition(
                category: .init(value: category, confidence: 0.8)))
    }

    // MARK: - Service

    func testALateServiceReadBecomesAnItemThroughTheOnePolicy() async throws {
        let (_, vehicle) = try makeVehicle()
        let service = try makeService(vehicle: vehicle)
        let inbox = AppInbox(noteEntryChanged: {})
        let session = ServiceInvoiceSession()
        let gate = Gate()

        session.start(
            work: { await gate.wait(); return self.serviceOutcome(vendor: "New Garage") },
            onAnswer: { _ in XCTFail("a read after the save must not fill the form") },
            onSavedAnswer: { outcome, entryID in
                inbox.recordLateGatewayAnswer(.service(outcome.recognition), entryID: entryID)
            })
        await Task.yield()
        session.markSaved(entryID: service.id)
        gate.open()
        try await Task.sleep(for: .milliseconds(80))

        XCTAssertTrue(inbox.hasItem(for: service.id),
                      "a service read that lands after the save must become an inbox item")
    }

    func testAServiceReadBeforeTheSaveFillsTheFormAndMakesNoItem() async throws {
        let (_, vehicle) = try makeVehicle()
        let service = try makeService(vehicle: vehicle)
        let inbox = AppInbox(noteEntryChanged: {})
        let session = ServiceInvoiceSession()
        var answered = false

        session.start(
            work: { self.serviceOutcome(vendor: "New Garage") },
            onAnswer: { _ in answered = true },
            onSavedAnswer: { outcome, entryID in
                inbox.recordLateGatewayAnswer(.service(outcome.recognition), entryID: entryID)
            })
        try await Task.sleep(for: .milliseconds(80))
        session.markSaved(entryID: service.id)
        try await Task.sleep(for: .milliseconds(40))

        XCTAssertTrue(answered, "a read that finished first must fill the open form")
        XCTAssertFalse(inbox.hasItem(for: service.id),
                       "a read that finished before the save is the form's, not the inbox's")
    }

    /// The named mutation: routing the late service answer through a direct
    /// `insert` instead of `GatewayInboxPolicy.item` would produce an item here.
    /// The policy knows an agreeing reading is not work; a direct insert does not.
    func testALateServiceReadThatAgreesMakesNoItem() async throws {
        let (_, vehicle) = try makeVehicle()
        let service = try makeService(vehicle: vehicle, vendor: "Old Garage")
        let inbox = AppInbox(noteEntryChanged: {})
        let session = ServiceInvoiceSession()
        let gate = Gate()

        session.start(
            work: { await gate.wait(); return self.serviceOutcome(vendor: "Old Garage") },
            onAnswer: { _ in XCTFail("a read after the save must not fill the form") },
            onSavedAnswer: { outcome, entryID in
                inbox.recordLateGatewayAnswer(.service(outcome.recognition), entryID: entryID)
            })
        await Task.yield()
        session.markSaved(entryID: service.id)
        gate.open()
        try await Task.sleep(for: .milliseconds(80))

        XCTAssertFalse(inbox.hasItem(for: service.id),
                       "an agreeing late reading is not worth an item - the policy decides, not the producer")
    }

    /// A second scan in the same long-lived session must start a fresh read: the
    /// session outlives the sheet (unlike the fuel path's per-sheet session), so
    /// the first save must not leave the boundary latched.
    func testASecondScanAfterASaveStartsAFreshRead() async throws {
        let (_, vehicle) = try makeVehicle()
        let service = try makeService(vehicle: vehicle)
        let inbox = AppInbox(noteEntryChanged: {})
        let session = ServiceInvoiceSession()
        let first = Gate()

        session.start(
            work: { await first.wait(); return self.serviceOutcome(vendor: "New Garage") },
            onAnswer: { _ in },
            onSavedAnswer: { outcome, entryID in
                inbox.recordLateGatewayAnswer(.service(outcome.recognition), entryID: entryID)
            })
        await Task.yield()
        session.markSaved(entryID: service.id)
        first.open()
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertTrue(inbox.hasItem(for: service.id))

        // A second scan replaces the saved read's state and answers on time.
        var answered = false
        session.start(
            work: { self.serviceOutcome(vendor: "Another Garage") },
            onAnswer: { _ in answered = true },
            onSavedAnswer: { _, _ in XCTFail("the second read was never saved") })
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertTrue(answered,
                      "a new scan must start a fresh read, not be blocked by the prior save")
    }

    func testALateServiceReadForADeletedEntryIsAbsorbedNotCrashed() async throws {
        let (repository, vehicle) = try makeVehicle()
        let service = try makeService(vehicle: vehicle)
        let inbox = AppInbox(noteEntryChanged: {})
        let session = ServiceInvoiceSession()
        let gate = Gate()

        session.start(
            work: { await gate.wait(); return self.serviceOutcome(vendor: "New Garage") },
            onAnswer: { _ in },
            onSavedAnswer: { outcome, entryID in
                inbox.recordLateGatewayAnswer(.service(outcome.recognition), entryID: entryID)
            })
        await Task.yield()
        session.markSaved(entryID: service.id)
        // The entry is deleted before the read lands.
        try repository.softDeleteServiceRecord(id: service.id)
        gate.open()
        try await Task.sleep(for: .milliseconds(80))

        XCTAssertFalse(inbox.hasItem(for: service.id),
                       "a late reading for a deleted entry is absorbed, never left pending")
    }

    // MARK: - Expense

    func testALateExpenseReadBecomesAnItemThroughTheOnePolicy() async throws {
        let (_, vehicle) = try makeVehicle()
        let expense = try makeExpense(vehicle: vehicle, category: .accessory)
        let inbox = AppInbox(noteEntryChanged: {})
        let session = ExpenseEntrySession()
        let gate = Gate()

        session.start(
            work: { await gate.wait(); return self.expenseOutcome(category: .parking) },
            onAnswer: { _ in XCTFail("a read after the save must not fill the form") },
            onSavedAnswer: { outcome, entryID in
                inbox.recordLateGatewayAnswer(.expense(outcome.recognition), entryID: entryID)
            })
        await Task.yield()
        session.markSaved(entryID: expense.id)
        gate.open()
        try await Task.sleep(for: .milliseconds(80))

        XCTAssertTrue(inbox.hasItem(for: expense.id),
                      "an expense read that lands after the save must become an inbox item")
    }

    func testAnExpenseReadBeforeTheSaveFillsTheFormAndMakesNoItem() async throws {
        let (_, vehicle) = try makeVehicle()
        let expense = try makeExpense(vehicle: vehicle)
        let inbox = AppInbox(noteEntryChanged: {})
        let session = ExpenseEntrySession()
        var answered = false

        session.start(
            work: { self.expenseOutcome(category: .parking) },
            onAnswer: { _ in answered = true },
            onSavedAnswer: { outcome, entryID in
                inbox.recordLateGatewayAnswer(.expense(outcome.recognition), entryID: entryID)
            })
        try await Task.sleep(for: .milliseconds(80))
        session.markSaved(entryID: expense.id)
        try await Task.sleep(for: .milliseconds(40))

        XCTAssertTrue(answered, "a read that finished first must fill the open form")
        XCTAssertFalse(inbox.hasItem(for: expense.id),
                       "a read that finished before the save is the form's, not the inbox's")
    }
}

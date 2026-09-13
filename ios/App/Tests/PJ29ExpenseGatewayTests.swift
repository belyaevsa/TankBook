import TankbookCore
import UIKit
import XCTest
@testable import Tankbook

/// PJ.29 - the Expense-mode capture's cloud half. These drive the REAL session
/// (`ExpenseEntrySession`) with a recording transport, so the request the
/// shipped path builds is asserted directly - `kind: "expense"`, the hints, and
/// the late-answer boundary - without a paid call. The full capture -> save ->
/// inbox path is the L4 `GatewayCaptureUITests`.
///
/// The named vacuous trap this guards: sending `kind: "receipt"` for an expense
/// (the fuel prompt answers with volume and fuel kind, the mapping drops them,
/// and the cloud never learned it was a parking ticket). The first test fails on
/// exactly that mutation.
@MainActor
final class PJ29ExpenseGatewayTests: XCTestCase {

    /// A one-shot async gate, so the test holds the answer open while it saves.
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

    private actor RecordingTransport: GatewayExtractTransport {
        let answer: GatewayExtraction
        private let gate: Gate?
        private(set) var requests: [GatewayExtractRequest] = []

        init(answer: GatewayExtraction, gate: Gate? = nil) {
            self.answer = answer
            self.gate = gate
        }

        func extract(_ request: GatewayExtractRequest) async throws -> GatewayExtraction {
            requests.append(request)
            if let gate { await gate.wait() }
            return answer
        }
    }

    private func image() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 40, height: 40)).image { context in
            UIColor.gray.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 40, height: 40))
        }
    }

    private func answer() -> GatewayExtraction {
        GatewayExtraction(
            total: .init(value: Decimal(string: "12.40")!, confidence: 0.9),
            date: .init(value: "17.08.2026", confidence: 0.8),
            currency: .init(value: .eur, confidence: 0.9),
            category: .init(value: .parking, confidence: 0.7),
            pipeline: "test")
    }

    private func makeVehicle() throws -> Vehicle {
        let repository = try AppStore.repository()
        let now = Date()
        let vehicle = Vehicle(
            id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
            name: "PJ29 Volvo", make: "Volvo", model: "V60", year: 2015,
            plate: nil, powertrain: .ice, fuelKinds: [.petrol95],
            tankCapacityL: 71, batteryCapacityKWh: nil, homeCurrency: .eur,
            units: Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100,
                                 energy: .kWhPer100),
            photo: nil, archived: false, paceLimitKmPerDay: 1500,
            initialOdometer: 118_930)
        try repository.upsertVehicle(vehicle)
        return vehicle
    }

    private func savedExpense(amount: String = "12.40",
                              category: ExpenseCategory = .parking) throws -> Expense {
        let vehicle = try makeVehicle()
        let now = Date()
        let expense = Expense(
            id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
            vehicleId: vehicle.id, date: now, odometer: nil,
            money: Money(amount: Decimal(string: amount)!, currency: .eur, homeCurrency: .eur),
            note: nil, attachments: [], provenance: .manual, conflict: .none,
            purchaseGroupId: nil, category: category, title: "Shop")
        try AppStore.repository().upsertExpense(expense)
        return expense
    }

    func testTheRequestCarriesTheExpenseKindAndTheHints() async throws {
        let transport = RecordingTransport(answer: answer())
        let session = ExpenseEntrySession()
        session.startGateway(
            image: image(),
            hints: GatewayExtractHints(currency: "EUR", locale: "en", vehicleFuelKinds: []),
            captureId: "capture-1",
            transport: transport,
            onSavedAnswer: { _, _ in })
        try await Task.sleep(for: .milliseconds(80))

        let requests = await transport.requests
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.kind, "expense",
                       "the expense capture must ask for the expense kind, never 'receipt'")
        XCTAssertEqual(request.hints.currency, "EUR",
                       "the car's home currency rides the request as a hint")
        XCTAssertEqual(request.captureId, "capture-1")
    }

    func testALateExpenseAnswerIsRoutedToTheInboxThroughTheOnePolicy() async throws {
        UserDefaults.standard.removeObject(forKey: AppInbox.storageKey)
        let expense = try savedExpense()
        let inbox = AppInbox(noteEntryChanged: {})
        let session = ExpenseEntrySession()
        let gate = Gate()
        let transport = RecordingTransport(answer: answer(), gate: gate)

        session.startGateway(
            image: image(),
            hints: GatewayExtractHints(currency: "EUR", locale: "en", vehicleFuelKinds: []),
            captureId: "capture-2",
            transport: transport,
            onSavedAnswer: { extraction, entryID in
                XCTAssertEqual(entryID, expense.id)
                inbox.recordLateGatewayAnswer(
                    .expense(ExpensePrefillBuilder.reading(fromGateway: extraction).recognition),
                    entryID: entryID)
            })
        await Task.yield()
        session.markSaved(entryID: expense.id)
        gate.open()
        try await Task.sleep(for: .milliseconds(120))

        XCTAssertTrue(inbox.hasItem(for: expense.id),
                      "a cloud expense answer that lands after the save must reach the inbox")
    }

    func testTheKindIsTheExpenseKindEvenWhenTheAnswerIsWithinBudget() async throws {
        // The within-budget answer fills the open form; the session holds it for
        // the sheet to consume, and no inbox item is made (the form it filled is
        // what the save writes).
        UserDefaults.standard.removeObject(forKey: AppInbox.storageKey)
        let expense = try savedExpense()
        let inbox = AppInbox(noteEntryChanged: {})
        let session = ExpenseEntrySession()
        let transport = RecordingTransport(answer: answer())

        session.startGateway(
            image: image(),
            hints: GatewayExtractHints(currency: "EUR", locale: "en", vehicleFuelKinds: []),
            captureId: "capture-3",
            transport: transport,
            onSavedAnswer: { extraction, entryID in
                inbox.recordLateGatewayAnswer(
                    .expense(ExpensePrefillBuilder.reading(fromGateway: extraction).recognition),
                    entryID: entryID)
            })
        try await Task.sleep(for: .milliseconds(80))

        let pending = try XCTUnwrap(session.consumePendingGatewayExtraction())
        XCTAssertEqual(pending.category?.value, .parking)
        XCTAssertFalse(inbox.hasItem(for: expense.id),
                       "a within-budget answer is the open form's, not the inbox's")
    }
}

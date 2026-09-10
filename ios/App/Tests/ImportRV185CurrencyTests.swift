import TankbookCore
import XCTest
@testable import Tankbook

/// RV.185 - the import must carry the currency the file declares (or the user
/// answers) onto the NEW car it creates, not just onto the entries. A new car
/// defaulted to EUR against KZT rows is a log full of rate-pending rows for a
/// user who never asked for a second currency, and hard rule 13 is broken at the
/// moment the value is stated.
@MainActor
final class ImportRV185CurrencyTests: XCTestCase {

    private func makeRepository() throws -> TankbookRepository {
        TankbookRepository(database: try TankbookDatabase.inMemory())
    }

    private func makeModel(_ repository: TankbookRepository) -> ImportFlowModel {
        ImportService.makeModel(repository: repository,
                                configService: AppConfigService.make(arguments: []))
    }

    /// A one-fill parse that DECLARES `currency` (a non-empty currency
    /// ambiguity's first option). The hardcode and the fix are indistinguishable
    /// with EUR, so every test here passes a non-EUR code.
    private func declaredCurrencyParse(_ currency: CurrencyCode) -> ImportParseResponse {
        let candidate = ImportCandidate(
            entityType: "fillUp",
            date: Date(timeIntervalSince1970: 1_786_924_800), // 2026-08-17
            odometer: 491_206, volumeL: 40, unitPrice: "220",
            money: ImportMoney(amount: "8442", currency: currency.rawValue),
            fuelKind: "petrol92", isFull: true, tankLevelAfterPct: nil, note: nil,
            vehicleName: nil,
            provenance: ImportProvenance(tag: "import", source: "mfm"),
            sourceRow: 1)
        return ImportParseResponse(
            importId: "00000000-0000-4000-8000-000000000401", format: "mfm",
            scope: "vehicle", candidates: [candidate], unparsed: [],
            ambiguities: [ImportAmbiguity(kind: "currency",
                                          options: [currency.rawValue], rowCount: 1)])
    }

    private func installNewCarImport(_ model: ImportFlowModel, currency: CurrencyCode) {
        model.adoptSingleFile(fileName: "export.csv", rawData: Data(),
                              parse: declaredCurrencyParse(currency))
        model.ensureTargetCar(preferredVehicleID: nil)
        model.rebuildClassification()
    }

    /// The headline: the car the import creates carries the DECLARED currency,
    /// asserted on the value the repository stored (not on the model's draft).
    func testNewCarCreatedByImportCarriesTheDeclaredCurrency() async throws {
        let repository = try makeRepository()
        let model = makeModel(repository)
        installNewCarImport(model, currency: .kzt)

        guard case .new(let vehicle) = model.targetCar else {
            return XCTFail("no live car, so the import must target a new one")
        }
        XCTAssertEqual(vehicle.homeCurrency, .kzt,
                       "the synthesized car carries the declared currency")

        let ok = await model.confirmImport()
        XCTAssertTrue(ok)
        let stored = try repository.liveVehicles()
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored.first?.homeCurrency, .kzt,
                       "the STORED car carries the declared currency, not the old hardcoded EUR")
    }

    /// The car and its imported entries agree, so no row is rate-pending PURELY
    /// because of the car's home currency. Oracle: the same `MoneyBackfillService`
    /// pending count the F9 footnote uses - a same-currency pair snapshots at
    /// rate 1 and needs no fetch, so a zero here cannot come from a count written
    /// in the test.
    func testImportedCarAndEntriesAgreeSoNoRowIsRatePending() async throws {
        let repository = try makeRepository()
        let model = makeModel(repository)
        installNewCarImport(model, currency: .kzt)
        let ok = await model.confirmImport()
        XCTAssertTrue(ok)

        let store = RateStore(seed: [])
        let result = try MoneyBackfillService(store: store).backfill(repository)
        XCTAssertEqual(result.stillPendingCount, 0,
                       "a clean KZT import must not leave rate-pending rows against a EUR home")
    }

    /// Importing into an EXISTING car leaves that car's home currency
    /// byte-identical: re-homing an owned car is RV.152's decision, not the
    /// import's.
    func testImportIntoExistingCarLeavesItsHomeCurrencyUntouched() async throws {
        let repository = try makeRepository()
        let existing = TargetCar.newCar(named: "Owned", homeCurrency: .eur).vehicleValue
        try repository.upsertVehicle(existing)

        let model = makeModel(repository)
        model.reloadVehicles()
        installNewCarImport(model, currency: .kzt)
        model.selectExistingVehicle(existing)
        model.rebuildClassification()
        let ok = await model.confirmImport()
        XCTAssertTrue(ok)

        let stored = try repository.liveVehicles().first { $0.id == existing.id }
        XCTAssertEqual(stored?.homeCurrency, .eur,
                       "the import must not re-home a car the user already owns")
    }
}

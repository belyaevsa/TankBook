import Foundation
import TankbookCore
import XCTest
@testable import Tankbook

/// RV.269 - the review intro's two counts partition the file: the rows not in
/// review are ready, the review rows need a look. `readyFills` is the first
/// count; `importFills` also carries the kept review rows and would make the
/// sentence call the same rows both ready and missing. RV.264's two plural keys
/// are unchanged.
@MainActor
final class RV269ReviewIntroTests: XCTestCase {

    private func makeModel() throws -> ImportFlowModel {
        let repository = TankbookRepository(database: try TankbookDatabase.inMemory())
        return ImportService.makeModel(repository: repository,
                                       configService: AppConfigService.make(arguments: []))
    }

    private func fill(_ row: Int, odometer: Int?, day: TimeInterval) -> ImportCandidate {
        ImportCandidate(
            entityType: "fillUp", date: Date(timeIntervalSince1970: day),
            odometer: odometer, volumeL: 40, unitPrice: "1.50",
            money: ImportMoney(amount: "60.00", currency: "EUR"),
            fuelKind: "petrol95", isFull: true, tankLevelAfterPct: 100, note: nil,
            vehicleName: nil, provenance: ImportProvenance(tag: "import", source: "mfm"),
            sourceRow: row)
    }

    /// A three-row file whose third row has no odometer, so exactly one row
    /// needs a look and the other two are ready.
    private func installThreeRowOneReviewParse(_ model: ImportFlowModel) {
        let response = ImportParseResponse(
            importId: "00000000-0000-4000-8000-000000000269", format: "mfm",
            scope: "vehicle",
            candidates: [
                fill(1, odometer: 100_000, day: 1_786_924_800),   // 2026-08-17
                fill(2, odometer: 100_500, day: 1_787_011_200),   // 2026-08-18
                fill(3, odometer: nil, day: 1_787_097_600),       // 2026-08-19
            ],
            unparsed: [], ambiguities: [])
        model.adoptSingleFile(fileName: "export.csv", rawData: Data(), parse: response)
        model.ensureTargetCar(preferredVehicleID: nil)
        model.rebuildClassification()
    }

    /// The named mutation's red: counting every row the commit writes
    /// (`importFills`) instead of the rows not in review renders
    /// "3 rows are ready. This 1 is missing something" and fails here.
    func testReviewIntroCountsOnlyTheRowsNotInReview() throws {
        let model = try makeModel()
        installThreeRowOneReviewParse(model)

        XCTAssertEqual(model.reviewRows.count, 1, "the missing-odometer row is the one review row")
        XCTAssertEqual(model.readyFills.count, 2, "the two complete rows are ready")
        XCTAssertEqual(model.reviewIntro,
                       "2 rows are ready. This 1 is missing something – fix one, or leave it out.")
    }

    /// The RU equivalent goes through the same two catalogue keys (RV.264), so
    /// the fix changes the number, never the phrase or its plural form.
    func testReviewIntroRendersTheSameKeysInRussian() throws {
        let model = try makeModel()
        installThreeRowOneReviewParse(model)

        let russian = try XCTUnwrap(
            Bundle.main.path(forResource: "ru", ofType: "lproj").flatMap(Bundle.init(path:)),
            "the app must bundle ru.lproj")
        let ready = String(localized: "\(model.readyFills.count) rows are ready.",
                           bundle: russian, locale: Locale(identifier: "ru"))
        let missing = String(
            localized: "These \(model.reviewRows.count) are missing something – fix one, or leave it out.",
            bundle: russian, locale: Locale(identifier: "ru"))
        XCTAssertEqual("\(ready) \(missing)",
                       "2 строки готовы. Эта 1 строка неполная – исправьте или пропустите.")
    }
}

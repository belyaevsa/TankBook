import TankbookCore
import XCTest
@testable import Tankbook

/// The "Not yet" chips on the import source screen must never name a format the
/// server already parses. Drivvo sat in that row for the whole life of its own
/// working parser, telling a user the app could not read the file it was in fact
/// reading - the product owner found it by using the app.
///
/// The screen's own header comment already says a hardcoded list "would make the
/// server-side parser unselectable and defeat the architecture". That was true of
/// the list above the chips and false of the chips themselves, which is exactly
/// the shape `docs/DEFECT-PATTERNS.md` calls a sibling defect.
@MainActor
final class ImportRoadmapChipTests: XCTestCase {

    private func makeView(formats: [ImportFormat]) -> ImportSourceView {
        let model = ImportService.makeModel(
            repository: TankbookRepository(database: try! TankbookDatabase.inMemory()),
            configService: AppConfigService.make(arguments: []))
        model.formats = formats
        return ImportSourceView(model: model, onChooseFile: {}, onNotSupported: {},
                                onBack: {}, onContinueBatch: {})
    }

    private func format(id: String, name: String) -> ImportFormat {
        ImportFormat(id: id, displayName: name, fileKinds: ["csv"], helpUrl: nil,
                     addedInPackVersion: 1)
    }

    /// The regression: with Drivvo in the live format list, no chip claims it is
    /// "not yet". This FAILED on the shipped code, which listed the five names
    /// literally.
    func testAShippedFormatIsNotListedAsNotYet() {
        let view = makeView(formats: [format(id: "mfm", name: "My Fuel Manager"),
                                      format(id: "drivvo", name: "Drivvo")])
        XCTAssertFalse(view.notYetNames.contains("Drivvo"),
                       "Drivvo is parsed by the server; it cannot also be 'not yet'")
        XCTAssertFalse(view.notYetNames.contains("My Fuel Manager"))
    }

    /// The other half: a name that genuinely has no parser stays.
    func testAnUnshippedFormatIsStillListed() {
        let view = makeView(formats: [format(id: "drivvo", name: "Drivvo")])
        XCTAssertTrue(view.notYetNames.contains("Fuelio"))
        XCTAssertTrue(view.notYetNames.contains("Spritmonitor"))
    }

    /// The match is on the display name, case- and space-insensitively, so a
    /// cosmetic rename on either side cannot resurrect a shipped importer.
    func testMatchingIgnoresCaseAndSpacing() {
        let view = makeView(formats: [format(id: "mfm", name: "my fuelmanager")])
        XCTAssertFalse(view.notYetNames.contains("My Fuel Manager"),
                       "a rename must not put a shipped importer back in the row")
    }

    /// With every roadmap name shipped the row has nothing to say, and the
    /// block is not rendered at all rather than rendered empty.
    func testTheRowEmptiesWhenEverythingHasShipped() {
        let all = ImportSourceView.roadmapImporters.enumerated().map {
            format(id: "f\($0.offset)", name: $0.element)
        }
        XCTAssertTrue(makeView(formats: all).notYetNames.isEmpty)
    }
}

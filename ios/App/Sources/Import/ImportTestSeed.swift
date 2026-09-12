#if DEBUG
import Foundation
import TankbookCore

// DEBUG/test seeding for the import wizard (P5.5b) - the same launch-argument
// hook pattern as HomeTestSeed. `-seedImportSource` renders the picker over the
// stub transport's format list; `-seedImportPreview` and `-seedImportReview`
// install a stub parse and drive the flow to the preview/review step, so the UI
// tests and screenshots never need the system file picker or a server.
enum ImportTestSeed {

    @MainActor
    static func seedDatabaseIfRequested() {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("-homeResetDatabase")
            || arguments.contains(where: { $0.hasPrefix("-seedImport") }) else { return }
        if arguments.contains("-homeResetDatabase") {
            AppStore.resetForTestsOncePerLaunch()
        }
        // The preview/review need a target car (the "imports into" card). Seed
        // the Volvo when none exists so the merge duplicate count is real.
        guard arguments.contains("-seedImportPreview")
            || arguments.contains("-seedImportReview")
            || arguments.contains("-seedImportTimeline")
            || arguments.contains("-seedImportResolvedDates")
            || arguments.contains("-seedImportService")
            || arguments.contains("-seedImportCars")
            || arguments.contains("-seedImportCarsDecided")
            || arguments.contains("-seedImportCarsNewCar")
            || arguments.contains("-seedImportBatch")
            || arguments.contains("-seedImportBatchAnomaly")
            || arguments.contains("-seedImportCurrency")
            || arguments.contains("-seedImportNewCarExisting")
            || arguments.contains("-seedImportStation")
            || arguments.contains("-seedImportStationReview")
            || arguments.contains("-seedImportUnsupported") else { return }
        if let repository = try? AppStore.repository(),
           (try? repository.liveVehicles())?.isEmpty != false {
            try? repository.upsertVehicle(HomeTestSeed.makeVehicle())
        }
        // RV.86: the `.cars` mapping gate's merge lane is demonstrated against a
        // real S2 duplicate - the existing Volvo V60 holds one fill that matches
        // the file's Volvo row 3 (same date 2026-08-17, same 64 L), so mapping
        // the file's Volvo into it surfaces the duplicate count. Seeded for the
        // multi-car screenshots and the L4 mapping test alike; the odometer
        // continuity assertions read the MAX, which this pair never touches.
        if (arguments.contains("-seedImportCars") || arguments.contains("-seedImportCarsDecided")
            || arguments.contains("-seedImportCarsNewCar")),
           let repository = try? AppStore.repository(),
           let existing = try? repository.liveVehicles().first {
            let duplicateFill = HomeTestSeed.makeFill(
                vehicleID: existing.id,
                HomeTestSeed.FillSpec(daysAgo: 0, odometer: 119_486, litres: 64,
                                      amount: "110", price: "1.71875",
                                      stationID: nil),
                date: Date(timeIntervalSince1970: 1_786_924_800)) // 2026-08-17T00:00:00Z
            try? repository.upsertFillUp(duplicateFill)
        }
    }

    @MainActor
    static func seedFlowIfRequested(model: ImportFlowModel) {
        let arguments = ProcessInfo.processInfo.arguments
        model.reloadVehicles()
        applyMixedDistanceUnitIfRequested(arguments: arguments, model: model)
        if arguments.contains("-seedImportPreview") {
            model.installSeededParse(resourceName: "import-parse-mfm",
                                     fileName: "MyFuelManager_2026-08.csv",
                                     rawFileResource: "import-mfm-sample")
            model.showPreview()
        } else if arguments.contains("-seedImportCurrency") {
            model.installSeededCurrencyParse()
            model.showPreview()
        } else if arguments.contains("-seedImportStation") {
            // RV.189: a fill whose file row named its station - the Log row must
            // title itself with the station, never the fuel kind ("92").
            model.installSeededStationParse()
            model.showPreview()
        } else if arguments.contains("-seedImportStationReview") {
            // RV.221: a station-named fill that needs a look, so the review row
            // must render the station name before the commit.
            model.installSeededStationReviewParse()
            model.showReview()
        } else if arguments.contains("-seedImportNewCar") {
            // RV.185: no existing car (the Volvo seed is deliberately skipped for
            // this flag), so the import targets a NEW car and the preview offers
            // its editable name beside the currency question. This file names no
            // vehicle, so the suggestion is the neutral default.
            model.pickedFormat = ImportFormat(id: "drivvo", displayName: "Drivvo",
                                              fileKinds: ["csv"], helpUrl: nil,
                                              addedInPackVersion: 1)
            model.installSeededCurrencyParse()
            model.showPreview()
        } else if arguments.contains("-seedImportNewCarExisting") {
            // RV.255: an existing car is in the garage and the user takes the
            // `ImportTargetCarSheet` "New car" door, so the commit must select
            // the car it created rather than leave Home on the pre-existing car.
            model.pickedFormat = ImportFormat(id: "drivvo", displayName: "Drivvo",
                                              fileKinds: ["csv"], helpUrl: nil,
                                              addedInPackVersion: 1)
            model.installSeededCurrencyParse()
            model.selectNewCar()
            model.showPreview()
        } else if arguments.contains("-seedImportUnsupported") {
            // RV.116: the review gate carrying the "not imported" notice with
            // its per-column row counts (Driver 250), and Continue not blocked.
            model.installSeededUnsupportedParse()
            model.showPreview()
        } else if arguments.contains("-seedImportResolvedDates") {
            // RV.85: the detectable-file preview - the server resolved the
            // dates from the file itself, so no dateFormat question renders.
            model.installSeededResolvedDatesParse()
            model.showPreview()
        } else if arguments.contains("-seedImportCarsNewCar") {
            // RV.185 screenshot state: the FIRST lane maps to a new car, so its
            // editable name field is in frame without scrolling. The mapping
            // gate renders one card per source car and a lane's name field sits
            // inside its own card, so which lane is new decides whether the
            // field is photographable at all.
            model.installSeededCarsParse(resourceName: "import-parse-mfm-cars",
                                         fileName: "MyFuelManager_2026-08.csv",
                                         rawFileResource: "import-mfm-cars")
            model.importAsNewCar(at: 0)
        } else if arguments.contains("-seedImportCarsDecided") {
            // RV.86 screenshot state: the multi-car mapping gate with two cars
            // already decided (Volvo -> the existing Volvo V60, AUDI -> a new
            // car), so the figures, the merge duplicate count and the summary
            // bar all render at once.
            let resourceName = arguments.contains("-seedImportMixedUnits")
                ? "import-parse-mfm-cars-mixed-units" : "import-parse-mfm-cars"
            model.installSeededCarsParse(resourceName: resourceName,
                                         fileName: "MyFuelManager_2026-08.csv",
                                         rawFileResource: "import-mfm-cars")
            if let existing = model.liveVehicles.first {
                model.importIntoExistingVehicle(existing, at: 0)
            }
            model.importAsNewCar(at: 1)
            if arguments.contains("-seedImportMixedUnits") {
                model.showReview()
            }
        } else if arguments.contains("-seedImportCars") {
            // RV.86: the multi-car mapping gate, freshly reached - every source
            // car undecided, Continue disabled (the L4 "never default the
            // mapping" surface).
            model.installSeededCarsParse(resourceName: "import-parse-mfm-cars",
                                         fileName: "MyFuelManager_2026-08.csv",
                                         rawFileResource: "import-mfm-cars")
        } else if arguments.contains("-seedImportBatch") {
            // RV.93: a whole-export pick of two files (fuel + costs) whose
            // merged mapping must ask ONCE per distinct car and land both kinds.
            model.installSeededBatchParse()
        } else if arguments.contains("-seedImportBatchAnomaly") {
            // RV.93: a two-file pick whose same-car rows contradict ACROSS the
            // files - only a merged single timeline flags it before the write.
            model.installSeededBatchAnomalyParse()
        } else if arguments.contains("-seedImportTimeline") {
            model.installSeededTimelineParse()
            model.showReview()
        } else if arguments.contains("-seedImportReview") {
            model.installSeededParse(resourceName: "import-parse-review",
                                     fileName: "MyFuelManager_2026-08.csv",
                                     rawFileResource: "import-mfm-review")
            model.showReview()
        } else if arguments.contains("-seedImportService") {
            model.installSeededServiceParse()
            model.showReview()
        } else {
            seedImportRequestFlow(arguments: arguments, model: model)
        }
        // RV.263: the auto-confirm screenshot seam commits without a tap, so a
        // file with no currency column must answer the currency gate first,
        // exactly as a user would.
        if arguments.contains("-seedImportAutoConfirm"), model.needsCurrencyAnswer {
            model.answerCurrency(model.defaultCurrency)
        }
    }

    /// The seeds that drive the REAL parse/read path against the stub transport
    /// (RV.68's 422 card, PR.6's in-flight Cancel, RV.73's unreadable pick), so
    /// each failure state renders from an actual request rather than a fixture.
    /// Split out of `seedFlowIfRequested` to keep its complexity under the
    /// linter's ceiling; it no-ops when none of its flags is present.
    @MainActor
    private static func seedImportRequestFlow(arguments: [String], model: ImportFlowModel) {
        if arguments.contains("-seedImportParse422") {
            // Drive the real parse path against the stub transport's 422, so
            // the specific "doesn't look like X export" message renders from a
            // wire failure, not a model fixture.
            model.selectFormat(model.formats.first ?? ImportFormat(id: "mfm", displayName: "My Fuel Manager",
                                                                   fileKinds: ["csv"], helpUrl: nil,
                                                                   addedInPackVersion: 1))
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("seed-422-\(UUID().uuidString).csv")
            try? Data("Date;Volume\n1/1/2024;42.1".utf8).write(to: url)
            model.parse(fileURL: url)
        } else if arguments.contains("-seedImportParsing") {
            // PR.6: drive the real parse path against a slow stub transport so
            // the Cancel affordance is on screen while `isParsing` is true - the
            // screenshot/UI-test state for "Cancel is visible while parsing".
            model.selectFormat(model.formats.first ?? ImportFormat(id: "mfm", displayName: "My Fuel Manager",
                                                                   fileKinds: ["csv"], helpUrl: nil,
                                                                   addedInPackVersion: 1))
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("seed-parsing-\(UUID().uuidString).csv")
            try? Data("Date;Volume\n1/1/2024;42.1".utf8).write(to: url)
            model.parse(fileURL: url)
        } else if arguments.contains("-seedImportReadFailed") {
            // RV.73: drive the REAL read path against a URL that cannot be
            // read (a pick whose bytes never existed) so the read-failure
            // state - its own card, distinct from the parse-rejection one -
            // renders from an actual failed `Data(contentsOf:)`, never from a
            // fixture. This is the closest a test can get to a security-scoped
            // pick that the app cannot read: the read is refused either way,
            // and the state that must follow is `.couldNotRead`.
            model.selectFormat(model.formats.first ?? ImportFormat(id: "mfm", displayName: "My Fuel Manager",
                                                                   fileKinds: ["csv"], helpUrl: nil,
                                                                   addedInPackVersion: 1))
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("seed-read-failed-\(UUID().uuidString).csv")
            model.parse(fileURL: url)
        }
    }

    /// Makes the existing car use miles before the decided two-car seed maps
    /// its other source car into a new kilometre car. Kept as a separate flag
    /// so the established RV.86 screenshot seed stays byte-for-byte unchanged.
    @MainActor
    private static func applyMixedDistanceUnitIfRequested(arguments: [String],
                                                          model: ImportFlowModel) {
        guard arguments.contains("-seedImportMixedUnits"),
              let repository = try? AppStore.repository(),
              var existing = try? repository.liveVehicles().first else { return }
        existing.units.distance = .mi
        try? repository.upsertVehicle(existing)
        model.reloadVehicles()
    }
}
#endif

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
            || arguments.contains("-seedImportReview") else { return }
        if let repository = try? AppStore.repository(),
           (try? repository.liveVehicles())?.isEmpty != false {
            try? repository.upsertVehicle(HomeTestSeed.makeVehicle())
        }
    }

    @MainActor
    static func seedFlowIfRequested(model: ImportFlowModel) {
        let arguments = ProcessInfo.processInfo.arguments
        model.reloadVehicles()
        if arguments.contains("-seedImportPreview") {
            model.installSeededParse(resourceName: "import-parse-mfm",
                                     fileName: "MyFuelManager_2026-08.csv",
                                     rawFileResource: "import-mfm-sample")
            model.showPreview()
        } else if arguments.contains("-seedImportReview") {
            model.installSeededParse(resourceName: "import-parse-review",
                                     fileName: "MyFuelManager_2026-08.csv",
                                     rawFileResource: "import-mfm-review")
            model.showReview()
        } else if arguments.contains("-seedImportParse422") {
            // Drive the real parse path against the stub transport's 422, so
            // the specific "doesn't look like X export" message renders from a
            // wire failure, not a model fixture.
            model.selectFormat(model.formats.first ?? ImportFormat(id: "mfm", displayName: "My Fuel Manager",
                                                                   fileKinds: ["csv"], helpUrl: nil,
                                                                   addedInPackVersion: 1))
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("seed-422-\(UUID().uuidString).csv")
            try? Data("Date;Volume\n1/1/2024;42.1".utf8).write(to: url)
            Task { await model.parse(fileURL: url) }
        }
    }
}

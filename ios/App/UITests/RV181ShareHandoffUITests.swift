import XCTest

/// RV.181 - a share reported as never reaching its destination (iOS 26, iPhone
/// 13). **These tests do NOT reproduce that**, and saying so is the point of
/// this header: they pass on the shape the report was filed against and on the
/// shape shipped after it. `Save to Files` completing under both is what rules
/// out the first theory - that the activity had no presenter.
///
/// What they are worth is a floor: the share sheet opens, and an in-process
/// destination writes a real artefact. The reported failure is at an
/// out-of-process destination on a device, which no simulator test reaches;
/// the seam's outcome record (`ShareOutcome`) exists to diagnose the next
/// report instead.
///
/// Simulator, not device: `Save to Files` and `Copy` exist on the simulator and
/// are enough to prove the hand-off. `Save to Files` writes into the Files
/// app's local storage ("On My iPhone"), which the simulator exposes on the
/// host filesystem under the device's `File Provider Storage`.
@MainActor
final class RV181ShareHandoffUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Launch

    private func launchSettings(seed: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-homeResetDatabase", seed, "-presentScreen", "settings"]
        app.launch()
        return app
    }

    private func openExportShare(_ app: XCUIApplication) {
        let row = app.buttons["settingsExportRow"]
        XCTAssertTrue(row.waitForExistence(timeout: 15), "the Export everything row is reachable")
        if !row.isHittable { app.swipeUp() }
        row.tap()
    }

    // MARK: - The arrival test (green on both shapes - see the header)

    /// After choosing *Save to Files* the exported archive must be ON DISK.
    /// This passes on the shape the defect was reported against, so it is a
    /// regression floor for the in-process destination, **not** evidence that
    /// RV.181 is fixed.
    func testExportReachesSaveToFiles() throws {
        removeSavedExports()

        let app = launchSettings(seed: "-seedSettingsPending")
        openExportShare(app)

        // The half that already worked: the activity sheet is up. Asserted so
        // the arrival failure below is clearly the second half, not this one.
        XCTAssertTrue(app.otherElements["ActivityListView"].waitForExistence(timeout: 20),
                      "the export must open the system share sheet")

        let saveToFiles = app.cells["Save to Files"]
        XCTAssertTrue(saveToFiles.waitForExistence(timeout: 10),
                      "the share sheet must offer Save to Files")
        saveToFiles.tap()

        let save = app.buttons["Save"]
        XCTAssertTrue(save.waitForExistence(timeout: 20),
                      "Save to Files must open the Files browser - a destination with a presenter")
        save.tap()

        // The save is asynchronous (the file provider copies the folder).
        let deadline = Date().addingTimeInterval(15)
        var landed: URL?
        while Date() < deadline, landed == nil {
            landed = savedExportFolder()
            if landed == nil { usleep(300_000) }
        }

        let folder = try XCTUnwrap(landed,
                                   "the export must actually land in Files, not just close the sheet")
        let data = folder.appendingPathComponent("data.json")
        let manifest = folder.appendingPathComponent("manifest.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: data.path),
                      "the archive's data.json must arrive at \(data.path)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: manifest.path),
                      "the archive's manifest.json must arrive at \(manifest.path)")

        // The host sheet must close once the activity settles, so the user is
        // not left on a blank sheet (the completion path owns the dismissal).
        XCTAssertTrue(app.otherElements["ActivityListView"].waitForNonExistence(timeout: 10),
                      "the share sheet must close after the activity settles")
        XCTAssertTrue(app.buttons["settingsExportRow"].waitForExistence(timeout: 10),
                      "the export must return to Settings")
    }

    /// The "sheet is presented" half, on its own. This is green on the broken
    /// code and must stay green after the fix - it is why the committed
    /// screenshots never caught RV.181.
    func testExportShareSheetIsPresented() {
        let app = launchSettings(seed: "-seedSettingsPending")
        openExportShare(app)
        XCTAssertTrue(app.otherElements["ActivityListView"].waitForExistence(timeout: 20),
                      "the export must open the system share sheet")
    }

    /// The outcome half, without a destination dispatch: Copy runs in-process,
    /// so it can prove the activity settled AND that the share seam logged a
    /// `completed` outcome. **It does not prove a destination received
    /// anything** - that needs the owner's iPhone 13 (see the header). What it
    /// proves is that the presentation is the fixed one and that the diagnostics
    /// preview now carries the share line, which is the device evidence path.
    func testExportCopyCompletesAndTheDiagnosticsPreviewCarriesTheShareLine() {
        let app = XCUIApplication()
        app.launchArguments = ["-homeResetDatabase", "-seedSettingsPending",
                               "-presentScreen", "settings", "-diagnosticsConsentOn"]
        app.launch()
        openExportShare(app)

        let sheet = app.otherElements["ActivityListView"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 20),
                      "the export must open the system share sheet")
        let copy = app.cells["Copy"]
        XCTAssertTrue(copy.waitForExistence(timeout: 10),
                      "the share sheet must offer Copy")
        copy.tap()

        XCTAssertTrue(sheet.waitForNonExistence(timeout: 10),
                      "the share sheet must close once Copy completes")
        XCTAssertTrue(app.buttons["settingsExportRow"].waitForExistence(timeout: 10),
                      "the export must return to Settings")

        // The device evidence path: the diagnostics bundle already carries the
        // in-memory breadcrumb ring, so the share's `app.event` line is on
        // screen without a share of its own.
        let about = app.buttons["settingsAboutRow"]
        XCTAssertTrue(about.waitForExistence(timeout: 10), "About is reachable from Settings")
        scrollUntilHittable(about, in: app)
        about.tap()

        let previewButton = app.buttons["diagnosticsPreviewButton"]
        XCTAssertTrue(previewButton.waitForExistence(timeout: 15),
                      "the diagnostics opt-in must reveal the preview affordance")
        scrollUntilHittable(previewButton, in: app)
        previewButton.tap()

        let preview = app.staticTexts["diagnosticsPreviewText"]
        XCTAssertTrue(preview.waitForExistence(timeout: 15),
                      "the diagnostics preview must open")
        let text = preview.label
        XCTAssertTrue(text.contains("operation=export.share"),
                      "the preview must carry the export share's outcome line")
        XCTAssertTrue(text.contains("outcome=completed"),
                      "the Copy share must be recorded as completed")
    }

    /// A tap below this line can be swallowed by the owned tab bar (~760 pt on
    /// this device); scroll until the control is safely above it.
    private func scrollUntilHittable(_ element: XCUIElement, in app: XCUIApplication) {
        var attempts = 0
        while element.frame.midY > 700 || !element.isHittable, attempts < 12 {
            app.swipeUp()
            attempts += 1
        }
    }

    // MARK: - Files "On My iPhone" storage

    /// The simulator's device data root, resolved from the test runner's own
    /// container path (`.../Devices/<UDID>/data/Containers/Data/Application/<id>`)
    /// so nothing here hardcodes a user or a device id.
    private func deviceDataRoot() -> URL? {
        var url = URL(fileURLWithPath: NSHomeDirectory()).standardizedFileURL
        for _ in 0..<4 { url = url.deletingLastPathComponent() }
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    /// The folder `Save to Files` writes into "On My iPhone": the Files app's
    /// local-storage provider keeps it under a shared app group's
    /// `File Provider Storage` directory.
    private func savedExportFolder() -> URL? {
        for group in filesAppGroupContainers() {
            let folder = group.appendingPathComponent("File Provider Storage/Tankbook-Account")
            if FileManager.default.fileExists(atPath: folder.path) { return folder }
        }
        return nil
    }

    private func removeSavedExports() {
        for group in filesAppGroupContainers() {
            let folder = group.appendingPathComponent("File Provider Storage/Tankbook-Account")
            try? FileManager.default.removeItem(at: folder)
        }
    }

    private func filesAppGroupContainers() -> [URL] {
        guard let root = deviceDataRoot() else { return [] }
        let shared = root.appendingPathComponent("Containers/Shared/AppGroup")
        let contents = try? FileManager.default.contentsOfDirectory(
            at: shared, includingPropertiesForKeys: nil)
        return contents ?? []
    }
}

import XCTest

/// Share-to-Tankbook (docs/JOURNEYS.md J2, PJ.21), on the Import suite's own
/// launch helper.
@MainActor
extension ImportUITests {

    /// A file shared to Tankbook opens the wizard at its source step with the
    /// file waiting: the primary action reads THAT file ("Read <name>") once
    /// the source app is declared, and the picker is the second door. The
    /// app never sniffs the file - the format list is still the question.
    func testSharedFileLandsOnTheSourceStepNamingTheFile() {
        let app = launch(["-openFile", "fuel-log.csv", "-importStubFormats", "one"])

        XCTAssertTrue(app.buttons["importFormatRow-mfm"].waitForExistence(timeout: 10),
                      "the shared file must land on the wizard's source step")
        let read = app.buttons["importChooseFileButton"]
        XCTAssertTrue(read.waitForExistence(timeout: 5))
        XCTAssertEqual(read.label, "Read fuel-log.csv", "the primary action names the shared file")
        XCTAssertTrue(app.buttons["importChooseAnotherFileButton"].exists,
                      "the picker stays one tap away as the second door")
    }

    func testSharedFileLandsOnTheSourceStepInRussian() {
        let app = XCUIApplication()
        app.launchArguments = ["-homeResetDatabase", "-openFile", "fuel-log.csv", "-importStubFormats", "one",
                               "-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU"]
        app.launch()

        XCTAssertTrue(app.buttons["importFormatRow-mfm"].waitForExistence(timeout: 10))
        let read = app.buttons["importChooseFileButton"]
        XCTAssertTrue(read.waitForExistence(timeout: 5))
        XCTAssertEqual(read.label, "Прочитать fuel-log.csv",
                       "the RU primary action is one phrase with the name inside it")
        XCTAssertEqual(app.buttons["importChooseAnotherFileButton"].label, "Выбрать другой файл")

        app.terminate()
        let reset = XCUIApplication()
        reset.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        reset.launch()
        reset.terminate()
    }
}

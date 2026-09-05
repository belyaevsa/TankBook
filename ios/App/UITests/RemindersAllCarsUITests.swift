import XCTest

/// RV.75 - the merged "all cars" Reminders screen
/// (design/screens/RemindersAll.dc.html, docs/SCREENMAP.md -> "Reminders
/// across cars"). The gate: two cars' reminders appear in one list with every
/// row naming its car; completing one leaves the other untouched; and creating
/// from the merged list makes the car an explicit choice (empty + required,
/// Save inert until picked - hard rule 13), while a car's own list arrives
/// filled and still changeable.
@MainActor
final class RemindersAllCarsUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(_ arguments: [String],
                        route: String = "remindersAll") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-homeResetDatabase", "-presentScreen", route] + arguments
        app.launch()
        return app
    }

    // MARK: - The merged list

    /// The whole point of the screen: TWO cars' attention rows are on one list,
    /// each naming its car - never a count of rows hiding that the second car
    /// is absent, and never a single-car garage.
    func testMergedListShowsBothCarsAttentionRowsEachNamingItsCar() {
        let app = launch(["-seedRemindersAll"])

        XCTAssertTrue(app.staticTexts["remindersAttentionHeader"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["remindersScheduledHeader"].exists,
                      "both groups render from the two-car seed")

        // The two attention rows, one per car.
        XCTAssertTrue(app.staticTexts["Insurance renewal"].exists)
        XCTAssertTrue(app.staticTexts["Oil change"].exists)

        // Both cars are represented BY NAME on their rows.
        XCTAssertTrue(app.staticTexts["Volvo V60"].exists,
                      "a merged row must name its car")
        XCTAssertTrue(app.staticTexts["Skoda Octavia"].exists,
                      "a merged row must name its car")

        // The scheduled group carries the other car's rows too.
        XCTAssertTrue(app.staticTexts["Winter tires"].exists)
        XCTAssertTrue(app.staticTexts["Inspection (TÜV)"].exists)
    }

    /// Completing the FIRST attention row (the seed's Skoda oil change, due
    /// soonest) must leave the OTHER car's attention row - and its car name -
    /// untouched on the merged list.
    func testCompletingOneCarAttentionLeavesTheOtherCarUntouched() {
        let app = launch(["-seedRemindersAll"])

        XCTAssertTrue(app.staticTexts["remindersAttentionHeader"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Oil change"].exists)

        // Attention rows sort by urgency: Oil change (+3 d, Skoda) before
        // Insurance renewal (+12 d, Volvo), so the first complete affordance
        // belongs to the Skoda row.
        let complete = app.buttons["reminderCompleteButton"].firstMatch
        XCTAssertTrue(complete.waitForExistence(timeout: 5))
        complete.tap()

        let skip = app.buttons["reminderCompleteSkip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 5))
        skip.tap()

        // The completed (non-recurring) Skoda attention row is gone...
        XCTAssertTrue(app.staticTexts["remindersAttentionHeader"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Oil change"].waitForExistence(timeout: 3),
                       "the completed attention row must leave the group")

        // ... and the Volvo row is untouched, still naming its car.
        XCTAssertTrue(app.staticTexts["Insurance renewal"].exists)
        XCTAssertTrue(app.staticTexts["Volvo V60"].exists)
    }

    // MARK: - The form's car field

    /// New reminder from the merged list: the car field arrives EMPTY and Save
    /// is inert until one is picked - the quiet guess hard rule 13 forbids
    /// (docs/SCREENMAP.md: "defaulting to the selected one is exactly the quiet
    /// guess hard rule 13 forbids"). The saved reminder returns to the merged
    /// list naming the car it was made for.
    func testNewReminderFromMergedMakesTheCarAnExplicitChoice() {
        let app = launch(["-seedRemindersAll"])

        let newButton = app.buttons["remindersAllNewReminderButton"]
        XCTAssertTrue(newButton.waitForExistence(timeout: 10))
        newButton.tap()

        let save = app.buttons["reminderFormSaveButton"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertFalse(save.isEnabled,
                       "Save must be inert until a car is picked")
        XCTAssertTrue(app.staticTexts["reminderFormCarRequiredHint"].exists,
                      "the empty car field must say a choice is required")

        // Fill everything except the car: Save must STAY inert - the car is
        // the missing required field, not the title or the date. (Date first,
        // while no keyboard is up, so the control is not covered.)
        app.buttons["reminderFormAddDateButton"].tap()
        let title = app.textFields["reminderFormTitleField"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        title.typeText("Brake check")
        XCTAssertFalse(save.isEnabled,
                       "Save stays inert while the car is unpicked")

        // Picking a car is what unlocks Save.
        let skoda = app.buttons["reminderFormCar_Skoda Octavia"]
        XCTAssertTrue(skoda.waitForExistence(timeout: 5))
        XCTAssertFalse(skoda.isSelected)
        skoda.tap()
        XCTAssertTrue(skoda.isSelected)
        XCTAssertTrue(save.isEnabled,
                      "Save unlocks the moment a car is picked")

        save.tap()

        // Back on the merged list, the saved reminder is there, on the car
        // that was chosen (the date defaults to today, so it is attention-due).
        XCTAssertTrue(app.staticTexts["remindersAttentionHeader"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Brake check"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Skoda Octavia"].exists,
                      "the merged list must still name the car on its rows")
    }

    /// Opened from a car's own list, the form arrives with THAT car chosen -
    /// a default input, not a fact - and the choice stays changeable (hard
    /// rule 13).
    func testFormFromCarsOwnListArrivesFilledAndChangeable() {
        let app = launch(["-seedRemindersAll"], route: "reminders")

        let newButton = app.buttons["remindersNewReminderButton"]
        XCTAssertTrue(newButton.waitForExistence(timeout: 10))
        newButton.tap()

        // The opener named a car (the per-car list's own), so it arrives
        // chosen...
        let volvo = app.buttons["reminderFormCar_Volvo V60"]
        XCTAssertTrue(volvo.waitForExistence(timeout: 5))
        XCTAssertTrue(volvo.isSelected,
                      "a car's own list must pre-fill its car")

        // ... and the second car is a peer choice, never locked out.
        let skoda = app.buttons["reminderFormCar_Skoda Octavia"]
        XCTAssertTrue(skoda.exists)
        XCTAssertFalse(skoda.isSelected)

        skoda.tap()
        XCTAssertTrue(skoda.isSelected,
                      "the pre-filled car must stay changeable (hard rule 13)")
        XCTAssertFalse(volvo.isSelected)
    }
}

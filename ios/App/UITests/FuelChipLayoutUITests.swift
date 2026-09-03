import XCTest

/// RV.28 (reported by the product owner with a screenshot): the fuel chips in
/// the multi-kind chooser must PACK, not distribute. The row rendered
/// `92 95 98` strung out with large gaps and `100 +` wrapped onto a second row
/// while all five chips fit on one line at their natural size, because
/// `LazyVGrid(.adaptive(minimum: 58))` computed how many columns fit and then
/// STRETCHED them to fill the width. A chip therefore kept whatever width the
/// container forced and the trailing chips wrapped even when room remained.
///
/// The regression this suite must never re-admit is the one that made the grid
/// adaptive in the first place: `minimum: 44` squeezed "100" and "LPG" until
/// their labels broke INSIDE the capsule. So the assertions here are FRAMES,
/// not existence - the chips existed throughout the bug (the vacuous trap) -
/// and they check exactly the layout contract of `FuelChipFlow`:
///   1. chips sit on ONE row when they naturally fit (no distribute-vs-wrap);
///   2. the block's trailing edge aligns with the Full-tank toggle below;
///   3. each chip keeps the width its label measures at (never compressed to a
///      uniform column, which is the squeeze that breaks "100"/"LPG").
/// The three are asserted on both screens that host the chooser: Confirm
/// (`ManualFillUpView`) and Edit entry (`EditEntryView`) - the same component,
/// but two real call sites a fix could diverge on.
@MainActor
final class FuelChipLayoutUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Launch helpers

    /// The Confirm fuel row: the default seed is a 95 car, which offers ALL
    /// four petrol grades as chips (grades share a tank, hard rule 13) plus the
    /// "+" correction menu - the exact `92 95 98 ... 100 +` set of the report.
    private func launchConfirmFuelRow() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-seedVehicleForUITests", "-homeResetDatabase"]
        app.launch()
        XCTAssertTrue(app.buttons["typeItButton"].waitForExistence(timeout: 10))
        app.buttons["typeItButton"].tap()
        XCTAssertTrue(app.textFields["manualFillUpTotalField"].waitForExistence(timeout: 5))
        return app
    }

    /// The Edit entry fuel row: a petrol car (offers all four grades, the same
    /// set as Confirm) whose newest fill opens in Edit. The `-seedHomeEditHistory`
    /// history is the seed the EditEntryUITests drive against - the chooser here
    /// is the same `ManualFillUpFuelFullCard`, so the three layout assertions
    /// must hold on this screen too.
    private func launchEditFuelRow() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-homeResetDatabase", "-seedHomeEditHistory"]
        app.launch()
        let row = app.buttons.matching(identifier: "logEntryButton").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        XCTAssertTrue(app.textFields["manualFillUpTotalField"].waitForExistence(timeout: 5))
        return app
    }

    /// Bring the chips into the viewport before reading frames: XCUITest frame
    /// values are trustworthy only after a layout pass has settled (a fuel row
    /// still below the fold is reported at stale coordinates). The save bar is
    /// a `safeAreaInset` the accessibility tree does not model, so "hittable"
    /// alone is not enough - mirror the scrollClearOfSaveBar geometry of the
    /// other suites.
    private func scrollChipsIntoView(_ app: XCUIApplication,
                                     _ chips: [XCUIElement],
                                     saveBarId: String) {
        let anchor = chips.first ?? app.buttons["manualFillUpFuelMoreMenu"]
        let bar = app.buttons[saveBarId]
        var scrolls = 0
        while scrolls < 8 {
            let barTop = bar.exists ? bar.frame.minY : app.windows.firstMatch.frame.maxY
            if anchor.isHittable && anchor.frame.maxY < barTop - 8 { return }
            guard let scroll = app.scrollViews.allElementsBoundByIndex.first(where: { $0.isHittable })
            else { return }
            let from = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
            let to = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
            from.press(forDuration: 0.05, thenDragTo: to)
            scrolls += 1
        }
    }

    /// The four grade chips of a petrol car, in render order.
    private func gradeChips(_ app: XCUIApplication) -> [XCUIElement] {
        ["petrol92", "petrol95", "petrol98", "petrol100"].map {
            app.buttons["manualFillUpFuelKind_\($0)"]
        }
    }

    // MARK: - The three layout assertions, one place

    /// 1. Every chip of the chooser sits on ONE row. 2. The block's trailing
    /// edge (the last chip, the "+" menu when present) aligns with the
    /// Full-tank toggle's trailing edge. 3. The widest chips are wider than the
    /// two-digit grade chips - i.e. each capsule carries its label's natural
    /// width, never a uniform column width (the squeeze that breaks labels).
    /// `context` names the screen for the failure messages.
    private func assertChipsPackAndAlign(app: XCUIApplication,
                                         context: String,
                                         saveBarId: String) {
        let chips = gradeChips(app)
        for chip in chips {
            XCTAssertTrue(chip.waitForExistence(timeout: 5),
                          "\(context): chip \(chip.identifier) must render")
        }
        let more = app.buttons["manualFillUpFuelMoreMenu"]
        XCTAssertTrue(more.exists, "\(context): the '+' correction menu must render")
        let toggle = app.switches["manualFillUpIsFullToggle"]
        XCTAssertTrue(toggle.exists, "\(context): the Full-tank toggle must render")

        scrollChipsIntoView(app, chips + [more], saveBarId: saveBarId)

        // The "100" (3 digits) and "LPG" (3 letters) chips must be measured at
        // their natural width: strictly wider than a two-digit grade chip.
        // Under the old adaptive grid every chip in a row shared one stretched
        // column width, so these were EQUAL - the comparison is the discriminator.
        let w92 = chips[0].frame.width
        let w98 = chips[2].frame.width
        let w100 = chips[3].frame.width
        XCTAssertEqual(w92, w98, accuracy: 1.0,
                       "\(context): same two-digit labels must measure equal at natural size")
        XCTAssertGreaterThan(w100, w98 + 2,
                             "\(context): '100' must keep its natural width (3 digits > 2), got \(w100) vs \(w98)")

        // 1. One row: every chip and the '+' share a minY (tolerance 1pt - the
        //    capsules sit on the same baseline).
        let ys = (chips + [more]).map { $0.frame.minY }
        let minY = ys.min() ?? 0
        let maxY = ys.max() ?? 0
        XCTAssertLessThanOrEqual(maxY - minY, 1.0,
                                 "\(context): all chips must pack onto ONE row, minY span \(maxY - minY)")

        // 2. The block is trailing-aligned with the Full-tank toggle below.
        XCTAssertEqual(more.frame.maxX, toggle.frame.maxX, accuracy: 2.0,
                       "\(context): the chip block must align with the Full-tank toggle, "
                       + "chips end at \(more.frame.maxX), toggle at \(toggle.frame.maxX)")
    }

    // MARK: - Confirm manual fill-up

    /// The report's exact case: a four-grade car on the Confirm row. All five
    /// elements (four grade chips + "+") fit on one row at natural width and
    /// must end flush with the Full-tank toggle.
    func testConfirmFourGradeChipsPackOneRowAlignedWithToggle() {
        let app = launchConfirmFuelRow()
        assertChipsPackAndAlign(app: app, context: "Confirm",
                                saveBarId: "manualFillUpSaveButton")
    }

    /// The WIDEST realistic offer set (petrol + LPG: five grade chips + "+").
    /// Whatever rows they wrap onto, no capsule may be compressed to a uniform
    /// width - "LPG" and "100" must measure wider than the two-digit grades.
    /// The old grid stretched every chip in a row to one equal column, which is
    /// precisely the squeeze that broke labels; this pins it on the widest set.
    func testConfirmWidestSetKeepsEveryChipItsNaturalWidth() {
        let app = XCUIApplication()
        app.launchArguments = ["-seedVehicleForUITests", "-homeResetDatabase",
                               "-seedVehiclePetrolLPG"]
        app.launch()
        XCTAssertTrue(app.buttons["typeItButton"].waitForExistence(timeout: 10))
        app.buttons["typeItButton"].tap()
        XCTAssertTrue(app.textFields["manualFillUpTotalField"].waitForExistence(timeout: 5))

        let chips = gradeChips(app)
        let lpg = app.buttons["manualFillUpFuelKind_lpg"]
        for chip in chips + [lpg] {
            XCTAssertTrue(chip.waitForExistence(timeout: 5),
                          "Confirm(LPG): chip \(chip.identifier) must render")
        }
        let more = app.buttons["manualFillUpFuelMoreMenu"]
        XCTAssertTrue(more.exists)
        scrollChipsIntoView(app, chips + [lpg, more], saveBarId: "manualFillUpSaveButton")

        let w92 = chips[0].frame.width
        let w98 = chips[2].frame.width
        let w100 = chips[3].frame.width
        XCTAssertEqual(w92, w98, accuracy: 1.0)
        XCTAssertGreaterThan(w100, w98 + 2,
                             "'100' must keep its natural width on the widest set, got \(w100) vs \(w98)")
        XCTAssertGreaterThan(lpg.frame.width, w98 + 2,
                             "'LPG' must keep its natural width on the widest set, "
                             + "got \(lpg.frame.width) vs \(w98) - compressed equal columns is the RV.28 regression")
    }

    // MARK: - Edit entry (the second call site)

    /// The chooser is the SAME `ManualFillUpFuelFullCard`, so Edit entry must
    /// show the identical packed, trailing-aligned row - a fix applied to only
    /// one screen would leave the report's bug half-shipped.
    func testEditEntryChooserPacksOneRowAlignedWithToggle() {
        let app = launchEditFuelRow()
        assertChipsPackAndAlign(app: app, context: "Edit",
                                saveBarId: "editEntrySaveButton")
    }
}

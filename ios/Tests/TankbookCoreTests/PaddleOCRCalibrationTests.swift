import CoreGraphics
import Foundation
import Testing
@testable import TankbookCore

// P4.13 - the coordinate-conversion calibration. This is the test that makes
// every other number in the task trustworthy: if the PaddleOCR -> Vision box
// mapping inverts the page, the parser's geometric rules fail silently and Arm A
// scores badly for reasons that have nothing to do with recognition quality.
//
// The task's chosen fixture, `receipt-001`, is a Latin-script (Estonian) Circle K
// receipt, not a Russian one - a fact the sweep surfaced, not assumed. Off-the-
// shelf PaddleOCR detects it with coarser line segmentation than Vision
// (merging `1,869 EUR/L` into one line where Vision emits `1,869` and `EUR/L`
// separately), so the parser's `/L`-label-below rule cannot resolve the price
// from PaddleOCR output regardless of coordinates. That is a segmentation
// finding, not a conversion bug - and it is pinned here so it cannot be mistaken
// for one. The conversion itself is proven two ways below: the formula directly,
// and the real `receipt-001` boxes' top-to-bottom order.

@Suite("P4.13 PaddleOCR coordinate conversion - calibration")
struct PaddleOCRCalibrationTests {

    private static let fixture: PaddleOCRCalibrationFixture = {
        let url = PaddleOCRCorpus.abRoot.appendingPathComponent("paddleocr-a-lines-receipt-001.json")
        let data = try! Data(contentsOf: url)
        return try! JSONDecoder().decode(PaddleOCRCalibrationFixture.self, from: data)
    }()

    private static func rawLine(_ needle: String) -> PaddleOCRRawLine {
        fixture.lines.first { $0.text.contains(needle) }!
    }

    // MARK: - 1. The formula, directly

    /// PaddleOCR's `[x0, y0, x1, y1]` is top-left-origin pixels; Vision's box is
    /// bottom-left-origin normalised. The mapping is `x/width` and
    /// `y_norm = 1 - (y_px / height)` with the rect origin at its bottom edge.
    @Test("a pixel box maps to Vision normalised space with y flipped")
    func pixelBoxMapsToVisionSpace() {
        // A 10x100 box at x=0..10, y=0..100 in a 100x200 image (top-left origin):
        // the box's TOP edge is y_px=0, BOTTOM edge y_px=100.
        let box = PaddleOCRCoordinate.visionBox(
            paddleBox: [0, 0, 10, 100], width: 100, height: 200
        )
        #expect(abs(box.minX - 0.0) < 1e-9)
        #expect(abs(box.width - 0.1) < 1e-9)
        // Bottom edge in Vision space: 1 - 100/200 = 0.5.
        #expect(abs(box.minY - 0.5) < 1e-9)
        #expect(abs(box.height - 0.5) < 1e-9)
        // Its centre: midY = 0.5 + 0.25 = 0.75.
        #expect(abs(box.midY - 0.75) < 1e-9)
    }

    @Test("a box higher on the page gets a higher Vision midY")
    func higherOnPageIsHigherMidY() {
        // Top box (y_px 0..10) vs bottom box (y_px 190..200) in a 200px image.
        let top = PaddleOCRCoordinate.visionBox(paddleBox: [0, 0, 10, 10], width: 100, height: 200)
        let bottom = PaddleOCRCoordinate.visionBox(paddleBox: [0, 190, 10, 200], width: 100, height: 200)
        #expect(top.midY > bottom.midY)
        #expect(abs(top.midY - (1.0 - 5.0 / 200)) < 1e-9)
        #expect(abs(bottom.midY - (1.0 - 195.0 / 200)) < 1e-9)
    }

    // MARK: - 2. Real `receipt-001` boxes: the flip is what preserves reading order

    /// In the receipt's own pixels, `Kogus` (the column header) sits above the
    /// quantity `67,00.`. A correct conversion keeps that order; the naive
    /// (unflipped) mapping inverts it - the exact trap `docs/EXTRACTION.md`
    /// describes for `loneMarkers`.
    @Test("receipt-001: correct conversion keeps Kogus above the quantity line")
    func receipt001ReadingOrder() {
        let kogus = Self.rawLine("Kogus")
        let qty = Self.rawLine("67,00")
        let width = Self.fixture.width
        let height = Self.fixture.height

        let kogusBox = PaddleOCRCoordinate.visionBox(paddleBox: kogus.box!, width: width, height: height)
        let qtyBox = PaddleOCRCoordinate.visionBox(paddleBox: qty.box!, width: width, height: height)

        #expect(kogusBox.midY > qtyBox.midY, "Kogus must sit above the quantity after the flip")

        // And the sorted output reads top-to-bottom.
        let lines = PaddleOCRCoordinate.lines(from: Self.fixture.lines, width: width, height: height)
        let kogusIndex = lines.firstIndex { $0.text.contains("Kogus") }!
        let qtyIndex = lines.firstIndex { $0.text.contains("67,00") }!
        #expect(kogusIndex < qtyIndex)
    }

    @Test("receipt-001: a naive unflipped y inverts the page")
    func naiveFlipInvertsThePage() {
        // Reproduce the wrong mapping - y = minY/height, origin top-left - and
        // show it puts Kogus BELOW the quantity. This is the failure the flip
        // exists to prevent.
        func naiveMidY(_ box: [Double]) -> Double {
            (box[1] + box[3]) / 2 / Self.fixture.height
        }
        let kogusMidY = naiveMidY(Self.rawLine("Kogus").box!)
        let qtyMidY = naiveMidY(Self.rawLine("67,00").box!)
        #expect(kogusMidY < qtyMidY, "the naive mapping must invert the order - that is the trap")
    }

    // MARK: - 3. The segmentation finding, pinned (not a conversion bug)

    /// PaddleOCR merges the price value and its `/L` unit label into one line
    /// (`1,869 EUR/L`), where Vision emits `1,869` and `EUR/L` separately. The
    /// parser's `loneMarkers` rule finds the price "directly below its /L label"
    /// and therefore cannot resolve it from PaddleOCR output. Asserting this
    /// explicitly keeps a future reader from blaming the coordinates.
    @Test("receipt-001: PaddleOCR merges the /L label and its value into one line")
    func paddleOCRMergesPriceAndUnitLabel() {
        let price = Self.rawLine("1,869")
        #expect(price.text.contains("/L") || price.text.contains("/l"), "price and /L label are one line")
        // And there is no separate "/L" label line for the value to sit under.
        let separateLabel = Self.fixture.lines.first { $0.text.trimmingCharacters(in: .whitespaces).uppercased() == "EUR/L" }
        #expect(separateLabel == nil, "PaddleOCR emits no standalone EUR/L label line")
    }
}

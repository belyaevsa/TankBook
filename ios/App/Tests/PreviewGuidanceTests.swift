import CoreGraphics
import UIKit
import XCTest
import TankbookCore
@testable import Tankbook

/// PU.40b - the preview guidance's state machine. No camera: synthetic rows in
/// the detector's own shape, and the production rescue, so the states are
/// pinned to the same rules the capture path decides with.
@MainActor
final class PreviewGuidanceTests: XCTestCase {

    private func row(x0: CGFloat, x1: CGFloat, y0: CGFloat, y1: CGFloat,
                     confidence: Double) -> PumpRowDetector.Row {
        PumpRowDetector.Row(quad: [CGPoint(x: x0, y: y0), CGPoint(x: x1, y: y0),
                                   CGPoint(x: x1, y: y1), CGPoint(x: x0, y: y1)],
                            confidence: confidence)
    }

    // MARK: - The four states

    func testTwoStackedRowsAreReady() {
        let rows = [row(x0: 0.1, x1: 0.6, y0: 0.10, y1: 0.15, confidence: 0.4),
                    row(x0: 0.1, x1: 0.6, y0: 0.20, y1: 0.25, confidence: 0.4)]
        XCTAssertEqual(CaptureGuidanceState.classify(rows: rows), .ready)
    }

    func testOneSizedRowIsOneRow() {
        let rows = [row(x0: 0.1, x1: 0.6, y0: 0.10, y1: 0.15, confidence: 0.9)]
        XCTAssertEqual(CaptureGuidanceState.classify(rows: rows), .oneRow)
    }

    /// Two rows that pass the size rule but sit side by side (a keypad beside a
    /// display, or a display only half in frame) are NOT ready - the stacking
    /// rule is what separates a display from two unrelated number rows.
    func testTwoSideBySideRowsAreOneRowNotReady() {
        let rows = [row(x0: 0.10, x1: 0.40, y0: 0.10, y1: 0.15, confidence: 0.6),
                    row(x0: 0.55, x1: 0.85, y0: 0.10, y1: 0.15, confidence: 0.6)]
        XCTAssertEqual(CaptureGuidanceState.classify(rows: rows), .oneRow)
    }

    func testRowsUnderTheSizeRuleAreTooSmall() {
        let rows = [row(x0: 0.1, x1: 0.2, y0: 0.10, y1: 0.12, confidence: 0.9),
                    row(x0: 0.1, x1: 0.2, y0: 0.14, y1: 0.16, confidence: 0.9)]
        XCTAssertEqual(CaptureGuidanceState.classify(rows: rows), .tooSmall)
    }

    func testNoRowsIsSearching() {
        XCTAssertEqual(CaptureGuidanceState.classify(rows: []), .searching)
    }

    // MARK: - The rescue

    /// A row below the confidence cut is not a display row on its own; the
    /// reader rescues it only when it stacks beside a passing row. The state
    /// machine reads the rescued set, so this pins the rescue into the hint.
    func testARowBelowTheRescueCutCountsOnlyWhenRescued() {
        let high = row(x0: 0.1, x1: 0.6, y0: 0.10, y1: 0.15, confidence: 0.6)
        let low = row(x0: 0.1, x1: 0.6, y0: 0.20, y1: 0.25, confidence: 0.2)

        let alone = PumpDisplayCapture.rescuedRows([low])
        XCTAssertTrue(alone.isEmpty, "a below-cut row with nothing to stack under is dropped")
        XCTAssertEqual(CaptureGuidanceState.classify(rows: alone), .searching,
                       "a below-cut row must not read as ready on its own")

        let rescued = PumpDisplayCapture.rescuedRows([high, low])
        XCTAssertEqual(rescued.count, 2, "the low row stacks under the passing one and is rescued")
        XCTAssertEqual(CaptureGuidanceState.classify(rows: rescued), .ready)
    }

    // MARK: - The debounce

    /// A new state must be seen for three consecutive frames before it is
    /// published; two frames leave the previous state standing.
    func testDebounceHoldsAStateForThreeFrames() {
        var debouncer = GuidanceDebouncer()
        XCTAssertEqual(debouncer.observe(.ready), .searching)
        XCTAssertEqual(debouncer.observe(.ready), .searching,
                       "two frames are not enough to publish")
        XCTAssertEqual(debouncer.observe(.ready), .ready,
                       "the third consecutive frame publishes")
    }

    /// A frame that agrees with the published state resets the run, so a
    /// one-frame excursion between two stable frames never publishes.
    func testDebounceResetsOnThePublishedState() {
        var debouncer = GuidanceDebouncer()
        XCTAssertEqual(debouncer.observe(.ready), .searching)
        XCTAssertEqual(debouncer.observe(.ready), .searching)
        XCTAssertEqual(debouncer.observe(.searching), .searching, "back to the published state")
        XCTAssertEqual(debouncer.observe(.ready), .searching, "the run starts over")
        XCTAssertEqual(debouncer.observe(.ready), .searching)
        XCTAssertEqual(debouncer.observe(.ready), .ready)
    }

    // MARK: - The published overlay

    /// Only the `ready` state draws the outline, and only the rows that pass
    /// the size rule - a rescued small row is not outlined.
    func testOverlayRectsOnlyForReadySizedRows() {
        let guidance = PreviewGuidance()
        let big = row(x0: 0.1, x1: 0.6, y0: 0.10, y1: 0.15, confidence: 0.4)
        let small = row(x0: 0.1, x1: 0.2, y0: 0.20, y1: 0.22, confidence: 0.4)
        guidance.observe(rows: [big, small], frameSize: CGSize(width: 100, height: 200), analysisMs: 4)
        XCTAssertEqual(guidance.state, .searching)
        XCTAssertTrue(guidance.overlayRects.isEmpty)

        guidance.observe(rows: [big, small], frameSize: CGSize(width: 100, height: 200), analysisMs: 4)
        guidance.observe(rows: [big, small], frameSize: CGSize(width: 100, height: 200), analysisMs: 4)
        XCTAssertEqual(guidance.state, .oneRow, "two sized rows that do not stack are not ready")
        XCTAssertTrue(guidance.overlayRects.isEmpty)
        XCTAssertEqual(guidance.framesAnalysed, 3)
    }

    /// Ready: both passing rows are outlined, once the debounce publishes.
    func testReadyPublishesAnOutlinePerSizedRow() {
        let guidance = PreviewGuidance()
        let top = row(x0: 0.1, x1: 0.6, y0: 0.10, y1: 0.15, confidence: 0.4)
        let bottom = row(x0: 0.1, x1: 0.6, y0: 0.20, y1: 0.25, confidence: 0.4)
        for _ in 0..<GuidanceDebouncer.requiredFrames {
            guidance.observe(rows: [top, bottom], frameSize: CGSize(width: 100, height: 200), analysisMs: 5)
        }
        XCTAssertEqual(guidance.state, .ready)
        XCTAssertEqual(guidance.overlayRects.count, 2)
        XCTAssertEqual(guidance.lastAnalysisMs, 5)
        XCTAssertEqual(guidance.frameSize, CGSize(width: 100, height: 200))
    }

    // MARK: - The overlay geometry

    /// `.resizeAspectFill`: scaled to cover the view and centred, so a portrait
    /// frame on a portrait screen is cropped equally top and bottom.
    func testAspectFillCoversAndCentres() {
        let fit = CameraPreviewView.aspectFill(frameSize: CGSize(width: 100, height: 200),
                                               in: CGSize(width: 400, height: 400))
        XCTAssertEqual(fit, CGRect(x: 0, y: -200, width: 400, height: 800))
    }

    /// One thin outline per ready row, and clearing the rects removes them.
    func testOverlayDrawsOneLayerPerRect() {
        let view = CameraPreviewView()
        view.frame = CGRect(x: 0, y: 0, width: 400, height: 800)
        view.setOverlay([CGRect(x: 0.1, y: 0.2, width: 0.5, height: 0.1),
                         CGRect(x: 0.1, y: 0.4, width: 0.5, height: 0.1)],
                        frameSize: CGSize(width: 100, height: 200))
        let shapes = view.layer.sublayers?.compactMap { $0 as? CAShapeLayer } ?? []
        XCTAssertEqual(shapes.count, 2)
        XCTAssertEqual(shapes.first?.lineWidth, 2)

        view.setOverlay([], frameSize: .zero)
        let after = view.layer.sublayers?.compactMap { $0 as? CAShapeLayer } ?? []
        XCTAssertTrue(after.isEmpty, "a search with no row must draw no outline")
    }
}

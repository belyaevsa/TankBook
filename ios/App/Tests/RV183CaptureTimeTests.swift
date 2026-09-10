import Foundation
import XCTest
import TankbookCore
@testable import Tankbook

/// RV.183 L1 - the recognised page's caption is the CAPTURE instant
/// (`Attachment.createdAt`), never the receipt's printed date
/// (`Attachment.extractedTimestamp`, a date-only fact). Both are `Date`, so a
/// test that only asserts "a date renders" passes on the defect; the first test
/// here asserts the SOURCE, and the formatter test pins the value it renders.
///
/// The second half pins the rule that made the defect visible: a date-only value
/// never renders a time component (docs/DESIGN.md -> Typography).
final class RV183CaptureTimeTests: XCTestCase {

    // MARK: - The caption's source (fails on the defect)

    /// The caption must be built from `createdAt`. The source scan is
    /// deliberate: the view is a SwiftUI `View` with no unit-test renderer, and
    /// a runtime assertion on the rendered string cannot see WHICH field fed it.
    func testCaptionReadsTheCaptureInstantNotTheReceiptsPrintedDate() throws {
        let text = try Self.recognisedViewSource()
        XCTAssertTrue(text.contains("capturedLine(createdAt)"),
                      "the caption must be built from Attachment.createdAt")
        XCTAssertFalse(text.contains("capturedLine(extractedTimestamp)"),
                       "the caption must never be built from the receipt's printed date")
        XCTAssertTrue(text.contains("let createdAt: Date"),
                      "the view must take the capture instant")
    }

    // MARK: - The formatter

    /// The capture instant is a real moment, so its time component IS rendered -
    /// this is the mirror of the date-only rule, and a caption that lost its
    /// time would fail here.
    func testCapturedLineCarriesTheCaptureInstant() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let captured = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 9, day: 10, hour: 14, minute: 32)))

        let line = AttachmentRecognisedView.capturedLine(captured)
        let stamp = captured.formatted(.dateTime.month(.abbreviated).day().hour().minute())
        XCTAssertTrue(line.contains(stamp),
                      "the caption must carry the capture instant: \(line)")
        XCTAssertTrue(line.contains("32"),
                      "the capture minute must survive, not be flattened to 00:00: \(line)")
    }

    // MARK: - A date-only value never renders a time

    /// The receipt's printed date has no time component. The `Date` row must
    /// render it date-only; if a formatter appends `.hour().minute()` the
    /// rendered string equals the date+time rendering, which this catches.
    func testDateOnlyValueNeverRendersATimeComponent() throws {
        let raw = "08.09.2026"
        let parsed = try XCTUnwrap(ConfirmDate.parse(raw))
        let meta = ExtractionMeta(fields: [
            .date: FieldExtraction(cropRect: nil, confidence: 0.9, userCorrected: false,
                                   value: .text(raw)),
        ], pipeline: "test")

        let rows = AttachmentValueFormat.rows(from: meta)
        guard case .plain(let rendered)? = rows.first(where: { $0.ref == .date })?.value else {
            return XCTFail("the date row must render as plain text")
        }
        let dateOnly = parsed.formatted(.dateTime.month(.abbreviated).day().year())
        let withTime = parsed.formatted(.dateTime.month(.abbreviated).day().year().hour().minute())
        XCTAssertEqual(rendered, dateOnly, "a date-only value must render date-only")
        XCTAssertNotEqual(rendered, withTime,
                          "a date-only value must never render a time component")
        XCTAssertEqual(rendered, AttachmentValueFormat.dateOnly(parsed))
    }

    // MARK: - Source tree

    private static func recognisedViewSource() throws -> String {
        let thisFile = URL(fileURLWithPath: #filePath).standardizedFileURL
        var candidate = thisFile.deletingLastPathComponent() // ios/App/Tests
        for _ in 0..<3 { candidate = candidate.deletingLastPathComponent() } // -> repo root
        let url = candidate.appendingPathComponent(
            "ios/App/Sources/EditEntry/AttachmentRecognisedView.swift")
        return try String(contentsOf: url, encoding: .utf8)
    }
}

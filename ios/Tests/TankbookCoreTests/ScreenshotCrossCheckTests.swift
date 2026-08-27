import Foundation
import Testing
@testable import TankbookCore

#if canImport(Vision)
import Vision

// P2.12 - the real OCR over the five Circle K screenshots and receipt-038.
// The pure evaluator's semantics live in `CrossCheckTests`; this suite runs the
// ACTUAL pipeline (Vision -> FuelExtractor -> cross-check) so "reconciled" is
// asserted on the values the parser really resolved, not on hand-built lines.
// Same Vision configuration as the L5 ratchet.

@Suite("Screenshot cross-check (P2.12, L5)")
struct ScreenshotCrossCheckTests {

    private static let repoRoot = URL(fileURLWithPath: #filePath).standardizedFileURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    private static let fixturesRoot = repoRoot
        .appendingPathComponent("Spike/ReceiptSpike/fixtures")
    private static let languages = ["en-US", "de-DE", "pl-PL", "cs-CZ", "ru-RU"]

    private func dec(_ string: String) -> Decimal { Decimal(string: string)! }

    private func extract(_ filename: String) throws -> FuelExtraction {
        let image = Self.fixturesRoot
            .appendingPathComponent("screenshots").appendingPathComponent(filename)
        let ocr = try VisionTextRecognizer.recognizeText(in: image, languages: Self.languages)
        return FuelExtractor().extract(lines: ocr)
    }

    private func expectReconciled(_ extraction: FuelExtraction, residual: String,
                                  discountLine: String,
                                  source: SourceLocation = #_sourceLocation) {
        guard case .reconciled(let actualResidual, let actualDiscount) = extraction.crossCheck else {
            Issue.record("expected reconciled, got \(extraction.crossCheck)", sourceLocation: source)
            return
        }
        #expect(abs(actualResidual - dec(residual)) < dec("0.005"), sourceLocation: source)
        #expect(abs(actualDiscount - dec(discountLine)) < dec("0.005"), sourceLocation: source)
    }

    // MARK: - the five Circle K screenshots

    @Test("screenshot-004: 67 x 1.884 reconciles by the printed 1.01 discount")
    func screenshot004Reconciles() throws {
        let result = try extract("screenshot-004-circlek-jarvevana-ee-diesel.png")
        #expect(abs((result.liters ?? 0) - 67.00) < 0.005)
        #expect(abs((result.unitPrice ?? 0) - 1.884) < 0.005)
        #expect(abs((result.total ?? 0) - 125.22) < 0.005)
        expectReconciled(result, residual: "1.01", discountLine: "1.01")
    }

    @Test("screenshot-005: 58.01 x 2.159 reconciles by the printed 4.06 discount")
    func screenshot005Reconciles() throws {
        let result = try extract("screenshot-005-circlek-garliava-lt-diesel.png")
        #expect(abs((result.liters ?? 0) - 58.01) < 0.005)
        #expect(abs((result.unitPrice ?? 0) - 2.159) < 0.005)
        #expect(abs((result.total ?? 0) - 121.18) < 0.005)
        expectReconciled(result, residual: "4.06", discountLine: "4.06")
    }

    @Test("screenshot-006: 68 x 1.799 reconciles by the printed 1.02 discount")
    func screenshot006Reconciles() throws {
        let result = try extract("screenshot-006-circlek-sikupilli-ee-diesel.png")
        #expect(abs((result.liters ?? 0) - 68.00) < 0.005)
        #expect(abs((result.unitPrice ?? 0) - 1.799) < 0.005)
        #expect(abs((result.total ?? 0) - 121.31) < 0.005)
        expectReconciled(result, residual: "1.02", discountLine: "1.02")
    }

    @Test("screenshot-007: 64 x 1.614 reconciles by the printed 1.92 discount")
    func screenshot007Reconciles() throws {
        let result = try extract("screenshot-007-circlek-jarvevana-ee-diesel-jun.png")
        #expect(abs((result.liters ?? 0) - 64.00) < 0.005)
        #expect(abs((result.unitPrice ?? 0) - 1.614) < 0.005)
        #expect(abs((result.total ?? 0) - 101.38) < 0.005)
        expectReconciled(result, residual: "1.92", discountLine: "1.92")
    }

    @Test("screenshot-008: the fuel line 112.63 reconciles as the fuel's share of the 3.17 discount")
    func screenshot008Reconciles() throws {
        let result = try extract("screenshot-008-circlek-jugla-lv-mixed.png")
        #expect(abs((result.liters ?? 0) - 59.78) < 0.005)
        #expect(abs((result.unitPrice ?? 0) - 1.924) < 0.005)
        // Hard rule 4: the fuel amount is the fuel line, never the grand total.
        #expect(abs((result.total ?? 0) - 112.63) < 0.005)
        #expect(abs((result.total ?? 0) - 122.99) >= 0.005)
        // product 115.02 + shop list 11.14 == 122.99 + 3.17: the residual 2.39
        // is the fuel's share of the printed discount.
        expectReconciled(result, residual: "2.39", discountLine: "3.17")
    }

    // MARK: - receipt-038

    @Test("receipt-038: a printed discount that does not explain the total is never reconciled")
    func receipt038IsNotReconciled() throws {
        // The paper receipt prints `EXTRA SOODUS -0,23 EUR` beneath the item
        // while KOKKU still reads 79,32 - the discount is NOT subtracted from
        // the total. With the ground-truth triple the outcome is a lock (the
        // product 45,22 x 1,754 = 79,32 equals the total); the parser currently
        // leaves the price and total unresolved, so the live outcome is
        // `.notApplicable`. Either way, a discount line existing must never
        // produce a reconciled.
        let image = Self.fixturesRoot
            .appendingPathComponent("receipts")
            .appendingPathComponent("receipt-038-circlek-sikupilli-95e0-pump8-ee.jpg")
        let ocr = try VisionTextRecognizer.recognizeText(in: image, languages: Self.languages)
        let result = FuelExtractor().extract(lines: ocr)

        if case .reconciled = result.crossCheck {
            Issue.record("receipt-038 must never reconcile; got \(result.crossCheck)")
        }
        // The live parser resolves the volume but not price/total -> no triple.
        #expect(result.liters == 45.22)
        #expect(result.crossCheck == .notApplicable)

        // The honest outcome with the ground-truth triple: lock, not reconciled.
        let outcome = ExtractionCrossCheck.evaluate(liters: 45.22, unitPrice: 1.754,
                                                    total: 79.32, lines: ocr)
        #expect(outcome == .lock, "got \(outcome)")
    }
}
#endif

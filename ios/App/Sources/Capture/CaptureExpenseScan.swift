import SwiftUI
import TankbookCore
import UIKit

// MARK: - RV.62 / RV.200 the expense capture path

/// The Expense-mode scan exit from the RV.5 review's "Use this". Lives in its
/// own file because `CaptureView.swift` is at its file-length limit; the two
/// members it reaches (`activeSheet`, `coverDismissBeat`) are internal rather
/// than private, the same split `CaptureFillUpScan.swift` made.
extension CaptureView {
    /// An Expense-mode capture: the same frame and the same `CapturePipeline`
    /// as any receipt - but only total / currency / date may reach the expense
    /// form's VALUE fields. A shop receipt is not a fuel receipt: liters, unit
    /// price and fuel kind are meaningless on it, and `ExpensePrefillBuilder`
    /// (core, L1) enforces that boundary - nothing here decides what crosses, it
    /// only hands the mapping's result to ExpenseEntry through the shared
    /// session and opens the expense sheet. A scan that resolves nothing writes
    /// an all-nil prefill, so the form opens empty, never an error (hard rule 7).
    ///
    /// RV.200: the scan's own lines also name the KIND of expense when they say
    /// so - a parking ticket, a toll, a car wash - and that suggestion rides the
    /// same session's `pendingPreset` into the form's editable category field.
    /// It is a suggestion, never a fact (hard rule 13), and an unrecognised kind
    /// leaves `pendingPreset` nil so the form opens at its default and says
    /// nothing. The inference reads the OCR lines (the extractor's INPUT), never
    /// the extraction it already produced.
    ///
    /// PJ.28: the photograph travels alongside the values (`pendingCapture`),
    /// so the save that follows this open persists the receipt it was read
    /// from instead of throwing the image away.
    ///
    /// RV.215: the read is DEFERRED. The form opens on whatever is available;
    /// a read that finishes before the save fills it, and one that finishes
    /// after `markSaved` becomes an inbox item through the ONE policy
    /// (`AppInbox.recordLateGatewayAnswer`), never a second producer.
    ///
    /// RV.243: the photograph is staged NOW, before the read, so the save keeps
    /// the receipt even when the read is still in flight (hard rule 8). The read
    /// only enriches the same capture with the values it resolves.
    func acceptExpenseScan(_ image: UIImage) async {
        let session = expenseSession
        let inbox = self.inbox
        session.start(
            image: image,
            work: { await self.expenseScanOutcome(from: image) },
            onAnswer: { outcome in
                session.pendingPrefill = outcome.prefill
                session.pendingPreset = outcome.preset
                session.pendingCapture = outcome.capture
            },
            onSavedAnswer: { outcome, entryID in
                inbox.recordLateGatewayAnswer(.expense(outcome.recognition), entryID: entryID)
            })
        // The cover beat still separates the review's dismissal from the sheet's
        // presentation; a seeded (fast) read completes within it, so the form
        // opens pre-filled exactly as before.
        try? await Task.sleep(for: Self.coverDismissBeat)
        activeSheet = .manualForm(.expense)
    }

    /// Runs the recognition an Expense-mode scan shares with the fill-up path
    /// and shapes both halves of the outcome: the pre-fill the open form takes
    /// and the recognition a late read offers (RV.215). `CapturePipeline` is the
    /// FILL-UP OCR, and that is deliberate here: its assembler is what resolves
    /// total, currency and date on a receipt; the fuel-specific fields it also
    /// resolves are dropped by the prefill builder, never carried. The
    /// photograph and the raw OCR lines are kept for the save's receipt
    /// attachment (PJ.28).
    private func expenseScanOutcome(from image: UIImage) async -> ExpenseScanOutcome {
        let capture: ExpenseScanCapture
        #if DEBUG
        // DEBUG/test-only (`ExpenseScanTestSeed`): a canned recognition lets a
        // UI test assert what the user SEES without OCR over a corpus image.
        // It substitutes only the pipeline's output - the session hand-off and
        // the form's apply path below are exactly the shipped ones.
        if let seeded = ExpenseScanTestSeed.extraction(
            from: ProcessInfo.processInfo.arguments) {
            if let delay = ExpenseScanTestSeed.delay(from: ProcessInfo.processInfo.arguments) {
                try? await Task.sleep(for: delay)
            }
            capture = ExpenseScanCapture(
                image: image, extraction: seeded,
                ocrLines: ExpenseScanTestSeed.ocrLines(from: ProcessInfo.processInfo.arguments))
        } else {
            capture = await expenseCapture(from: image)
        }
        #else
        capture = await expenseCapture(from: image)
        #endif
        let preset = ExpenseCategoryInference.infer(from: capture.ocrLines)
        return ExpenseScanOutcome(
            prefill: ExpensePrefillBuilder.prefill(from: capture.extraction),
            preset: preset,
            capture: capture,
            recognition: ExpenseScanOutcome.recognition(from: capture.extraction, preset: preset))
    }

    /// Runs the recognition an Expense-mode scan shares with the fill-up path.
    private func expenseCapture(from image: UIImage) async -> ExpenseScanCapture {
        let vehicle = try? currentVehicle()
        let prefill = await CapturePipeline.process(
            image, source: .receipt,
            bandProvider: AppFuelPriceBand.provider(vehicleId: vehicle?.id))
        return ExpenseScanCapture(image: image,
                                  extraction: prefill.extraction ?? FuelExtraction(),
                                  ocrLines: prefill.ocrLines)
    }
}

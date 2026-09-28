import SwiftUI
import TankbookCore
import UIKit

// MARK: - RV.57 the fill-up capture path

/// The fill-up scan exit from the RV.5 review's "Use this": a canned
/// `FillUpScanTestSeed` (DEBUG, UI tests) or the real `CapturePipeline`.
/// Either way the entry view opens AT ONCE, pre-filled from the LOCAL parse
/// (RV.57) - the app never waits on the cloud to show the card. Lives in its
/// own file because `CaptureView.swift` is at its file-length limit; the three
/// members it reaches (`activeSheet`, `coverDismissBeat`, `currentVehicle()`)
/// are therefore internal rather than private.
extension CaptureView {
    func acceptFillUpScan(_ image: UIImage) async {
        #if DEBUG
        // The seeded path has no pipeline await to separate the cover's
        // dismissal from the sheet's presentation (see `coverDismissBeat`); the
        // real OCR's wait does that for free in production.
        if let seeded = FillUpScanTestSeed.extraction(from: ProcessInfo.processInfo.arguments) {
            try? await Task.sleep(for: Self.coverDismissBeat)
            activeSheet = .scanned(ConfirmPrefill(extraction: seeded, sourceImage: image))
            return
        }
        #endif
        let vehicle = try? currentVehicle()
        let prefill = await CapturePipeline.process(
            image,
            bandProvider: AppFuelPriceBand.provider(vehicleId: vehicle?.id),
            homeCurrency: vehicle?.homeCurrency)
        activeSheet = .scanned(prefill)
    }
}

// MARK: - The verify screen

/// A fill-up capture goes to the verify screen (`CaptureVerifyView`): the photo
/// with its recognised numbers, checked and corrected before Confirm opens. The
/// recognition starts the moment the photo exists, so the photo shows at once
/// and the fields fill in behind it. Expense and Service captures keep the
/// plain review: their documents carry line items, not three numbers.
extension CaptureView {
    func verifySession(for image: UIImage) -> CaptureVerifySession? {
        guard mode == .fillUpAuto || mode == .charge else { return nil }
        let vehicle = try? currentVehicle()
        let session = CaptureVerifySession(image: image, volumeUnit: vehicle?.units.volume ?? .l)
        session.start { await Self.recognize(image, vehicleId: vehicle?.id, homeCurrency: vehicle?.homeCurrency) }
        return session
    }

    private static func recognize(_ image: UIImage, vehicleId: UUID?, homeCurrency: CurrencyCode?) async -> ConfirmPrefill {
        #if DEBUG
        if let seeded = FillUpScanTestSeed.extraction(from: ProcessInfo.processInfo.arguments) {
            var prefill = ConfirmPrefill(extraction: seeded, sourceImage: image)
            FillUpScanTestSeed.decorate(&prefill, arguments: ProcessInfo.processInfo.arguments)
            return prefill
        }
        #endif
        return await CapturePipeline.process(image, bandProvider: AppFuelPriceBand.provider(vehicleId: vehicleId),
                                             homeCurrency: homeCurrency)
    }

    func verifyScreen(_ session: CaptureVerifySession) -> some View {
        CaptureVerifyView(
            session: session,
            onContinue: {
                let prefill = session.confirmedPrefill()
                reviewSubject = nil
                Task {
                    // The cover must be gone before the sheet presents.
                    try? await Task.sleep(for: Self.coverDismissBeat)
                    activeSheet = .scanned(prefill)
                }
            },
            onRetake: {
                #if EXPERIMENTS
                ScanRecorder.recordOutcome(session.prefill, result: .retaken)
                #endif
                session.cancel()
                reviewSubject = nil
            },
            onOpenAs: { form in openAs(form, image: session.image) })
    }

    /// RV.319: the verify screen's "Open as service / expense" - the photo
    /// goes to that form's own scan path, with its own reading and cloud
    /// call, exactly as if it had been captured in that mode.
    private func openAs(_ form: CaptureEntryForm, image: UIImage) {
        reviewSubject = nil
        switch form {
        case .service:
            mode = .service
            scanServiceInvoice([image])
        case .expense:
            mode = .expense
            Task {
                try? await Task.sleep(for: Self.coverDismissBeat)
                await acceptExpenseScan(image)
            }
        case .fillUp:
            break
        }
    }
}


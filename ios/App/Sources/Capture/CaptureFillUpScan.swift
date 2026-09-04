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
            image, source: .receipt,
            bandProvider: AppFuelPriceBand.provider(vehicleId: vehicle?.id))
        activeSheet = .scanned(prefill)
    }
}

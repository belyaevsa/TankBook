import SwiftUI
import TankbookCore
import UIKit

/// PJ.42 - "No receipt to hand? Try a sample": the bundled sample receipt run
/// through the real reader on the real verify screen, so a first-time user sees
/// what a scan does before they have a receipt. It ends on "Done – now try your
/// own" and SAVES NOTHING - no entry, no photo, no sync record (product owner,
/// 2026-10-01). The reader is on-device only (`CapturePipeline` makes no network
/// call), so the sample works offline and never reaches the cloud reader.
struct DemoReceiptView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var session: CaptureVerifySession?

    /// The bundled sample: a line drawing of a fuel receipt (45,22 L at 1,754
    /// EUR/L = 79,32 EUR) - never a real person's receipt.
    static var sampleImage: UIImage? {
        UIImage(named: "DemoReceipt")
    }

    var body: some View {
        Group {
            if let session {
                CaptureVerifyView(session: session, onContinue: finish, onRetake: finish, demo: true)
            } else {
                Theme.Palette.midnight.ignoresSafeArea()
            }
        }
        .task { start() }
    }

    private func start() {
        guard session == nil, let image = Self.sampleImage else { return }
        AppLog.shared.emit(CaptureDemo(stage: "opened"))
        let session = CaptureVerifySession(image: image, volumeUnit: .l)
        session.start {
            let prefill = await CapturePipeline.process(image,
                                                        bandProvider: AppFuelPriceBand.provider(vehicleId: nil),
                                                        homeCurrency: .eur)
            let read = [prefill.extraction?.total != nil, prefill.extraction?.liters != nil,
                        prefill.extraction?.unitPrice != nil].filter { $0 }.count
            AppLog.shared.emit(CaptureDemo(stage: "read", fieldsRead: read))
            return prefill
        }
        self.session = session
    }

    private func finish() {
        session?.cancel()
        AppLog.shared.emit(CaptureDemo(stage: "done"))
        dismiss()
    }
}

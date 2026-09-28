import SwiftUI
import TankbookCore
import UIKit

// MARK: - P3.1b / PJ.29a the service invoice capture path
//
// Split out of `CaptureView.swift` (which sits at the linter's file-length
// ceiling), the same split `CaptureExpenseScan.swift` made. The document
// camera's result and the `-captureAutoServiceScan` test hook both land in
// `scanServiceInvoice`; the reading itself (the local split and the cloud
// reading of every page) is `ServiceInvoiceSession.startReading`, shared with
// the service form's own "Add invoice".

extension CaptureView {
    /// The document camera returned pages: OCR them, split deterministically,
    /// persist the pages, hand the pre-fill to ServiceEntry and leave Capture.
    /// The pre-fill is default input the user edits (hard rule 13) - a failed
    /// split is the lump sum, never an error.
    ///
    /// RV.215: the read is deferred. The form opens now (after the cover beat);
    /// a read that finishes first fills it, and one that finishes after the
    /// entry is saved becomes an inbox item through the ONE policy
    /// (`AppInbox.recordLateGatewayAnswer`), never a second producer.
    ///
    /// PJ.29a: once the local split lands, the cloud reading of the same pages
    /// starts (F4: never awaited). A late answer reaches the inbox through the
    /// same one policy.
    func scanServiceInvoice(_ images: [UIImage]) {
        let vehicle = try? currentVehicle()
        var split: (@MainActor ([InvoicePage]) async -> ServiceScanOutcome)?
        #if DEBUG
        // DEBUG/test-only (`ServiceScanTestSeed`): a canned split lets a UI test
        // assert what the user SEES without OCR over a corpus image. It
        // substitutes only the scanner's output - the session hand-off, the
        // gateway start and the form's apply path are the shipped ones.
        let homeCurrency = vehicle?.homeCurrency ?? .eur
        if ProcessInfo.processInfo.arguments.contains("-seedServiceScan") {
            split = { staged in
                if let seeded = ServiceScanTestSeed.outcome(from: ProcessInfo.processInfo.arguments,
                                                            pages: staged, homeCurrency: homeCurrency) {
                    return seeded
                }
                return await ServiceInvoiceScanner.process(images: images, stagedPages: staged,
                                                           homeCurrency: homeCurrency)
            }
        }
        #endif
        invoiceSession.startReading(images: images, vehicle: vehicle, config: config, inbox: inbox,
                                    split: split)
        Task {
            try? await Task.sleep(for: Self.coverDismissBeat)
            onServiceEntry()
        }
    }

    /// DEBUG/test-only: `-captureAutoServiceScan` (with `-captureFixtureImage`)
    /// runs the real service scan a beat after the surface appears, so a UI test
    /// and `simctl` can reach the service form the document camera would have
    /// produced without driving the system scanner. `-captureAutoServiceScanPages
    /// <n>` repeats the fixture as n pages, the way a multi-page scan lands.
    /// Production never passes the argument; it routes through the exact call
    /// `DocumentCamera`'s result makes.
    func presentServiceScanIfRequested() {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("-captureAutoServiceScan"),
              let image = fixtureImage() else { return }
        var pageCount = 1
        if let index = arguments.firstIndex(of: "-captureAutoServiceScanPages"),
           arguments.indices.contains(index + 1),
           let count = Int(arguments[index + 1]) {
            pageCount = max(1, count)
        }
        Task {
            try? await Task.sleep(for: .milliseconds(600))
            scanServiceInvoice(Array(repeating: image, count: pageCount))
        }
        #endif
    }
}

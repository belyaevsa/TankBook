import SwiftUI
import TankbookCore
import UIKit

// MARK: - P3.1b / PJ.29a the service invoice capture path
//
// Split out of `CaptureView.swift` (which sits at the linter's file-length
// ceiling), the same split `CaptureExpenseScan.swift` made. The document
// camera's result and the `-captureAutoServiceScan` test hook both land in
// `scanServiceInvoice`; this extension owns the local split's hand-off and the
// cloud reading of every captured page.

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
        let homeCurrency = (try? currentVehicle())?.homeCurrency ?? .eur
        let session = invoiceSession
        let inbox = self.inbox
        // RV.243: persist the pages NOW, before the read. A save that beats the
        // read must still keep the invoice (hard rule 8); the read enriches
        // these same pages and only offers its values.
        let staged = ServiceInvoiceScanner.stagePages(images: images)
        session.start(
            stagedPages: staged,
            work: { await self.serviceScanOutcome(images: images, staged: staged,
                                                  homeCurrency: homeCurrency) },
            onAnswer: { outcome in session.pendingPrefill = outcome.prefill },
            onSavedAnswer: { outcome, entryID in
                inbox.recordLateGatewayAnswer(.service(outcome.recognition), entryID: entryID)
            })
        Task {
            try? await Task.sleep(for: Self.coverDismissBeat)
            onServiceEntry()
        }
    }

    /// PJ.29a: runs the local split and, once it has produced the outcome, fires
    /// the cloud reading of EVERY page in one request (docs/API.md "multi-page
    /// invoices"). The header is on the first page and the lines may run onto
    /// the rest; the cloud's lines are paired onto the local split by the
    /// device (docs/JOURNEYS.md J7), never taken as the split. Starting the
    /// gateway here, never awaited, keeps F4: the form opens on the local read
    /// and the cloud is a head start, not a wait.
    private func serviceScanOutcome(images: [UIImage], staged: [InvoicePage],
                                    homeCurrency: CurrencyCode) async -> ServiceScanOutcome {
        #if DEBUG
        // DEBUG/test-only (`ServiceScanTestSeed`): a canned split lets a UI test
        // assert what the user SEES without OCR over a corpus image. It
        // substitutes only the scanner's output - the session hand-off, the
        // gateway start and the form's apply path are the shipped ones.
        if let seeded = ServiceScanTestSeed.outcome(from: ProcessInfo.processInfo.arguments,
                                                    pages: staged,
                                                    homeCurrency: homeCurrency) {
            startServiceGatewayIfAvailable(pages: images)
            return seeded
        }
        #endif
        let outcome = await ServiceInvoiceScanner.process(images: images, stagedPages: staged,
                                                          homeCurrency: homeCurrency)
        startServiceGatewayIfAvailable(pages: images)
        return outcome
    }

    /// PJ.29a: fires `/extract` with `kind: "invoice"` for every captured page,
    /// under the same guards the fill-up and expense paths use -
    /// `allowsServerBacked` withholds the call under `.required` (docs/CONFIG.md),
    /// a guest has no transport, and a non-JPEG rendition gets no call. The
    /// answer is delivered to the open sheet through the session, or, once the
    /// record is saved, to the inbox through the ONE policy.
    private func startServiceGatewayIfAvailable(pages: [UIImage]) {
        guard config.allowsServerBacked, !pages.isEmpty else { return }
        let vehicle = try? currentVehicle()
        let language = Locale.current.language.languageCode?.identifier ?? "en"
        let hints = GatewayExtractHints(currency: vehicle?.homeCurrency.rawValue,
                                        locale: language,
                                        vehicleFuelKinds: [])
        let inbox = self.inbox
        invoiceSession.startGateway(
            pages: pages,
            hints: hints,
            captureId: UUID.v7().uuidString,
            maxInvoicePages: config.config.maxInvoicePages,
            onSavedAnswer: { extraction, entryID in
                let reading = ServiceRecognitionBuilder.reading(fromGateway: extraction,
                                                                homeCurrency: vehicle?.homeCurrency)
                inbox.recordLateGatewayAnswer(.service(reading.recognition), entryID: entryID)
            })
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

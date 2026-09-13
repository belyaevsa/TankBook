import SwiftUI
import TankbookCore
import UIKit

// MARK: - P3.1b / PJ.29a the service invoice capture path
//
// Split out of `CaptureView.swift` (which sits at the linter's file-length
// ceiling), the same split `CaptureExpenseScan.swift` made. The document
// camera's result and the `-captureAutoServiceScan` test hook both land in
// `scanServiceInvoice`; this extension owns the local split's hand-off and the
// cloud reading of the invoice's first page.

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
    /// PJ.29a: once the local split lands, the cloud reading of the same first
    /// page starts (F4: never awaited). A late answer reaches the inbox through
    /// the same one policy.
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
    /// the cloud reading of the FIRST page. An invoice may have several pages;
    /// the header is on the first, and only the header crosses the gateway - the
    /// line items stay the local deterministic split's (docs/JOURNEYS.md J7).
    /// Starting the gateway here, never awaited, keeps F4: the form opens on the
    /// local read and the cloud is a head start, not a wait.
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
            startServiceGatewayIfAvailable(image: images.first)
            return seeded
        }
        #endif
        let outcome = await ServiceInvoiceScanner.process(images: images, stagedPages: staged,
                                                          homeCurrency: homeCurrency)
        startServiceGatewayIfAvailable(image: images.first)
        return outcome
    }

    /// PJ.29a: fires `/extract` with `kind: "invoice"` for the first captured
    /// page, under the same guards the fill-up and expense paths use -
    /// `allowsServerBacked` withholds the call under `.required` (docs/CONFIG.md),
    /// a guest has no transport, and a non-JPEG rendition gets no call. The
    /// answer is delivered to the open sheet through the session, or, once the
    /// record is saved, to the inbox through the ONE policy.
    private func startServiceGatewayIfAvailable(image: UIImage?) {
        guard config.allowsServerBacked, let image else { return }
        let vehicle = try? currentVehicle()
        let language = Locale.current.language.languageCode?.identifier ?? "en"
        let hints = GatewayExtractHints(currency: vehicle?.homeCurrency.rawValue,
                                        locale: language,
                                        vehicleFuelKinds: [])
        let inbox = self.inbox
        invoiceSession.startGateway(
            image: image,
            hints: hints,
            captureId: UUID.v7().uuidString,
            onSavedAnswer: { extraction, entryID in
                let reading = ServiceRecognitionBuilder.reading(fromGateway: extraction)
                inbox.recordLateGatewayAnswer(.service(reading.recognition), entryID: entryID)
            })
    }

    /// DEBUG/test-only: `-captureAutoServiceScan` (with `-captureFixtureImage`)
    /// runs the real service scan a beat after the surface appears, so a UI test
    /// and `simctl` can reach the service form the document camera would have
    /// produced without driving the system scanner. Production never passes the
    /// argument; it routes through the exact call `DocumentCamera`'s result makes.
    func presentServiceScanIfRequested() {
        #if DEBUG
        guard ProcessInfo.processInfo.arguments.contains("-captureAutoServiceScan"),
              let image = fixtureImage() else { return }
        Task {
            try? await Task.sleep(for: .milliseconds(600))
            scanServiceInvoice([image])
        }
        #endif
    }
}

import TankbookCore
import UIKit

// The invoice's reading, started the same way from every door that gives a
// service its invoice: Capture's Service mode (the document camera, a Photos
// pick, "Open as service") and the service form's own "Add invoice" (RV.332).

extension ServiceInvoiceSession {
    /// Stages the pages at once (RV.243: a save that beats the read keeps the
    /// invoice), runs the deterministic split in the background and, once it
    /// has produced its outcome, the cloud reading of every page (PJ.29a, F4:
    /// never awaited). The split fills the open form only while the user has
    /// typed nothing (`ServiceEntryView`'s `prefillRevision` handler); an
    /// answer after the save becomes an inbox item through the one policy.
    /// Returns the staged pages for the form's strip.
    @discardableResult
    func startReading(images: [UIImage], vehicle: Vehicle?, config: AppConfigService, inbox: AppInbox,
                      split: (@MainActor ([InvoicePage]) async -> ServiceScanOutcome)? = nil) -> [InvoicePage] {
        let homeCurrency = vehicle?.homeCurrency ?? .eur
        let saveResult = ServiceInvoiceScanner.stagePagesResult(images: images)
        let staged = saveResult.pages
        failedPages = saveResult.failures
        start(
            stagedPages: staged,
            work: { [weak self] in
                let outcome: ServiceScanOutcome
                if let split {
                    outcome = await split(staged)
                } else {
                    outcome = await ServiceInvoiceScanner.process(images: images, stagedPages: staged,
                                                                  homeCurrency: homeCurrency)
                }
                self?.startCloudReading(pages: staged.map(\.image), vehicle: vehicle,
                                       config: config, inbox: inbox)
                return outcome
            },
            onAnswer: { [weak self] outcome in self?.pendingPrefill = outcome.prefill },
            onSavedAnswer: { outcome, entryID in
                inbox.recordLateGatewayAnswer(.service(outcome.recognition), entryID: entryID)
            })
        return staged
    }

    /// PJ.29a: fires `/extract` with `kind: "invoice"` for every page, under
    /// the same guards the fill-up and expense paths use - `allowsServerBacked`
    /// withholds the call under `.required` (docs/CONFIG.md), a guest has no
    /// transport, and a non-JPEG rendition gets no call. The answer is
    /// delivered to the open sheet through the session, or, once the record
    /// is saved, to the inbox through the ONE policy.
    func startCloudReading(pages: [UIImage], vehicle: Vehicle?, config: AppConfigService, inbox: AppInbox) {
        guard config.allowsServerBacked, !pages.isEmpty else { return }
        let language = Locale.current.language.languageCode?.identifier ?? "en"
        let hints = GatewayExtractHints(currency: vehicle?.homeCurrency.rawValue,
                                        locale: language,
                                        vehicleFuelKinds: [])
        startGateway(
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
}

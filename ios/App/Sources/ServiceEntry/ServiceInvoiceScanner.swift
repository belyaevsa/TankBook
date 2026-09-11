import Foundation
import UIKit
import TankbookCore

/// The scanned invoice path (P3.1b): document-camera images in, a
/// `ServiceEntryPrefill` out. OCR runs per page (the text is retained on each
/// attachment for re-parsing after a parser upgrade); the deterministic
/// `InvoiceSplitter` runs over all pages' lines; each page is persisted as an
/// `Attachment` with the invoice's printed date as `extractedTimestamp`.
///
/// The splitter's output is a head start, never an answer (hard rules 13, 15):
/// a failed split returns the lump sum, an unreadable invoice returns an empty
/// pre-fill - neither is an error state, so these functions never throw outward.
///
/// `appendPages` is the page strip's "+ add page": it OCRs and persists the new
/// pages WITHOUT re-splitting, so a row the user already changed stays changed
/// (hard rule 13 - a scan never overwrites a value the user owns).
@MainActor
enum ServiceInvoiceScanner {
    static let languages = ["en-US", "de-DE", "ru-RU"]

    static func process(images: [UIImage], stagedPages: [InvoicePage],
                        homeCurrency: CurrencyCode) async -> ServiceScanOutcome {
        guard let repository = try? AppStore.repository(), !images.isEmpty else {
            return ServiceScanOutcome(prefill: ServiceEntryPrefill(),
                                      recognition: ServiceRecognition())
        }
        let linesByPage = images.map(ocrLines)
        let split = InvoiceSplitter().split(lines: linesByPage.flatMap { $0 })
        let pages = enrichPages(stagedPages, linesByPage: linesByPage,
                                extractedTimestamp: split.date, repository: repository)

        let items = split.items.map { item in
            ServiceEntryItemDraft(
                title: item.title,
                category: item.category,
                cost: ConfirmFormat.string(decimal: item.amount, fractionDigits: 2),
                scanned: true)
        }

        let prefill = ServiceEntryPrefill(
            vendor: split.vendor ?? "",
            items: items,
            odometer: "",
            date: split.date ?? Date(),
            dateFromInvoice: split.date != nil,
            pages: pages,
            provenance: .receiptScan,
            extraction: split.extraction)
        // RV.215: the same split is what a late read would offer the saved
        // record, so it is produced here, not re-derived by a second reader.
        return ServiceScanOutcome(prefill: prefill,
                                  recognition: recognition(from: split, homeCurrency: homeCurrency))
    }

    /// RV.243: persists the captured pages the instant the scan starts, before
    /// the read has OCR'd or split anything. A save that beats the read still
    /// keeps the invoice (hard rule 8); `process` enriches these SAME pages
    /// (`updatePage`) instead of persisting a second set, so the late read only
    /// offers values and never writes a duplicate page.
    static func stagePages(images: [UIImage]) -> [InvoicePage] {
        guard let repository = try? AppStore.repository(), !images.isEmpty else { return [] }
        return persistPages(repository: repository, images: images,
                            linesByPage: images.map { _ in [] },
                            extractedTimestamp: nil)
    }

    /// The late-answer shape of the same split: the vendor, the invoice total,
    /// the currency it is priced in and each line (with its own money pair, so
    /// taking a line brings its cost rather than guessing one). Every value is a
    /// suggestion - `GatewayInboxPolicy` decides what is a decision.
    static func recognition(from split: InvoiceSplitResult,
                            homeCurrency: CurrencyCode) -> ServiceRecognition {
        let lineItems = split.items.map { item in
            ServiceRecognition.LineItem(
                title: item.title,
                category: item.category,
                cost: Money(amount: item.amount, currency: homeCurrency,
                            homeCurrency: homeCurrency))
        }
        return ServiceRecognition(
            vendor: split.vendor.map { GatewayFieldValue(value: $0, confidence: 0.9) },
            total: split.total.map { GatewayFieldValue(value: $0, confidence: 0.9) },
            currency: GatewayFieldValue(value: homeCurrency, confidence: 0.9),
            lineItems: lineItems)
    }

    static func appendPages(images: [UIImage]) async -> [InvoicePage] {
        guard let repository = try? AppStore.repository(), !images.isEmpty else { return [] }
        let linesByPage = images.map(ocrLines)
        return persistPages(repository: repository, images: images,
                            linesByPage: linesByPage, extractedTimestamp: nil)
    }

    // MARK: - Helpers

    private static func ocrLines(_ image: UIImage) -> [OCRLine] {
        guard let cgImage = image.cgImage else { return [] }
        return (try? VisionTextRecognizer.recognizeText(image: cgImage,
                                                        languages: languages)) ?? []
    }

    private static func persistPages(repository: TankbookRepository,
                                     images: [UIImage],
                                     linesByPage: [[OCRLine]],
                                     extractedTimestamp: Date?) -> [InvoicePage] {
        let store = InvoicePageStore(repository: repository, files: InvoiceAttachmentFiles())
        var pages: [InvoicePage] = []
        for (index, image) in images.enumerated() {
            let lines = linesByPage[index]
            let ocrText = lines.isEmpty ? nil : lines.map(\.text).joined(separator: "\n")
            let jpeg = image.jpegData(compressionQuality: 0.8) ?? Data()
            guard let attachment = try? store.addPage(
                imageData: jpeg, ocrText: ocrText, extractedTimestamp: extractedTimestamp) else {
                continue
            }
            pages.append(InvoicePage(attachment: attachment, image: image))
        }
        return pages
    }

    /// RV.243: fills in the pages staged at scan start with the read's OCR text
    /// and the invoice's printed date. The file and row already exist; this
    /// updates them in place, so a deferred read never leaves a second page.
    private static func enrichPages(_ pages: [InvoicePage], linesByPage: [[OCRLine]],
                                    extractedTimestamp: Date?,
                                    repository: TankbookRepository) -> [InvoicePage] {
        let store = InvoicePageStore(repository: repository, files: InvoiceAttachmentFiles())
        return pages.enumerated().map { index, page in
            let lines = index < linesByPage.count ? linesByPage[index] : []
            let ocrText = lines.isEmpty ? nil : lines.map(\.text).joined(separator: "\n")
            guard let updated = try? store.updatePage(page.attachment, ocrText: ocrText,
                                                      extractedTimestamp: extractedTimestamp) else {
                return page
            }
            return InvoicePage(attachment: updated, image: page.image)
        }
    }
}

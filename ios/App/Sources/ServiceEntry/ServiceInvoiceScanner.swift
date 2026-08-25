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

    static func process(images: [UIImage]) async -> ServiceEntryPrefill {
        guard let repository = try? AppStore.repository(), !images.isEmpty else {
            return ServiceEntryPrefill()
        }
        let linesByPage = images.map(ocrLines)
        let split = InvoiceSplitter().split(lines: linesByPage.flatMap { $0 })
        let pages = persistPages(repository: repository, images: images,
                                 linesByPage: linesByPage, extractedTimestamp: split.date)

        let items = split.items.map { item in
            ServiceEntryItemDraft(
                title: item.title,
                category: item.category,
                cost: ConfirmFormat.string(decimal: item.amount, fractionDigits: 2),
                scanned: true)
        }

        return ServiceEntryPrefill(
            vendor: split.vendor ?? "",
            items: items,
            odometer: "",
            date: split.date ?? Date(),
            dateFromInvoice: split.date != nil,
            pages: pages,
            provenance: .receiptScan,
            extraction: split.extraction)
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
}

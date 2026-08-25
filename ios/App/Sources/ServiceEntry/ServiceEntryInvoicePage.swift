import UIKit
import TankbookCore

/// One scanned invoice page held on the ServiceEntry screen (P3.1b). The
/// `attachment` was persisted at capture time (file + row, via
/// `InvoicePageStore`); the `image` is the in-memory thumbnail the page strip
/// renders. Removing a page deletes its attachment row AND its file - no orphan.
struct InvoicePage: Identifiable {
    let attachment: Attachment
    let image: UIImage

    var id: UUID { attachment.id }
}

/// The placeholder thumbnail the seeds and screenshots use for a scanned page
/// (simctl cannot drive the document camera, so a seed renders the strip from a
/// generated page image rather than a real scan). Test-only.
enum InvoicePagePreview {
    static func image(width: CGFloat = 120, height: CGFloat = 160) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height))
        return renderer.image { context in
            UIColor(white: 0.93, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            UIColor(white: 0.45, alpha: 1).setFill()
            var y: CGFloat = 18
            var index = 0
            while y < height - 14 {
                let lineWidth = width - 22 - CGFloat((index * 7) % 26)
                context.fill(CGRect(x: 11, y: y, width: lineWidth, height: 3))
                y += 14
                index += 1
            }
        }
    }
}

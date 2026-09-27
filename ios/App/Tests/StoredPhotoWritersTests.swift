import ImageIO
import TankbookCore
import UIKit
import XCTest
@testable import Tankbook

/// SH.10: every photo writer stores the rendition, not the full capture - the
/// receipt save, the out-of-save attach, and an invoice page. The stored file is
/// also what sync uploads (`FileBackedBlobSource` reads it as it is).
@MainActor
final class StoredPhotoWritersTests: XCTestCase {
    private func capture() -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 4032, height: 3024), format: format).image { context in
            UIColor.darkGray.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4032, height: 3024))
        }
    }

    private func longEdge(_ data: Data) throws -> Int {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        return max(properties[kCGImagePropertyPixelWidth] as? Int ?? 0, properties[kCGImagePropertyPixelHeight] as? Int ?? 0)
    }

    private func stored(_ attachment: Attachment) throws -> Data {
        let url = try VehiclePhotoStore.attachmentsDirectory().appendingPathComponent(attachment.file.relativePath)
        defer { try? FileManager.default.removeItem(at: url) }
        return try Data(contentsOf: url)
    }

    func testTheOutOfSaveAttachStoresTheRendition() throws {
        let attachment = try ReceiptAttachmentWriter.write(id: AttachmentID(), image: capture(), ocrLines: [],
                                                           extraction: FuelExtraction())
        XCTAssertLessThanOrEqual(try longEdge(stored(attachment)), AttachmentRendition.maxLongEdge)
    }

    func testTheReceiptSaveStoresTheRendition() throws {
        let repository = TankbookRepository(database: try TankbookDatabase.inMemory())
        let id = AttachmentID()
        try writeReceiptPhoto(id: id, source: ConfirmPrefill(extraction: FuelExtraction(), sourceImage: capture()),
                              extraction: nil, repository: repository)
        let attachment = try XCTUnwrap(repository.liveAttachments().first { $0.id == id })
        XCTAssertLessThanOrEqual(try longEdge(stored(attachment)), AttachmentRendition.maxLongEdge)
    }

    func testAnInvoicePageStoresTheRendition() throws {
        XCTAssertLessThanOrEqual(try longEdge(ServiceInvoiceScanner.storedPageData(capture())),
                                 AttachmentRendition.maxLongEdge)
    }
}

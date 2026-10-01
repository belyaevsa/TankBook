import TankbookCore
import UIKit
import XCTest
@testable import Tankbook

@MainActor
final class PJ43PageSaveTests: XCTestCase {
    func testFailedMiddlePageKeepsItsSlotAndContinueAttachesOnlySavedPages() throws {
        let repository = try AppStore.repository()
        let before = try repository.liveAttachments().count
        ServiceInvoiceScanner.debugFailPageIndex = 2
        let image = InvoicePagePreview.image()
        let result = ServiceInvoiceScanner.stagePagesResult(images: [image, image, image])

        XCTAssertEqual(result.failures, [FailedInvoicePage(index: 1, total: 3)])
        XCTAssertEqual(result.pages.map(\.sourceIndex), [0, 2])
        XCTAssertEqual(result.pages.count, 2)
        let attachmentIDs = result.pages.map(\.attachment.id)
        XCTAssertEqual(Set(attachmentIDs).count, 2)
        XCTAssertEqual(try repository.liveAttachments().count, before + 2)

        ServiceEntryView.discardStagedPages(result.pages, pendingPrefill: nil,
                                            session: ServiceInvoiceSession(), repository: repository)
        XCTAssertEqual(try repository.liveAttachments().count, before)
    }
}

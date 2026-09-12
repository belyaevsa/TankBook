import Foundation

// MARK: - A cancelled service scan's staged pages (RV.245, docs/LOGGING.md §4)

/// The shape-only record that a ServiceEntry sheet closed without a save and
/// its staged invoice pages were deleted with it. `pageCount` is how many
/// attachment rows were tombstoned - a count, the whole shape of the event -
/// never a page's text, its image or the invoice's values (hard rule 12).
///
/// The server-side orphan sweep (P4.3) never reaches the device, so this line
/// is the only record that the cleanup ran and how much it took.
public struct InvoicePagesDiscarded: LogEvent {
    public let eventName = "service.pages.discarded"
    public let category = LogCategory.ui
    public let level = LogLevel.info
    public let fields: [LogField]

    public init(pageCount: Int) {
        fields = [.safe("pageCount", pageCount)]
    }
}

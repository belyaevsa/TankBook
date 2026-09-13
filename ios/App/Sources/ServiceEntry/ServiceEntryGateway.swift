import Foundation
import TankbookCore

// MARK: - PJ.29a the cloud reading (docs/API.md -> "The device's side of /extract")

// Split out of `ServiceEntryView.swift` (which sits near the linter's
// file-length ceiling), the same split `ExpenseEntryGateway.swift` made. The
// capture path starts the session-owned gateway; this is the sheet half: it
// consumes the answer the session holds and applies it under the fill-up path's
// own rule - blank AND untouched fields only, never a value the user owns
// (hard rule 13, docs/JOURNEYS.md F4).
extension ServiceEntryView {
    /// Consumes a cloud answer the session has ready and applies it. Called from
    /// `load()` (an answer that beat the sheet) and from the `gatewayRevision`
    /// onChange (an answer that arrived while it was open).
    func applyPendingGatewayAnswer() {
        guard let extraction = invoiceSession.consumePendingGatewayExtraction() else { return }
        applyGatewayAnswer(extraction)
    }

    /// Applies a WITHIN-BUDGET cloud answer as a SUGGESTION, bound by hard rule
    /// 13 and F4: only header fields still blank AND untouched, on an unsaved
    /// record. The vendor, the date and the currency are the service header's
    /// field set. The total the answer may carry has no standalone field on this
    /// form - the header total is derived from the line items (hard rule 2) - so
    /// it is offered through the inbox recognition, never typed into the form.
    /// The line items a cloud answer might carry have no channel at all: the
    /// core mapping produces none, so the local split's stay the form's.
    func applyGatewayAnswer(_ extraction: GatewayExtraction) {
        let reading = ServiceRecognitionBuilder.reading(fromGateway: extraction)
        let snapshot = GatewaySuggestionSnapshot(
            touched: invoiceSession.gateway.touched,
            onDeviceResolved: gatewayOnDeviceResolved,
            saved: invoiceSession.gateway.phase == .saved)
        for ref in GatewaySuggestionPolicy.fillableFields(answer: extraction, snapshot: snapshot) {
            switch ref {
            case .vendor:
                if let vendor = reading.prefill.vendor {
                    form.vendor = vendor
                    form.initialVendor = vendor
                }
            case .currency:
                if let currency = reading.prefill.currency {
                    form.currency = currency
                    form.initialCurrency = currency
                }
            case .date:
                if let date = reading.prefill.date {
                    form.date = date
                    form.initialDate = date
                    form.dateFromInvoice = true
                }
            default:
                break
            }
        }
    }

    /// The header fields the ON-DEVICE split resolved - the cloud answer must
    /// never fight it for one of them (F4). The vendor counts only when the
    /// split read one; the date only when it came from the invoice (a default
    /// "today" is not a resolution). The local split never resolves a currency,
    /// so it is always the cloud's to offer.
    static func onDeviceResolvedFields(prefill: ServiceEntryPrefill?) -> Set<FieldRef> {
        var out = Set<FieldRef>()
        if let vendor = prefill?.vendor,
           !vendor.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            out.insert(.vendor)
        }
        if prefill?.dateFromInvoice == true { out.insert(.date) }
        return out
    }
}

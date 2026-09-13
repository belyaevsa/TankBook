import Foundation
import TankbookCore

// MARK: - PJ.29 the cloud reading (docs/API.md -> "The device's side of /extract")

// Split out of `ExpenseEntryView.swift` (which sits near the linter's
// file-length ceiling), the same split `ExpenseEntrySave.swift` made. The
// capture path starts the session-owned gateway; this is the sheet half: it
// consumes the answer the session holds and applies it under the fill-up path's
// own rule - blank AND untouched fields only, never a value the user owns
// (hard rule 13, docs/JOURNEYS.md F4).
extension ExpenseEntryView {
    /// Consumes a cloud answer the session has ready and applies it. Called from
    /// `load()` (an answer that beat the sheet) and from the `gatewayRevision`
    /// onChange (an answer that arrived while it was open).
    func applyPendingGatewayAnswer() {
        guard let extraction = expenseSession.consumePendingGatewayExtraction() else { return }
        applyGatewayAnswer(extraction)
    }

    /// Applies a WITHIN-BUDGET cloud answer as a SUGGESTION, bound by hard rule
    /// 13 and F4: only fields still blank AND untouched, on an unsaved entry.
    /// The amount, its currency, the date and the category are the expense field
    /// set; the fuel fields a `receipt` answer might carry have no home here and
    /// are dropped by the core mapping (`ExpensePrefillBuilder.reading`).
    func applyGatewayAnswer(_ extraction: GatewayExtraction) {
        let reading = ExpensePrefillBuilder.reading(fromGateway: extraction)
        let snapshot = GatewaySuggestionSnapshot(
            touched: expenseSession.gateway.touched,
            onDeviceResolved: gatewayOnDeviceResolved,
            saved: expenseSession.gateway.phase == .saved)
        for ref in GatewaySuggestionPolicy.fillableFields(answer: extraction, snapshot: snapshot) {
            switch ref {
            case .total:
                if let total = reading.prefill.total {
                    form.amount = ConfirmFormat.string(decimal: total, fractionDigits: 2)
                    // A suggestion is a pre-fill, not a user edit: keep the
                    // discard snapshot in step so a later on-device read still
                    // has first claim.
                    form.initialAmount = form.amount
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
                }
            case .category:
                if let category = reading.recognition.category?.value {
                    form.category = category
                    form.initialCategory = category
                }
            default:
                break
            }
        }
    }
}

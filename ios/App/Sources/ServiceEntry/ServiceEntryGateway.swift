import Foundation
import SwiftUI
import TankbookCore

// MARK: - PJ.29a the cloud reading (docs/API.md -> "The device's side of /extract")

// Split out of `ServiceEntryView.swift` (which sits near the linter's
// file-length ceiling), the same split `ExpenseEntryGateway.swift` made. The
// capture path starts the session-owned gateway; this is the sheet half: it
// consumes the answer the session holds and applies it under the fill-up path's
// own rule - blank AND untouched header fields only, never a value the user
// owns (hard rule 13, docs/JOURNEYS.md F4) - and renders the answer's LINES as
// offers on the split's rows (docs/JOURNEYS.md J7 "every page reaches the
// cloud"), each answered take-or-keep, keep by default.
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
    /// The answer's line items become `lineOffers` (`offerLines`), never rows.
    func applyGatewayAnswer(_ extraction: GatewayExtraction) {
        let reading = ServiceRecognitionBuilder.reading(fromGateway: extraction,
                                                        homeCurrency: vehicle?.homeCurrency)
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
        offerLines(reading.recognition)
    }

    /// Pairs the cloud's lines onto the form's rows and holds the pairs as
    /// offers - by amount, then title, never by position (`LineMatcher`, the
    /// same pairing the inbox card uses). A paired line that agrees with its
    /// row is no offer; one that differs is offered on that row; a cloud line
    /// with no partner is offered as a new line; a row the cloud did not see is
    /// left alone. The arithmetic gate's flag rides along: a reading that does
    /// not add up is still offered, flagged under the total, never applied.
    /// Tires mode has no line rows, so nothing is offered there.
    func offerLines(_ recognition: ServiceRecognition) {
        readingDoesNotAddUp = recognition.doesNotAddUp
        guard form.mode == .service, !recognition.lineItems.isEmpty else { return }
        let home = vehicle?.homeCurrency ?? form.currency
        let local = form.items.map { $0.serviceItem(currency: form.currency, homeCurrency: home) }
        lineOffers = LineMatcher.match(cloud: recognition.lineItems, local: local).compactMap { match in
            let line = recognition.lineItems[match.cloudIndex]
            guard let localIndex = match.localIndex else {
                return ServiceLineOffer(id: match.cloudIndex, localItemID: nil, line: line)
            }
            let current = local[localIndex]
            guard current.title != line.title || current.category != line.category
                    || current.cost?.amount != line.cost?.amount else { return nil }
            return ServiceLineOffer(id: match.cloudIndex, localItemID: form.items[localIndex].id, line: line)
        }
    }

    /// Take the invoice's line: the row's title, category and cost become the
    /// cloud's. The row is the user's from here (`scanned` lifts through the
    /// card's own edit hooks), and the offer is answered.
    func takeLineOffer(_ offer: ServiceLineOffer) {
        if let index = form.items.firstIndex(where: { $0.id == offer.localItemID }) {
            form.items[index].title = offer.line.title
            form.items[index].category = offer.line.category
            form.items[index].cost = offer.line.cost.map {
                ManualFillUpFormat.decimal($0.amount, fractionDigits: 2)
            } ?? ""
        }
        lineOffers.removeAll { $0.id == offer.id }
    }

    /// Add the cloud's new line to the split, as the user's own row.
    func addLineOffer(_ offer: ServiceLineOffer) {
        form.items.append(ServiceEntryItemDraft(
            title: offer.line.title,
            category: offer.line.category,
            cost: offer.line.cost.map { ManualFillUpFormat.decimal($0.amount, fractionDigits: 2) } ?? ""))
        lineOffers.removeAll { $0.id == offer.id }
    }

    /// Keep mine, said out loud: the offer goes, the row stays as typed.
    func keepLineOffer(_ offer: ServiceLineOffer) {
        lineOffers.removeAll { $0.id == offer.id }
    }

    /// The line rows with their offers: each row carries the strip for the
    /// cloud line paired with it, and the cloud's unpaired lines follow the
    /// split as dimmed cards the user adds or dismisses.
    var lineItemsSection: some View {
        Group {
            ForEach($form.items) { $item in
                ServiceEntryItemCard(item: $item, onDelete: {
                    form.items.removeAll { $0.id == item.id }
                }, offer: lineOffers.first { $0.localItemID == item.id },
                   onTakeOffer: takeLineOffer, onKeepOffer: keepLineOffer)
                    .id(Self.lineOfferAnchor(for: item.id))
            }
            ForEach(lineOffers.filter { $0.localItemID == nil }) { offer in
                ServiceLineOfferNewCard(offer: offer,
                                        onAdd: { addLineOffer(offer) },
                                        onDismiss: { keepLineOffer(offer) })
            }
            ServiceEntryAddItemButton(action: addItem)
        }
    }

    static func lineOfferAnchor(for itemID: UUID) -> String { "lineOffer-\(itemID.uuidString)" }

    /// DEBUG/screenshot-only: `-screenshotLineOffers` scrolls the first
    /// offered row into view once the offers land, so the capture shows the
    /// strip rather than the top of a long form. Production never passes it.
    func scrollToLineOffersForScreenshot(_ proxy: ScrollViewProxy) {
        #if DEBUG
        guard ProcessInfo.processInfo.arguments.contains("-screenshotLineOffers"),
              let first = lineOffers.first(where: { $0.localItemID != nil })?.localItemID else { return }
        withAnimation { proxy.scrollTo(Self.lineOfferAnchor(for: first), anchor: .bottom) }
        #endif
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

import SwiftUI
import TankbookCore

// MARK: - The cloud's line offers on the open form (docs/JOURNEYS.md J7, PJ.303)

/// One cloud line offered against the form: the form row it pairs with (by
/// amount, then title - `LineMatcher`, never by position) or, with no
/// partner, a new line. Held beside the form, never in it: an offer nobody
/// answers changes nothing at save (hard rule 13, "keep mine" is the default).
struct ServiceLineOffer: Identifiable, Equatable {
    /// The cloud line's index, stable for the sheet's life.
    let id: Int
    /// The form row this offer pairs with; nil when the cloud read a line the
    /// local split did not.
    let localItemID: UUID?
    let line: ServiceRecognition.LineItem
}

extension ServiceLineOffer {
    /// The cloud's reading of the line, title and cost together - the same
    /// rendering the inbox card's receipt column uses, so the two surfaces
    /// name the same line the same way.
    var valueText: String {
        guard let cost = line.cost else { return line.title }
        let amount = ManualFillUpFormat.decimal(cost.amount, fractionDigits: 2)
        return "\(line.title) · \(amount)\u{00A0}\(AddVehicleSupport.moneySymbol(for: cost.currency))"
    }
}

/// The offer strip under a paired row: "From the invoice: <cloud line>" with
/// the two answers. The value is dimmed - a suggestion, not a fact - and the
/// buttons are not, so the answer is always reachable. Taking swaps the row;
/// keeping removes the strip; doing neither leaves the row exactly as typed.
struct ServiceLineOfferStrip: View {
    let offer: ServiceLineOffer
    let onTake: () -> Void
    let onKeep: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.serviceLineOfferCaption)
                .font(.caption2)
                .foregroundStyle(Theme.Palette.inkSoft)
            // The value on its own line and the answers under it: RU
            // "Оставить" beside a long line squeezed the value into a
            // mid-word wrap when the three shared a row.
            Text(offer.valueText)
                .font(.subheadline)
                .foregroundStyle(Theme.Palette.ink)
                .opacity(ConfirmConfidenceGate.dimmedOpacity)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("serviceEntryLineOfferValue_\(offer.id)")
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                ServiceLineOfferButton(title: L10n.serviceLineOfferTake, prominent: true, action: onTake)
                    .accessibilityIdentifier("serviceEntryLineOfferTake_\(offer.id)")
                ServiceLineOfferButton(title: L10n.serviceLineOfferKeep, prominent: false, action: onKeep)
                    .accessibilityIdentifier("serviceEntryLineOfferKeep_\(offer.id)")
            }
        }
        .padding(.top, 4)
    }
}

/// A cloud line no local line matched, offered as a dimmed row of its own
/// below the split. It joins the split only when accepted; dismissing it
/// leaves no trace, and neither answer touches a line the user typed.
struct ServiceLineOfferNewCard: View {
    let offer: ServiceLineOffer
    let onAdd: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.serviceLineOfferNewCaption)
                .font(.caption2)
                .foregroundStyle(Theme.Palette.inkSoft)
            Text(offer.valueText)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.Palette.ink)
                .opacity(ConfirmConfidenceGate.dimmedOpacity)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("serviceEntryLineOfferValue_\(offer.id)")
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                ServiceLineOfferButton(title: L10n.serviceLineOfferAdd, prominent: true, action: onAdd)
                    .accessibilityIdentifier("serviceEntryLineOfferTake_\(offer.id)")
                ServiceLineOfferButton(title: L10n.serviceLineOfferDismiss, prominent: false, action: onDismiss)
                    .accessibilityIdentifier("serviceEntryLineOfferKeep_\(offer.id)")
            }
        }
        .padding(13)
        .formCard()
    }
}

/// The two answers, as compact chips. Blue `action` for the one that changes
/// the row (a choice, not chrome), `inkSoft` for keeping - neither is red or
/// amber, because nothing here is wrong (hard rule 5).
struct ServiceLineOfferButton: View {
    let title: String
    let prominent: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(prominent ? Theme.Palette.action : Theme.Palette.inkSoft)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Theme.Palette.midnight)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// The arithmetic gate's flag (docs/ERRORS.md -> Service & expenses, "cloud
/// reading doesn't add up"): the cloud's lines do not sum to the header total
/// it read, so its lines are offered with this line under the total and never
/// applied. Amber is attention, not action (hard rule 5); the sentence names
/// the next step and Save is untouched (hard rule 7).
struct ServiceReadingDoesNotAddUpLine: View {
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption2)
                .foregroundStyle(Theme.Palette.warn)
            Text(L10n.serviceReadingDoesNotAddUp)
                .font(.caption2)
                .foregroundStyle(Theme.Palette.warn)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 2)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("serviceEntryReadingDoesNotAddUp")
    }
}

/// The page-cap note (docs/ERRORS.md -> Service & expenses, "invoice over the
/// cloud page cap"): the scan has more pages than `/extract` takes, so no
/// cloud reading was started. Every page is kept and split on the device -
/// nothing is lost (hard rule 8) and the split stands (hard rules 1, 15).
struct ServicePageCapNoteView: View {
    let cap: Int

    var body: some View {
        Text(L10n.servicePageCapNote(cap))
            .font(.footnote)
            .foregroundStyle(Theme.Palette.inkSoft)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Theme.Palette.dash)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .accessibilityIdentifier("servicePageCapNote")
    }
}

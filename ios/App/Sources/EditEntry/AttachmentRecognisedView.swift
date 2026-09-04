import SwiftUI
import TankbookCore

/// The attachment viewer's second page (RV.17, RV.48): what the receipt carried
/// when it was read. RV.48 changed the headline from the raw OCR lines to the
/// parse's per-field ASSIGNMENT (`Attachment.extractionMeta`) - what the receipt
/// said per field, the numbers in DIN with units subordinate, money
/// amount-then-symbol. The raw text is demoted behind a disclosure, never
/// deleted from the view. This is presentation of STORED data, never
/// re-recognition: the viewer must not re-run OCR, because a fresh read could
/// contradict values the user has already confirmed (hard rule 13) and the whole
/// point of the viewer is to look, not to re-derive.
///
/// Hard rule 13 is untouched. The stored assignment is a record of what the
/// scan CONCLUDED, not a fact and not a source that may overwrite a user's
/// value: `FieldExtraction.userCorrected` already marks a field the user
/// changed, and nothing here feeds a value back into an entry.
struct AttachmentRecognisedView: View {
    let extractionMeta: ExtractionMeta?
    let ocrText: String?
    let extractedTimestamp: Date?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("What was read")
                    .font(.headline)
                    .foregroundStyle(Theme.Palette.ink)
                    .accessibilityIdentifier("attachmentViewerRecognisedTitle")
                if let timestamp = extractedTimestamp {
                    Text(Self.scannedLine(timestamp))
                        .font(.footnote)
                        .foregroundStyle(Theme.Palette.inkSoft)
                }
                let rows = AttachmentValueFormat.rows(from: extractionMeta)
                if rows.isEmpty {
                    nothingRecognisedCard
                } else {
                    fieldList(rows)
                }
                if let ocr = Self.nonEmpty(ocrText) {
                    rawTextDisclosure(ocr)
                }
            }
            .padding(.horizontal, Theme.Spacing.screenMargin)
            .padding(.vertical, 20)
        }
        .background(Theme.Palette.midnight)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("attachmentViewerRecognised")
    }

    /// The assigned fields, the page's headline (RV.48). One row per field the
    /// parse assigned a value to - a field it did not assign is absent, never a
    /// blank row. Numbers in DIN with the unit subordinate (hard rule 6).
    private func fieldList(_ rows: [AttachmentValueFormat.Row]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(row.label)
                        .font(.footnote)
                        .foregroundStyle(Theme.Palette.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 12)
                    switch row.value {
                    case .numeric(let figure, let unit):
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text(figure)
                                .font(.custom(AppFonts.dinAlternateBold, size: 15))
                                .monospacedDigit()
                                .foregroundStyle(Theme.Palette.ink)
                            if let unit {
                                Text(unit)
                                    .font(.caption)
                                    .foregroundStyle(Theme.Palette.inkSoft)
                            }
                        }
                    case .plain(let text):
                        Text(text)
                            .font(.footnote)
                            .foregroundStyle(Theme.Palette.ink)
                    }
                }
                .padding(.vertical, 10)
                if index < rows.count - 1 {
                    Divider().overlay(Theme.Palette.hairline)
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.cardPadding)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Palette.dash.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card)
                .stroke(Theme.Palette.hairline, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("attachmentViewerRecognisedFields")
    }

    /// A parse that assigned nothing says so, instead of an empty card (RV.48's
    /// L4 requirement). The photo is the page beside this one, so the honest
    /// statement names no next step beyond looking at it.
    private var nothingRecognisedCard: some View {
        Text("Nothing usable was read from this receipt.")
            .font(.subheadline)
            .foregroundStyle(Theme.Palette.inkSoft)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Spacing.cardPadding)
            .background(Theme.Palette.dash.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card)
                    .stroke(Theme.Palette.hairline, lineWidth: 1)
            )
            .accessibilityIdentifier("attachmentViewerNothingRecognised")
    }

    /// The raw OCR lines, demoted behind a disclosure (RV.48). Kept rather than
    /// deleted so a bad parse can still be re-examined (docs/EXTRACTION.md's
    /// failure modes are pinned to it); the assigned fields above are the
    /// meaning, this is the evidence.
    private func rawTextDisclosure(_ ocr: String) -> some View {
        DisclosureGroup {
            Text(ocr)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(Theme.Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 10)
                .accessibilityIdentifier("attachmentViewerOcrText")
        } label: {
            Text("Read from the receipt")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.Palette.inkSoft)
        }
        .tint(Theme.Palette.inkSoft)
        .accessibilityIdentifier("attachmentViewerRawTextDisclosure")
    }

    /// "Scanned 3 Sept, 14:32" - the timestamp the pipeline stamped on the
    /// attachment. One full localised phrase per language (the RU pass on P1.4
    /// proved composed strings need a full localised phrase), the date formatted
    /// locale-aware.
    private static func scannedLine(_ timestamp: Date) -> String {
        let stamp = timestamp.formatted(.dateTime.month(.abbreviated).day().hour().minute())
        return String(format: L10n.localize("Scanned %@"), stamp)
    }

    /// The OCR text as something worth rendering - nil when empty or whitespace.
    private static func nonEmpty(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

// MARK: - RV.48 the value rendering (docs/DESIGN.md)

/// Turns an `Attachment`'s stored `ExtractionMeta` into the recognised page's
/// rows: one per assigned field, the number in DIN and its unit subordinate,
/// money amount-then-symbol with U+00A0. A field the parse did not assign is
/// absent, never a blank row (hard rule 13).
enum AttachmentValueFormat {
    struct Row: Identifiable {
        let ref: FieldRef
        let label: String
        let value: Value
        var id: FieldRef { ref }
    }

    enum Value {
        /// A numeric figure (DIN) with an optional subordinate unit/symbol.
        case numeric(figure: String, unit: String?)
        /// A non-numeric value (date, fuel kind, currency) in SF Pro.
        case plain(String)
    }

    /// The reading order of the fields (docs/SCHEMA.md vocabulary): what/where/
    /// when, then quantity, then money, then currency.
    private static let order: [FieldRef] = [
        .date, .fuelKind, .volume, .unitPrice, .total, .currency, .station, .vendor, .energy,
    ]

    static func rows(from meta: ExtractionMeta?) -> [Row] {
        guard let meta, meta.hasAssignedValue else { return [] }
        let currency = currency(in: meta.fields)
        let rank = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($0.element, $0.offset) })
        return meta.assignedFields
            .sorted { (rank[$0.key] ?? Int.max) < (rank[$1.key] ?? Int.max) }
            .map { ref, extraction in
                Row(ref: ref, label: label(ref), value: value(ref, extraction.value, currency: currency))
            }
    }

    private static func label(_ ref: FieldRef) -> String {
        switch ref {
        case .date: return L10n.localize("Date")
        case .fuelKind: return L10n.localize("Fuel")
        case .volume: return L10n.localize("Litres")
        case .unitPrice: return L10n.localize("Price/L")
        case .total: return L10n.localize("Total")
        case .currency: return L10n.localize("Currency")
        case .station: return L10n.localize("Station")
        case .vendor: return L10n.localize("Vendor")
        case .energy: return L10n.localize("Energy")
        case .lineItem(let n): return "\(L10n.localize("Row %@")) \(n)"
        }
    }

    private static func value(_ ref: FieldRef, _ value: FieldValue?, currency: CurrencyCode?) -> Value {
        guard let value else { return .plain("") }
        switch value {
        case .money(let amount):
            let figure = ManualFillUpFormat.decimal(amount, fractionDigits: ref == .unitPrice ? 3 : 2)
            let symbol = currency.map { AddVehicleSupport.currencySymbol(for: $0) } ?? ""
            return .numeric(figure: figure, unit: symbol.isEmpty ? nil : symbol)
        case .number(let number):
            switch ref {
            case .volume:
                return .numeric(figure: ManualFillUpFormat.decimal(number, fractionDigits: 2),
                                unit: L10n.volumeUnit(.l))
            case .energy:
                return .numeric(figure: ManualFillUpFormat.decimal(number, fractionDigits: 2),
                                unit: L10n.kWh)
            default:
                return .numeric(figure: ManualFillUpFormat.decimal(number, fractionDigits: 2), unit: nil)
            }
        case .text(let text):
            if ref == .date, let parsed = ConfirmDate.parse(text) {
                return .plain(parsed.formatted(.dateTime.month(.abbreviated).day().year()))
            }
            return .plain(text)
        case .fuelKind(let kind):
            return .plain(kind.inboxLabel)
        case .currency(let code):
            return .plain(code.rawValue)
        }
    }

    /// The currency the parse read, from the sibling `.currency` field - the
    /// money figures' own currency (hard rule 3), never a guessed one.
    private static func currency(in fields: [FieldRef: FieldExtraction]) -> CurrencyCode? {
        guard case .currency(let code)? = fields[.currency]?.value else { return nil }
        return code
    }
}

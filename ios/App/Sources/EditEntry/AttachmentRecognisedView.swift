import SwiftUI
import TankbookCore

/// The attachment viewer's second page (RV.17): what the receipt carried when
/// it was read - the raw OCR lines and the scan timestamp, already persisted on
/// the `Attachment` (`ocrText`, `extractedTimestamp`). This is presentation of
/// STORED data, never re-recognition: the viewer must not re-run OCR, because a
/// fresh read could contradict values the user has already confirmed (hard rule
/// 13) and the whole point of the viewer is to look, not to re-derive.
///
/// The product owner's framing: the recognised data is "just an additional
/// photo" - a full page reached by swiping, never chrome overlaid on the
/// receipt image. When the attachment carries nothing recognised this view is
/// not created at all (the pager in `AttachmentViewerView` never adds the page),
/// so the surface is absent rather than empty.
struct AttachmentRecognisedView: View {
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
                if let ocr = Self.nonEmpty(ocrText) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Read from the receipt")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.Palette.inkSoft)
                        Text(ocr)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(Theme.Palette.ink)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("attachmentViewerOcrText")
                    }
                    .padding(Theme.Spacing.cardPadding)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.Palette.dash.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.card)
                            .stroke(Theme.Palette.hairline, lineWidth: 1)
                    )
                }
            }
            .padding(.horizontal, Theme.Spacing.screenMargin)
            .padding(.vertical, 20)
        }
        .background(Theme.Palette.midnight)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("attachmentViewerRecognised")
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

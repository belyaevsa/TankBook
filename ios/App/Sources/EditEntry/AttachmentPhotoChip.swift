import SwiftUI
import TankbookCore

/// The receipt strip's photo chip (P4.6). Renders the inline thumbnail carried
/// inside the Attachment payload - zero blob fetches - and, while the full
/// rendition blob has not landed, overlays a "photo syncing" veil with a
/// spinner. The chip is decorative: the entry stays openable and editable
/// throughout, because nothing is ever blocked on a photo (hard rule 1).
struct AttachmentPhotoChip: View {
    let attachment: Attachment
    let blobAvailable: Bool

    private var showShimmer: Bool {
        // The shimmer is specifically "the thumbnail arrived (in the payload)
        // but the full rendition has not landed" (docs/SYNC.md). No thumbnail
        // means a local capture whose blob is either present or simply has no
        // chip to shimmer over - never the syncing state.
        attachment.kind == .photo && attachment.thumbnailBase64 != nil && !blobAvailable
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(Theme.Palette.dash)

            if let image = thumbnailImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 44, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                Image(systemName: attachment.kind == .pdf ? "doc.text" : "photo")
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.inkSoft)
            }

            if showShimmer {
                veil
            }
        }
        .frame(width: 44, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(showShimmer ? L10n.localize("Photo syncing") : L10n.localize("Receipt photo"))
        .accessibilityIdentifier(showShimmer ? "attachmentPhotoSyncing" : "attachmentPhotoChip")
    }

    private var thumbnailImage: UIImage? {
        guard let base64 = attachment.thumbnailBase64,
              let data = Data(base64Encoded: base64) else { return nil }
        return UIImage(data: data)
    }

    /// A translucent veil + spinner over the thumbnail - the visual "this is on
    /// its way", never a block. Static in a screenshot (the spinner glyph alone
    /// reads as "syncing"), and it never gates the entry.
    private var veil: some View {
        ZStack {
            Theme.Palette.midnight.opacity(0.55)
            ProgressView()
                .controlSize(.mini)
                .tint(Theme.Palette.inkSoft)
        }
    }
}

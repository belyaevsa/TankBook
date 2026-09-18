import SwiftUI
import TankbookCore

// MARK: - The "How to export" link and the inconsistent-dates card (RV.85)

extension ImportSourceView {
    /// The shared "How to export" link into the source app's guide page
    /// (PJ.33). `Text` is a literal so the label localises (never a `String`).
    func helpLink(_ url: URL, identifier: String) -> some View {
        Link(destination: url) {
            HStack(spacing: 6) {
                Image(systemName: "questionmark.circle")
                    .font(.caption)
                Text("How to export")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(Theme.Palette.action)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .accessibilityIdentifier(identifier)
    }

    /// The mixed-date-order file's own card (RV.85). Lives in an extension so
    /// `parseErrorCard`'s switch and this struct stay under the lint ceilings.
    var inconsistentDatesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("This file mixes two date formats.")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.Palette.warn)
            Text("Some dates only read one way, others the other way.")
                .font(.caption)
                .foregroundStyle(Theme.Palette.inkSoft)
                .lineSpacing(1.4)
            Text("Fix the dates in the export, then pick the file again.")
                .font(.caption)
                .foregroundStyle(Theme.Palette.inkSoft)
                .lineSpacing(1.4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .formCard()
        .accessibilityIdentifier("importInconsistentDatesCard")
    }
}

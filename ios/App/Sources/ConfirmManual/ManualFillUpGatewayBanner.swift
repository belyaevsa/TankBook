import SwiftUI
import TankbookCore

// MARK: - RV.57 the "proceed now" note (replaces RV.8's banner)

/// The Confirm sheet's note that a more reliable reading may still arrive
/// (docs/JOURNEYS.md F4, amended by the RV.57 product-owner ruling). It is a
/// hint, never an error (hard rule 7): `inkSoft`, dismissable, carries no
/// spinner - the whole point is that the user need not wait - and blocks
/// nothing. Save stays reachable with the note on screen.
///
/// It replaces RV.8's `GatewayReadingBanner`, whose spinner read as "wait" and
/// whose copy read as "keep typing" rather than the product owner's "proceed
/// now; the more reliable data will come later". The presence rule lives in
/// core (`GatewayProceedNote.shouldShow`) so it tests at L1; this file is only
/// the rendering and the dismiss affordance. Visibility (the in-flight phase
/// AND "not yet dismissed") is the parent's decision; the note renders whatever
/// it is handed.
struct GatewayProceedNoteView: View {
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("A more reliable reading may still arrive. You can proceed now.")
                .font(.footnote)
                .foregroundStyle(Theme.Palette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.Palette.inkSoft)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
            .accessibilityIdentifier("gatewayProceedNoteDismissButton")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.Palette.dash)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("gatewayProceedNote")
    }
}

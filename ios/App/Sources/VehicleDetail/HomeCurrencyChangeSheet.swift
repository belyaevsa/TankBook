import SwiftUI
import TankbookCore

/// RV.177/RV.178 - the home-currency question, drawn as a custom sheet instead
/// of the system alert RV.152 shipped.
///
/// The alert could not tell its two answers apart. Neither button carried a
/// role, so iOS tinted both with the app accent - and the accent IS taillight
/// red. The irreversible "Convert the log" and the harmless "Keep the entries
/// as they are" rendered identically, and `.destructive` could not separate
/// them because it renders the same colour as the accent. The hierarchy is
/// therefore structural: a filled primary against a quiet outlined secondary
/// (docs/DESIGN.md -> Consequential actions).
///
/// RV.178: the currency change is already decided by tapping Save, so this
/// sheet asks only what to do with the entries that already exist and offers
/// NO cancel. Both answers commit, and the sheet refuses to be dismissed
/// without one - `.interactiveDismissDisabled(true)` and no close affordance.
/// A swipe-down that silently abandoned the question would be worse than the
/// alert it replaces, which at least forced a choice.
struct HomeCurrencyChangeSheet: View {
    let title: String
    let pendingCount: Int
    let onConvert: () -> Void
    let onKeep: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("homeCurrencyChangeTitle")
                Text(L10n.homeCurrencyChangeMessage(pending: pendingCount))
                    .font(.subheadline)
                    .foregroundStyle(Theme.Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("homeCurrencyChangeMessage")
                actions
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Theme.Palette.midnight)
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .interactiveDismissDisabled(true)
        .accessibilityIdentifier("homeCurrencyChangeSheet")
    }

    /// The two answers, in the order they must be read: the filled primary is
    /// "Convert the log", the quiet secondary is "Keep the entries as they
    /// are". The treatments differ by structure - a solid `taillight` fill
    /// against a hairline outline - never by colour alone, because the accent
    /// and the destructive red are the same colour here.
    private var actions: some View {
        VStack(spacing: 10) {
            Button(action: onConvert) {
                Text("Convert the log")
                    .font(.body.weight(.bold))
                    .foregroundStyle(Theme.Palette.midnight)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Theme.Palette.taillight)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("homeCurrencyChangeConvertButton")

            Button(action: onKeep) {
                Text("Keep the entries as they are")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.Palette.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Theme.Palette.midnight)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Theme.Palette.hairline, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("homeCurrencyChangeKeepButton")
        }
        .padding(.top, 4)
    }
}

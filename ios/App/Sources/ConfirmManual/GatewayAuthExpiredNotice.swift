import SwiftUI
import TankbookCore

// MARK: - RV.65 the "sign in to use cloud reading" notice

/// The Confirm sheet's name for a dead session on `/extract` (docs/ERRORS.md ->
/// Confirm, the RV.65 row; docs/JOURNEYS.md F4, amended). The cloud half of the
/// reading was refused with a 401 the refresh could not fix - the refresher was
/// rejected, or it handed back the same bearer - so the sheet stops treating the
/// gateway as available and tells the user the honest reason: the session cannot
/// authenticate.
///
/// It is an error that names its next step (hard rule 7) - "sign in" - and
/// survives being ignored: `warn`, non-blocking, dismissable, and Save stays
/// reachable the whole time (hard rules 1 and 15: the on-device result stands,
/// typing is a peer door, and no screen is sync-gated). The copy is a whole
/// localised phrase per language (hard rule 10). The actual Sign in action lives
/// on the Settings account card (RV.26); this notice is the capture surface's
/// name for the same condition.
struct GatewayAuthExpiredNoticeView: View {
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.system(size: 15))
                .foregroundStyle(Theme.Palette.warn)
                .padding(.top, 1)
            Text(L10n.gatewayAuthExpiredNotice)
                .font(.footnote)
                .foregroundStyle(Theme.Palette.ink)
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
            .accessibilityIdentifier("gatewayAuthExpiredNoticeDismissButton")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.Palette.warn.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.Palette.warn.opacity(0.35), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("gatewayAuthExpiredNotice")
    }
}

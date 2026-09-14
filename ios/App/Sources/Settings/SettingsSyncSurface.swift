import SwiftUI
import TankbookCore

/// The signed-in sync surface below the account card: "Sync now", the transport
/// issue cards (revoked / quota / server) and the flagged count-and-link row
/// (docs/SYNC.md -> the three parts). Extracted from `SettingsView` so each view
/// stays within the lint body-length budget.
struct SettingsSyncSurface: View {
    @Environment(AppSync.self) private var sync
    @Environment(AppConfigService.self) private var config
    @Binding var showsSignIn: Bool

    var body: some View {
        VStack(spacing: 12) {
            if config.allowsServerBacked {
                syncNowRow
                issueCards
            } else {
                // P6.18b: the `.required` notice replaces the sync affordance -
                // the server has stopped supporting this build, so "Sync now"
                // would be refused anyway (the same set 426 withholds,
                // docs/CONFIG.md). Non-dismissible, names its next step. The
                // queue stays dirty; nothing is lost.
                UpdateRequiredNotice()
            }
            if sync.flaggedCount > 0 {
                flaggedRow
            }
            if sync.rejectedCount > 0 {
                rejectedRow
            }
        }
    }

    /// "Sync now" - the manual trigger. Idempotency is the coordinator's
    /// guarantee; the spinner is driven by `isSyncing`. Offline is not an
    /// error: the row settles back to "Will sync when you're back online".
    private var syncNowRow: some View {
        Button {
            Task { await sync.syncNow() }
        } label: {
            HStack(spacing: 8) {
                if sync.isSyncing {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Theme.Palette.inkSoft)
                } else {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.subheadline)
                        .foregroundStyle(Theme.Palette.action)
                }
                Text("Sync now")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.Palette.ink)
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
            .formCard()
        }
        .buttonStyle(.plain)
        .disabled(sync.isSyncing)
        .accessibilityIdentifier("settingsSyncNowButton")
    }

    @ViewBuilder
    private var issueCards: some View {
        switch sync.status {
        case .deviceRevoked:
            transportCard(
                icon: "person.crop.circle.badge.exclamationmark",
                iconColor: Theme.Palette.warn,
                message: L10n.deviceRevokedMessage,
                identifier: "settingsRevokedCard"
            ) {
                Button("Sign in") { showsSignIn = true }
                    .buttonStyle(.plain)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.Palette.action)
                    .accessibilityIdentifier("settingsRevokedSignInButton")
            }
            .id(SettingsScrollTarget.revokedCard)
        case .authExpired:
            // The expired-session card renders in the account card's signed-out
            // branch, so this status never reaches the signed-in issue cards.
            EmptyView()
        case .quotaFull:
            // RV.70: the card's action was a "Tankbook Pro" link to a blank
            // screen (Route.paywall resolved to LeafContent - Color.clear). Pro
            // is cut from v1 (docs/STORE.md §5), so the honest next step names
            // the wait and the resilience instead of a purchase that does not
            // exist (hard rule 7): the disclosure stays amber (the state is
            // attention), the next step is a sentence, never a dead button.
            transportCard(
                icon: "photo.badge.exclamationmark",
                iconColor: Theme.Palette.warn,
                message: L10n.quotaFull(percent: sync.surfaceState.quotaUsedPercent ?? 100),
                identifier: "settingsQuotaCard",
                messageIdentifier: "settingsQuotaCardMessage"
            ) {
                Text(L10n.quotaNextStep)
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.inkSoft)
                    .lineSpacing(1.5)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("settingsQuotaNextStep")
            }
            .id(SettingsScrollTarget.quotaCard)
        case .serverUnreachable:
            transportCard(
                icon: "wifi.exclamationmark",
                iconColor: Theme.Palette.inkSoft,
                message: L10n.syncServiceUnreachableMessage,
                identifier: "settingsServerCard",
                messageIdentifier: "settingsServerCardMessage"
            ) {
                Button("Try again") {
                    Task { await sync.syncNow() }
                }
                .buttonStyle(.plain)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.Palette.action)
                .accessibilityIdentifier("settingsServerRetryButton")
            }
        case .synced, .waitingToSync:
            if SyncSurface.isOfflineWithQueue(sync.surfaceState) {
                offlineHint
            } else if SyncSurface.lowPowerReason(sync.surfaceState) {
                // P6.8: a Low Power queue is the offline-queue's sibling - the
                // background cycle that would drain it is postponed, not lost.
                lowPowerHint
            } else {
                EmptyView()
            }
        }
    }

    /// "Will sync when you're back online" - the offline hint, not an error.
    private var offlineHint: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.slash")
                .font(.caption)
                .foregroundStyle(Theme.Palette.inkSoft)
            Text("Will sync when you're back online")
                .font(.caption)
                .foregroundStyle(Theme.Palette.inkSoft)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .formCard()
        .accessibilityIdentifier("settingsOfflineHint")
    }

    /// P6.8: the Low Power explanation row (docs/SYNC.md -> Low Power Mode).
    /// Reassurance, never a warning - `inkSoft` like the offline hint, never
    /// amber, no badge, no toast (hard rule 8). It names what is deferred and
    /// that it resumes automatically; a user who turned the mode on chose this,
    /// so the app agreeing with them is not an error state.
    private var lowPowerHint: some View {
        HStack(spacing: 8) {
            Image(systemName: "bolt")
                .font(.caption)
                .foregroundStyle(Theme.Palette.inkSoft)
            Text(L10n.lowPowerDeferredMessage)
                .font(.caption)
                .foregroundStyle(Theme.Palette.inkSoft)
                .lineSpacing(1.5)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .formCard()
        .accessibilityIdentifier("settingsLowPowerHint")
    }

    /// A transport-issue card (revoked / quota / server): the account-level
    /// issues that belong in Settings with their next step (docs/SYNC.md).
    private func transportCard(icon: String, iconColor: Color, message: String,
                               identifier: String,
                               messageIdentifier: String? = nil,
                               @ViewBuilder action: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 15))
                    .foregroundStyle(iconColor)
                    .padding(.top, 1)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.ink)
                    .lineSpacing(1.5)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(messageIdentifier ?? "")
                Spacer(minLength: 0)
            }
            action()
        }
        .padding(14)
        .formCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }

    /// "N entries need a look" - a derived count and a link only. Settings
    /// never resolves a conflict; the badge lives where the data lives.
    private var flaggedRow: some View {
        NavigationLink(value: Route.flaggedEntries) {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .foregroundStyle(Theme.Palette.warn)
                Text(L10n.flaggedEntries(sync.flaggedCount))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.Palette.ink)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.Palette.inkSoft)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
            .formCard()
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("settingsFlaggedRow")
    }

    /// "N entries could not sync" (RV.284, docs/ERRORS.md -> Settings). A count
    /// and a next step only - Settings never fixes these either; the badge lives
    /// on the entry row. The server rejected these structurally, so they stay on
    /// this phone until edited or the app updates. No navigation: there is no
    /// list of rejected entries, the rows themselves carry the badge.
    private var rejectedRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "icloud.slash")
                .font(.subheadline)
                .foregroundStyle(Theme.Palette.warn)
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.rejectedEntries(sync.rejectedCount))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.Palette.ink)
                    .accessibilityIdentifier("settingsRejectedCount")
                Text(L10n.rejectedEntriesHint)
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.inkSoft)
                    .accessibilityIdentifier("settingsRejectedHint")
            }
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .formCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settingsRejectedRow")
    }
}

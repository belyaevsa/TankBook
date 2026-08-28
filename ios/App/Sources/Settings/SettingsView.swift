import SwiftUI
import TankbookCore

/// The Settings screen (P4.9b) - design/screens/Settings.dc.html plus the
/// normative sync surface from docs/SYNC.md -> "The Settings sync surface".
/// Reached from the Home gear (docs/SCREENMAP.md: Home -->|gear| Settings).
///
/// The three parts of the sync surface, split exactly as the doc prescribes:
///
/// 1. **Status** - a relative timestamp on the account card, reassurance and
///    never a warning (it does not turn amber with age; a week offline is the
///    same as an hour).
/// 2. **"Sync now"** - an idempotent manual trigger (the core `SyncCoordinator`
///    makes a repeated tap inert), offline not an error, never the only path.
/// 3. **Issues, split by class** - transport issues (410 revoked, blob-quota
///    429, server down) belong here as cards with their next step; domain
///    issues (S1-S5 flagged records) show a derived **count and a link only**
///    to the Log filtered to flagged entries. Settings resolves nothing - a
///    resolution control here is a bug (hard rule 8).
struct SettingsView: View {
    @Environment(AppSync.self) private var sync
    @State private var showsSignIn = false
    @State private var didSeed = false

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                accountCard
                if sync.signedIn {
                    SettingsSyncSurface(showsSignIn: $showsSignIn)
                }
                preferencesCard
                yourDataSection
                proCard
                aboutCard
                footer
            }
            .padding(.horizontal, Theme.Spacing.screenMargin)
            .padding(.top, 4)
            .padding(.bottom, 32)
        }
        .background(Theme.Palette.midnight)
        .task {
            if !didSeed {
                didSeed = true
                SettingsTestSeed.seedIfRequested(sync: sync)
            }
            await sync.refresh()
        }
        .sheet(isPresented: $showsSignIn) {
            SignInFlowHost()
        }
    }

    // MARK: - Account card

    @ViewBuilder
    private var accountCard: some View {
        if sync.signedIn {
            NavigationLink(value: Route.accountDevices) {
                HStack(spacing: 12) {
                    avatar
                    VStack(alignment: .leading, spacing: 1) {
                        Text(L10n.accountTitle(email: sync.session?.email,
                                               provider: sync.session?.provider ?? .apple))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.Palette.ink)
                            .accessibilityIdentifier("settingsAccountTitle")
                        accountStatusLines
                    }
                    Spacer(minLength: 8)
                    chevron
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
                .contentShape(Rectangle())
                .formCard()
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("settingsAccountCard")
        } else {
            Button {
                showsSignIn = true
            } label: {
                HStack(spacing: 12) {
                    avatar
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Sign in to sync")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.Palette.ink)
                    }
                    Spacer(minLength: 8)
                    chevron
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
                .contentShape(Rectangle())
                .formCard()
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("settingsSignInButton")
        }
    }

    private var avatar: some View {
        ZStack {
            Circle()
                .fill(Theme.Palette.midnight)
                .overlay(Circle().stroke(Theme.Palette.hairline, lineWidth: 1))
            Image(systemName: "person")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Theme.Palette.inkSoft)
        }
        .frame(width: 40, height: 40)
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.Palette.inkSoft)
    }

    /// The account card's status lines. Line one is the reassurance text
    /// (docs/SYNC.md: never amber with age, a long queue is not an error).
    /// Line two is the P6.11 server-ahead notice when a server newer than this
    /// app refused or paced the sync: version-first copy on the update cases,
    /// and `.rateLimited` as a wait in the ordinary status colour - never
    /// amber, never an update prompt. A refused push always leaves a queue
    /// (S7), so line one hides only when there is nothing waiting and a notice
    /// is showing.
    @ViewBuilder
    private var accountStatusLines: some View {
        let notice = sync.serverNotice
        if notice == .none || sync.dirtyCount > 0 {
            Text(statusLine)
                .font(.caption)
                .foregroundStyle(Theme.Palette.inkSoft)
                .accessibilityIdentifier("settingsSyncStatus")
        }
        if notice != .none {
            Text(notice.text)
                .font(.caption)
                .foregroundStyle(notice.isAttention ? Theme.Palette.warn : Theme.Palette.inkSoft)
                .accessibilityIdentifier(notice.accessibilityIdentifier)
        }
    }

    /// The account card's reassurance status line: reassurance, never amber
    /// (docs/SYNC.md). `inkSoft` is the ordinary status colour - age and queue
    /// length never move it to `warn`.
    private var statusLine: String {
        switch sync.status {
        case .synced:
            return L10n.syncedAgo(lastSyncDate: sync.lastSyncDate)
        case .waitingToSync:
            return L10n.waitingToSync(sync.dirtyCount)
        case .serverUnreachable, .quotaFull:
            return L10n.syncedAgo(lastSyncDate: sync.lastSyncDate)
        case .deviceRevoked:
            return L10n.localize("Signed out")
        }
    }

    // MARK: - Appearance / Language / Notifications

    private var preferencesCard: some View {
        VStack(spacing: 0) {
            valueRow("Appearance", value: "Dark", identifier: "settingsAppearanceRow")
            CardDivider()
            valueRow("Language", value: "English", identifier: "settingsLanguageRow")
            CardDivider()
            valueRow("Notifications", value: "Reminders only", identifier: "settingsNotificationsRow")
        }
        .formCard()
    }

    /// A static value row (its destination screen is another task). The value
    /// is drawn like the artboard: inkSoft with a trailing chevron.
    private func valueRow(_ label: LocalizedStringKey, value: LocalizedStringKey,
                          identifier: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(Theme.Palette.ink)
            Spacer(minLength: 8)
            Text(value)
                .font(.footnote)
                .foregroundStyle(Theme.Palette.inkSoft)
            chevron
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }

    // MARK: - Your data

    private var yourDataSection: some View {
        VStack(spacing: 8) {
            SectionEyebrow("Your data")
            VStack(spacing: 0) {
                NavigationLink(value: Route.importWizard) {
                    navRow("Import from another app")
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("settingsImportRow")
                CardDivider()
                exportRow
                CardDivider()
                NavigationLink(value: Route.recentlyDeleted) {
                    navRow("Recently deleted")
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("settingsRecentlyDeletedRow")
            }
            .formCard()
        }
    }

    /// "Export everything · always free" - a system share sheet (a leaf). The
    /// export body is a later task; the row renders the artboard's label and
    /// promise now, so the "always free" guarantee is visible before the share
    /// sheet exists.
    private var exportRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text("Export everything")
                .font(.subheadline)
                .foregroundStyle(Theme.Palette.ink)
            Text("·")
                .font(.subheadline)
                .foregroundStyle(Theme.Palette.inkSoft.opacity(0.6))
            Text("always free")
                .font(.caption)
                .foregroundStyle(Theme.Palette.inkSoft)
            Spacer(minLength: 8)
            chevron
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("settingsExportRow")
    }

    private func navRow(_ label: LocalizedStringKey) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(Theme.Palette.ink)
            Spacer(minLength: 8)
            chevron
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    // MARK: - Pro & About

    private var proCard: some View {
        NavigationLink(value: Route.paywall) {
            HStack(spacing: 12) {
                Image(systemName: "star")
                    .font(.system(size: 17))
                    .foregroundStyle(Theme.Palette.taillight)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Tankbook Pro")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.Palette.ink)
                    Text("Unlimited cars · cloud reading for tough receipts")
                        .font(.caption)
                        .foregroundStyle(Theme.Palette.inkSoft)
                }
                Spacer(minLength: 8)
                chevron
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
            .formCard()
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("settingsProCard")
    }

    private var aboutCard: some View {
        NavigationLink(value: Route.about) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("About & feedback")
                    .font(.subheadline)
                    .foregroundStyle(Theme.Palette.ink)
                Spacer(minLength: 8)
                Text(verbatim: version)
                    .font(.footnote)
                    .foregroundStyle(Theme.Palette.inkSoft)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
            .formCard()
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("settingsAboutRow")
    }

    /// The bundle version, read (never hardcoded) for the "v1.0" row.
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "1.0"
    }

    // MARK: - Footer

    private var footer: some View {
        Text("Per-car settings (currency, units, tank size) live on each car in the Garage.")
            .font(.caption)
            .foregroundStyle(Theme.Palette.inkSoft.opacity(0.7))
            .multilineTextAlignment(.center)
            .padding(.top, 2)
            .accessibilityIdentifier("settingsFooter")
    }
}

/// The signed-in sync surface below the account card: "Sync now", the transport
/// issue cards (revoked / quota / server) and the flagged count-and-link row
/// (docs/SYNC.md -> the three parts). Extracted from `SettingsView` so each view
/// stays within the lint body-length budget.
private struct SettingsSyncSurface: View {
    @Environment(AppSync.self) private var sync
    @Binding var showsSignIn: Bool

    var body: some View {
        VStack(spacing: 12) {
            syncNowRow
            issueCards
            if sync.flaggedCount > 0 {
                flaggedRow
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
        case .quotaFull:
            transportCard(
                icon: "photo.badge.exclamationmark",
                iconColor: Theme.Palette.warn,
                message: L10n.quotaFull(percent: sync.forcedQuotaPercent ?? 95),
                identifier: "settingsQuotaCard"
            ) {
                NavigationLink("Tankbook Pro", value: Route.paywall)
                    .buttonStyle(.plain)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.Palette.action)
                    .accessibilityIdentifier("settingsQuotaProButton")
            }
        case .serverUnreachable:
            transportCard(
                icon: "wifi.exclamationmark",
                iconColor: Theme.Palette.inkSoft,
                message: L10n.syncServiceUnreachableMessage,
                identifier: "settingsServerCard"
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

    /// A transport-issue card (revoked / quota / server): the account-level
    /// issues that belong in Settings with their next step (docs/SYNC.md).
    private func transportCard(icon: String, iconColor: Color, message: String,
                               identifier: String,
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
}

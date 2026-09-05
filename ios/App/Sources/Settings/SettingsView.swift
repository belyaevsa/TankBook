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
    @State private var isExporting = false
    @State private var shareable: ExportShareable?
    @State private var exportFailure: ExportFailure?
    @State private var showsLanguagePicker = false
    @State private var languageStore = LanguagePreferenceStore()
    @State private var selectedLanguage: String?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 12) {
                    accountCard
                        .id(SettingsScrollTarget.account)
                    if sync.signedIn {
                        SettingsSyncSurface(showsSignIn: $showsSignIn)
                        SignOutSection()
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
            .onAppear { scrollToRequestedCard(proxy) }
            .onChange(of: sync.settingsScrollTarget) { _, _ in
                scrollToRequestedCard(proxy)
            }
        }
        .task {
            if !didSeed {
                didSeed = true
                #if DEBUG
                SettingsTestSeed.seedIfRequested(sync: sync)
                SettingsTestSeed.setPendingLanguageForScreenshotIfRequested()
                #endif
            }
            selectedLanguage = languageStore.selectedLanguage
            await sync.refresh()
            presentExportShareIfRequested()
            presentLanguagePickerIfRequested()
        }
        .sheet(isPresented: $showsSignIn,
               onDismiss: {
                   // PJ.13: a `.sheet` does not re-trigger the presenter's
                   // `.task` on iOS 26 (the P6.18b finding, pinned by a UI
                   // test), so the card would otherwise stay on its pre-sign-in
                   // state. The sign-in flow's first push leaves the session in
                   // the Keychain and the outcome on the coordinator; this
                   // refresh is what the card reads them from.
                   Task { await sync.refresh() }
               },
               content: { SignInFlowHost() })
        .sheet(isPresented: $showsLanguagePicker,
               content: {
                   LanguagePickerView(store: languageStore,
                                      selection: $selectedLanguage,
                                      promptOnOpen: ProcessInfo.processInfo.arguments
                                          .contains("-languagePickerShowPrompt"))
               })
        .exportFlow(shareable: $shareable, failure: $exportFailure,
                    retry: buildAccountExport)
    }

    // MARK: - Account card

    /// RV.22: scrolls to the card the sync chip's Settings tap named (state 2
    /// "Settings, scrolled to the card naming the fix"). A deferred scroll so
    /// the pushed content has laid out before `scrollTo` runs; clears the target
    /// after one use so a later gear-open does not re-scroll. A target whose
    /// card is not in the hierarchy (the chip's forced state diverging from the
    /// real surface) is a no-op.
    private func scrollToRequestedCard(_ proxy: ScrollViewProxy) {
        guard let target = sync.settingsScrollTarget else { return }
        DispatchQueue.main.async {
            proxy.scrollTo(target, anchor: .top)
            sync.settingsScrollTarget = nil
        }
    }

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
        } else if sync.deviceRevoked {
            // RV.58: a 410 is terminal - the session was dropped and a revoked
            // mark persisted, so this card renders for the revoked device even
            // though it is signed out (ERRORS.md -> Settings, the 410 row). Its
            // "Sign in" re-attaches the device row; the local log is untouched
            // (hard rules 7 and 8). Never the plain guest card, never "update".
            AccountSignInCard(
                message: L10n.deviceRevokedMessage,
                cardIdentifier: "settingsRevokedCard",
                buttonIdentifier: "settingsRevokedSignInButton",
                scrollTarget: .revokedCard,
                signIn: { showsSignIn = true }
            )
        } else if sync.authExpired {
            // The session expired and the refresh was rejected (PR.1): the user
            // must sign in again. A card with its next step, never "update the
            // app" (hard rule 7) - the app is current, the token is not.
            AccountSignInCard(
                message: L10n.authExpiredMessage,
                cardIdentifier: "settingsAuthExpiredCard",
                buttonIdentifier: "settingsAuthExpiredSignInButton",
                scrollTarget: nil,
                signIn: { showsSignIn = true }
            )
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
    /// is showing. Line three is the J11a just-signed-in confirmation
    /// (docs/JOURNEYS.md J11a -> Confirm), shown until the next sign-out.
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
        if sync.justSignedIn {
            Text(L10n.garageFollowsAccountMessage)
                .font(.caption)
                .foregroundStyle(Theme.Palette.inkSoft)
                .accessibilityIdentifier("settingsSignedInConfirmation")
        }
    }

    /// The account card's reassurance status line: reassurance, never amber
    /// (docs/SYNC.md). `inkSoft` is the ordinary status colour - age and queue
    /// length never move it to `warn`.
    private var statusLine: String {
        switch sync.status {
        case .synced:
            // PJ.13: the reassurance gains the device count when it is known
            // ("Synced just now · 1 device", docs/JOURNEYS.md J11a).
            return L10n.syncedStatus(lastSyncDate: sync.lastSyncDate,
                                     deviceCount: sync.deviceCount)
        case .waitingToSync:
            // P6.8: the Low Power reason rides on S7's existing row
            // (docs/SYNC.md -> Low Power Mode: "Waiting to sync · 5 changes ·
            // Low Power Mode is on") - a reason, never a severity.
            return L10n.waitingToSync(sync.dirtyCount,
                                      lowPowerReason: SyncSurface.lowPowerReason(sync.surfaceState))
        case .serverUnreachable, .quotaFull:
            return L10n.syncedAgo(lastSyncDate: sync.lastSyncDate)
        case .deviceRevoked, .authExpired:
            return L10n.localize("Signed out")
        }
    }

    // MARK: - Appearance / Language / Notifications

    private var preferencesCard: some View {
        VStack(spacing: 0) {
            valueRow("Appearance", value: "Dark", identifier: "settingsAppearanceRow")
            CardDivider()
            languageRow
            CardDivider()
            valueRow("Notifications", value: "Reminders only", identifier: "settingsNotificationsRow")
        }
        .formCard()
    }

    /// The language row (docs/TASKS.md RV.24); RV.42: it carries the restart
    /// prompt while the stored choice differs from the running language.
    private var languageRow: some View {
        LanguageRow(value: languageValue,
                    pendingRestart: LanguagePreference.isPendingRestart(
                        storedLanguage: languageStore.storedLanguage,
                        runningLanguage: LanguageDisplay.currentCode),
                    action: { showsLanguagePicker = true })
    }

    /// The language the row displays: the user's stored choice wins; without one
    /// the app follows the system (docs/TASKS.md RV.24 - the L1 rule, resolved).
    private var languageValue: String {
        if let code = selectedLanguage {
            return LanguageDisplay.name(code)
        }
        return LanguageDisplay.name(LanguageDisplay.currentCode)
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

    /// "Export everything · always free" (PJ.36) - a system share sheet. The
    /// row builds the WHOLE-ACCOUNT archive (`scope: .account`, every car and
    /// every tombstone) and hands the directory to the share sheet; a disk-full
    /// failure surfaces its message as a state, never a crash (docs/ERRORS.md ->
    /// Settings). The "always free" promise is the row's label AND the only
    /// truth: there is no Pro gate anywhere on this path (VISION.md).
    private var exportRow: some View {
        Button(action: buildAccountExport) {
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
                if isExporting {
                    ProgressView().controlSize(.small).tint(Theme.Palette.inkSoft)
                } else {
                    chevron
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isExporting)
        .accessibilityIdentifier("settingsExportRow")
    }

    private func buildAccountExport() {
        guard !isExporting else { return }
        isExporting = true
        Task {
            do {
                shareable = ExportShareable(items: [try ExportBuilder.buildAccountArchive()])
            } catch {
                exportFailure = ExportFailure.map(error)
            }
            isExporting = false
        }
    }

    /// DEBUG/test-only: `-presentExportShare` opens the whole-account share
    /// sheet a beat after Settings appears, so a screenshot can show it without
    /// a UI test driving a tap (`simctl` cannot tap). Routes through the exact
    /// method the button calls; production never passes the argument.
    private func presentExportShareIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-presentExportShare") else { return }
        Task {
            try? await Task.sleep(for: .milliseconds(600))
            buildAccountExport()
        }
    }

    /// DEBUG/screenshot only: `-presentLanguagePicker` opens the language picker
    /// a beat after Settings appears (simctl cannot tap). `-languagePickerShowPrompt`
    /// preselects a language so the restart prompt renders.
    private func presentLanguagePickerIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-presentLanguagePicker") else { return }
        Task {
            try? await Task.sleep(for: .milliseconds(600))
            if ProcessInfo.processInfo.arguments.contains("-languagePickerShowPrompt") {
                selectedLanguage = LanguageDisplay.offered.first
            }
            showsLanguagePicker = true
        }
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
}

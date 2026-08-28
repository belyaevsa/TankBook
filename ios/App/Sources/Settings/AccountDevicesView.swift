import os
import SwiftUI
import TankbookCore

/// The Account & devices screen (P6.4) - Settings' signed-in target
/// (docs/SCREENMAP.md: Settings -> account card, signed in -> AccountDevices).
/// The device list, revoke, and delete account - the server side already
/// shipped (P4.9a/P4.9b); this is the surface for it.
///
/// Two sentences this screen exists to say correctly:
///
/// 1. **Revoke stops syncing, it erases nothing.** The revoked device gets 410
///    on its next pull and its local data stays on it. The confirm says "It
///    stops syncing with your account. Everything on it stays."
/// 2. **Delete account is a tombstone.** The log on this phone is never
///    touched; the server purges its copy after the grace period. The confirm
///    says exactly that - a user who believes their local log is deleted will
///    not trust the export that still works (docs/ERRORS.md, the delete-account
///    copy matches https://tankbook.live/delete-account/).
///
/// Red appears in exactly one place: the delete-account confirmation inside the
/// system dialog (hard rule 5 - destructive confirmations only). Revoke's
/// confirmation is ordinary (attention, not destruction): nothing is deleted.
struct AccountDevicesView: View {
    @Environment(AppSync.self) private var sync
    @Environment(\.dismiss) private var dismiss

    @State private var model: AccountDevicesModel?
    @State private var pendingRevoke: AccountDevice?
    @State private var showsDeleteConfirm = false
    @State private var didLoad = false

    private static let log = Logger(subsystem: "app.tankbook", category: "accountDevices")

    var body: some View {
        Group {
            if let model {
                content(model)
            } else {
                Color.clear
            }
        }
        .background(Theme.Palette.midnight)
        .navigationTitle("Account & devices")
        .task {
            if model == nil {
                model = AccountDevicesService.makeModel()
            }
            if let model, !didLoad {
                didLoad = true
                await model.load()
            }
        }
        .alert("Revoke this device?",
               isPresented: revokePresented) {
            Button("Revoke") {
                if let device = pendingRevoke {
                    Task { await model?.revoke(device) }
                }
                pendingRevoke = nil
            }
            .accessibilityIdentifier("accountRevokeConfirmButton")
            Button("Cancel", role: .cancel) { pendingRevoke = nil }
        } message: {
            Text(L10n.revokeConfirmationMessage)
        }
        .alert("Delete account?",
               isPresented: $showsDeleteConfirm) {
            Button("Delete account", role: .destructive) {
                Task { await performDelete() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(L10n.deleteAccountConfirmationMessage)
        }
    }

    /// The revoke confirmation binds to whichever device's Revoke was tapped.
    private var revokePresented: Binding<Bool> {
        Binding(
            get: { pendingRevoke != nil },
            set: { if !$0 { pendingRevoke = nil } }
        )
    }

    // MARK: - Content

    private func content(_ model: AccountDevicesModel) -> some View {
        ScrollView {
            VStack(spacing: 12) {
                identityHeader(model)
                devicesSection(model)
                deleteSection(model)
            }
            .padding(.horizontal, Theme.Spacing.screenMargin)
            .padding(.top, 4)
            .padding(.bottom, 32)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.Palette.midnight)
    }

    /// The signed-in identity: the Settings account card's avatar and the
    /// account's display name/provider (docs/API.md -> Auth). Static - the
    /// account's mutations live below.
    private func identityHeader(_ model: AccountDevicesModel) -> some View {
        HStack(spacing: 12) {
            avatar
            VStack(alignment: .leading, spacing: 1) {
                Text(accountTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.Palette.ink)
                    .accessibilityIdentifier("accountDevicesTitle")
                Text(L10n.signedInSubtitle(email: session?.email,
                                           provider: session?.provider ?? .apple))
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.inkSoft)
            }
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .formCard()
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

    private var session: AuthSession? {
        model?.currentSession
    }

    private var accountTitle: String {
        if let email = session?.email { return email }
        return L10n.providerAccountName(session?.provider ?? .apple)
    }

    // MARK: - Devices

    @ViewBuilder
    private func devicesSection(_ model: AccountDevicesModel) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionEyebrow("Devices")
            switch model.phase {
            case .idle, .loading:
                loadingCard
            case .failed(let message):
                failedCard(message, identifier: "accountDevicesLoadError") {
                    Button("Try again") {
                        Task { await model.retry() }
                    }
                    .buttonStyle(.plain)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.Palette.action)
                    .accessibilityIdentifier("accountDevicesRetryButton")
                }
            case .loaded:
                if model.devices.isEmpty {
                    emptyDevicesCard
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(model.devices.enumerated()), id: \.element.id) { index, device in
                            deviceRow(device, model: model)
                            if index < model.devices.count - 1 {
                                CardDivider()
                            }
                        }
                    }
                    .formCard()
                }
            }
        }
    }

    private var loadingCard: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
                .tint(Theme.Palette.inkSoft)
            Text("Loading devices…")
                .font(.caption)
                .foregroundStyle(Theme.Palette.inkSoft)
            Spacer(minLength: 0)
        }
        .padding(14)
        .formCard()
    }

    /// A failed load names its next step (hard rule 7): Try again. Offline is
    /// never an error - the card is a pause, not a wall (F3/S7). The identifier
    /// lives on the MESSAGE text, never the container: a container identifier
    /// propagates down and overrides its children's own identifiers, which would
    /// swallow the retry button's.
    private func failedCard(_ message: String, identifier: String,
                            @ViewBuilder retry: @escaping () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.Palette.inkSoft)
                    .padding(.top, 1)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.ink)
                    .lineSpacing(1.5)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(identifier)
                Spacer(minLength: 0)
            }
            retry()
        }
        .padding(14)
        .formCard()
    }

    private var emptyDevicesCard: some View {
        Text("No devices yet – this account's devices appear here.")
            .font(.caption)
            .foregroundStyle(Theme.Palette.inkSoft)
            .multilineTextAlignment(.center)
            .padding(14)
            .formCard()
    }

    /// One device row. The name is server-supplied runtime data - it sits in
    /// the nominative head of its own line, never inside a prepositional phrase
    /// (docs/LOCALIZATION.md, the P4.7 lesson). The status line is app-composed
    /// (an app-formatted relative day) and separate.
    @ViewBuilder
    private func deviceRow(_ device: AccountDevice, model: AccountDevicesModel) -> some View {
        let isCurrent = model.isCurrentDevice(device)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: Self.platformIcon(device.platform))
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.Palette.inkSoft)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 7) {
                        Text(device.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(device.revoked
                                             ? Theme.Palette.inkSoft
                                             : Theme.Palette.ink)
                            .lineLimit(1)
                        if isCurrent {
                            thisDeviceBadge
                        }
                    }
                    Text(Self.statusLine(device))
                        .font(.caption)
                        .foregroundStyle(device.revoked
                                         ? Theme.Palette.inkSoft
                                         : Theme.Palette.inkSoft)
                }
                Spacer(minLength: 8)
                trailing(device, model: model)
            }
            if model.revokeErrorFor == device.id {
                revokeErrorRow(device, model: model)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("accountDeviceRow")
        .opacity(device.revoked ? 0.55 : 1)
    }

    /// "This device" - the marker on the phone running the app, so a user
    /// recognising their devices at a glance never has to guess.
    private var thisDeviceBadge: some View {
        Text("This device")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Theme.Palette.action)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Theme.Palette.action.opacity(0.12))
            .clipShape(Capsule())
    }

    /// The row's trailing control: Revoke on a live device, a checkmark and the
    /// honest "Signed out" label on a revoked one. Revoking is always available
    /// (including on this device - it signs this phone out of the account).
    @ViewBuilder
    private func trailing(_ device: AccountDevice, model: AccountDevicesModel) -> some View {
        if device.revoked {
            HStack(spacing: 4) {
                Image(systemName: "checkmark")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Theme.Palette.inkSoft)
                Text("Signed out")
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.inkSoft)
            }
        } else if model.inFlightRevoke == device.id {
            ProgressView()
                .controlSize(.small)
                .tint(Theme.Palette.inkSoft)
        } else {
            Button("Revoke") { pendingRevoke = device }
                .buttonStyle(.plain)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.Palette.action)
                .accessibilityIdentifier("accountRevokeButton")
        }
    }

    /// A failed revoke names its next step (hard rule 7): Try again on the same
    /// row, amber (attention, never red - nothing was lost).
    private func revokeErrorRow(_ device: AccountDevice, model: AccountDevicesModel) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(Theme.Palette.warn)
            Text(L10n.revokeFailedMessage)
                .font(.caption)
                .foregroundStyle(Theme.Palette.warn)
            Spacer(minLength: 8)
            Button("Try again") {
                Task { await model.revoke(device) }
            }
            .buttonStyle(.plain)
            .font(.caption.weight(.bold))
            .foregroundStyle(Theme.Palette.action)
            .accessibilityIdentifier("accountRevokeRetryButton")
        }
        .accessibilityIdentifier("accountRevokeError")
    }

    /// The status line: "Signed out" for a revoked device (its next pull is
    /// 410 - it no longer syncs, and its data stays on it), else the app-
    /// formatted relative day since the server last saw the device.
    private static func statusLine(_ device: AccountDevice) -> String {
        if device.revoked { return L10n.localize("Signed out") }
        let daysAgo = max(0, Int(Date().timeIntervalSince(device.lastSeenAt) / 86_400))
        return L10n.seenAgo(relativeDay: L10n.relativeDay(daysAgo))
    }

    private static func platformIcon(_ platform: String) -> String {
        let normalized = platform.lowercased()
        if normalized.contains("ipad") { return "ipad" }
        if normalized.contains("iphone") || normalized.contains("ios") { return "iphone" }
        if normalized.contains("watch") { return "applewatch" }
        if normalized.contains("mac") { return "macbook" }
        return "desktopcomputer"
    }

    // MARK: - Delete account

    /// The destructive row. Red belongs to exactly this confirmation (inside
    /// the system dialog, hard rule 5); the row itself is inkSoft, matching the
    /// Settings rows - the red is reserved for the confirmation.
    private func deleteSection(_ model: AccountDevicesModel) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            VStack(spacing: 0) {
                Button {
                    showsDeleteConfirm = true
                } label: {
                    HStack {
                        if model.isDeletingAccount {
                            ProgressView()
                                .controlSize(.small)
                                .tint(Theme.Palette.inkSoft)
                        }
                        Text("Delete account")
                            .font(.subheadline)
                            .foregroundStyle(Theme.Palette.ink)
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Theme.Palette.inkSoft)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 13)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(model.isDeletingAccount)
                .accessibilityIdentifier("accountDeleteButton")
            }
            .formCard()

            if let deleteError = model.deleteError {
                failedCard(deleteError, identifier: "accountDeleteError") {
                    Button("Try again") {
                        showsDeleteConfirm = true
                    }
                    .buttonStyle(.plain)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.Palette.action)
                    .accessibilityIdentifier("accountDeleteRetryButton")
                }
            }

            // The tombstone truth, stated plainly (site/delete-account.md): the
            // local log is never touched, so the export that still works stays
            // trusted.
            Text(L10n.deleteAccountFootnote)
                .font(.caption)
                .foregroundStyle(Theme.Palette.inkSoft)
                .multilineTextAlignment(.leading)
                .lineSpacing(2)
                .padding(.horizontal, 4)
                .padding(.top, 2)
                .accessibilityIdentifier("accountDeleteFootnote")
        }
    }

    // MARK: - Behavior

    private func performDelete() async {
        guard let model else { return }
        let deleted = await model.deleteAccount()
        if deleted {
            // The session is cleared; Settings reads it back through AppSync.
            await sync.refresh()
            dismiss()
        }
    }
}

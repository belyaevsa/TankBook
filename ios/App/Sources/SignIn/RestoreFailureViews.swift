import SwiftUI
import TankbookCore

/// The F7 empty-restore state (docs/JOURNEYS.md F7): the account is truly empty,
/// and the app says so BEFORE the user can log anything new. The recovery entry
/// point ("Expecting your data?") exists to prevent a merge conflict - the worst
/// sequence is the user re-adding a car manually and the backup later reappearing.
/// This is a data protection, not a nicety.
struct EmptyRestoreView: View {
    let flow: SignInFlow
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 20) {
                    titleBlock
                    recoveryCard
                }
                .padding(.horizontal, 28)
                .padding(.top, 8)
                .padding(.bottom, 20)
            }
            footer
        }
        .background(Theme.Palette.midnight)
    }

    private var header: some View {
        HStack {
            Spacer()
            Button {
                flow.signOutLocally()
                dismiss()
            } label: {
                Text("Not my account · sign out")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.Palette.inkSoft)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("restoringSignOutButton")
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    private var titleBlock: some View {
        VStack(spacing: 14) {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 44))
                .foregroundStyle(Theme.Palette.inkSoft)
            VStack(spacing: 6) {
                Text("No data found")
                    .font(.title2.bold())
                    .foregroundStyle(Theme.Palette.ink)
                Text("We didn't find any cars or entries under this account.")
                    .font(.footnote)
                    .foregroundStyle(Theme.Palette.inkSoft)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }
        }
    }

    private var recoveryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Expecting your data?")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.Palette.ink)
                .accessibilityIdentifier("emptyRestoreRecoveryPrompt")
            NavigationLink(value: Route.importWizard) {
                recoveryRow(icon: "square.and.arrow.down", title: "Import a file you exported yourself")
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("emptyRestoreImportRow")
            CardDivider()
            Button {
                flow.signOutLocally()
                dismiss()
            } label: {
                recoveryRow(icon: "person.crop.circle.badge.xmark", title: "Sign out and try another account")
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("emptyRestoreSignOutButton")
        }
        .padding(18)
        .formCard()
    }

    private func recoveryRow(icon: String, title: LocalizedStringKey) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(Theme.Palette.action)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.Palette.ink)
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.Palette.inkSoft)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private var footer: some View {
        VStack(spacing: 10) {
            Button {
                flow.acceptEmpty()
            } label: {
                Text("Start fresh")
                    .font(.body.weight(.bold))
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 17)
                    .background(Theme.Palette.taillight)
                    .clipShape(RoundedRectangle(cornerRadius: 15))
                    .shadow(color: Theme.Palette.taillight.opacity(0.3), radius: 18, y: 4)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("emptyRestoreStartFreshButton")

            Text("Start fresh opens an empty garage. If your data comes back later, it still arrives automatically.")
                .font(.caption2)
                .foregroundStyle(Theme.Palette.inkSoft.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 26)
        .padding(.bottom, 24)
    }
}

/// The F7 backend-down state (docs/JOURNEYS.md F7): the sync service is
/// unreachable, and the copy says exactly that with its next steps - never a
/// generic "something went wrong". The import path and the retry are both one
/// tap away.
struct RestoreUnreachableView: View {
    let flow: SignInFlow
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 20) {
                    titleBlock
                    actionsCard
                }
                .padding(.horizontal, 28)
                .padding(.top, 8)
                .padding(.bottom, 20)
            }
            footer
        }
        .background(Theme.Palette.midnight)
    }

    private var header: some View {
        HStack {
            Spacer()
            Button {
                flow.signOutLocally()
                dismiss()
            } label: {
                Text("Not my account · sign out")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.Palette.inkSoft)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("restoringSignOutButton")
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    private var titleBlock: some View {
        VStack(spacing: 14) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 44))
                .foregroundStyle(Theme.Palette.inkSoft)
            Text("Sync service unreachable – your data is safe on the server. You can import an export file, or it will all arrive when the service is back.")
                .font(.body)
                .foregroundStyle(Theme.Palette.ink)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .accessibilityIdentifier("restoreUnreachableMessage")
        }
    }

    private var actionsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            NavigationLink(value: Route.importWizard) {
                actionRow(icon: "square.and.arrow.down", title: "Import a file")
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("restoreUnreachableImportRow")
            CardDivider()
            Button {
                flow.retryRestore()
            } label: {
                actionRow(icon: "arrow.clockwise", title: "Try again")
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("restoreUnreachableRetryButton")
        }
        .padding(18)
        .formCard()
    }

    private func actionRow(icon: String, title: LocalizedStringKey) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(Theme.Palette.action)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.Palette.ink)
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.Palette.inkSoft)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private var footer: some View {
        VStack(spacing: 10) {
            Button {
                flow.signOutLocally()
                dismiss()
            } label: {
                Text("Sign out")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.Palette.inkSoft)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("restoreUnreachableSignOutButton")
        }
        .padding(.horizontal, 26)
        .padding(.bottom, 24)
    }
}

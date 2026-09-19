import SwiftUI
import TankbookCore

/// The restore pull dropped mid-way (docs/ERRORS.md -> Restoring, "Pull
/// interrupted"; docs/JOURNEYS.md F7): the honest notice, what landed so far,
/// and the two next steps - retry now, or open the partial garage, which the
/// regular sync keeps filling from the persisted cursor once the device is
/// back online. Never the server-down copy: this outage is the connection,
/// and sending the user to import a file for it would be the wrong next step.
struct RestoreInterruptedView: View {
    let flow: SignInFlow
    /// What landed before the drop; nil when the first page never arrived, in
    /// which case there is no partial garage to open.
    let snapshot: RestoreSnapshot?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 20) {
                    titleBlock
                    if let snapshot {
                        landedCard(snapshot)
                    }
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
            Image(systemName: "wifi.slash")
                .font(.system(size: 44))
                .foregroundStyle(Theme.Palette.inkSoft)
            Text("Connection dropped – restore continues when you're back online.")
                .font(.body)
                .foregroundStyle(Theme.Palette.ink)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .accessibilityIdentifier("restoreInterruptedMessage")
        }
    }

    /// What landed so far - the same two lines the Restoring screen's card
    /// leads with, so the partial garage is named in numbers, not a spinner.
    private func landedCard(_ snapshot: RestoreSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Restored so far")
                .font(.caption)
                .textCase(.uppercase)
                .tracking(1.2)
                .foregroundStyle(Theme.Palette.inkSoft)
            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.restoreCarsLine(carCount: snapshot.carCount,
                                          names: snapshot.carNames.joined(separator: ", ")))
                    .font(.subheadline)
                    .foregroundStyle(Theme.Palette.ink)
                Text(L10n.restoreEntriesLine(entryCount: snapshot.entryCount,
                                             startMonthYear: monthYear(snapshot.earliestEntry),
                                             endMonthYear: monthYear(snapshot.latestEntry)))
                    .font(.subheadline)
                    .foregroundStyle(Theme.Palette.ink)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .formCard()
        .accessibilityIdentifier("restoreInterruptedLandedCard")
    }

    private var actionsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if snapshot != nil {
                Button {
                    flow.onFinished()
                } label: {
                    actionRow(icon: "car.2", title: "Open my garage (partial, keeps filling)")
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("restoreInterruptedOpenGarageButton")
                CardDivider()
            }
            Button {
                flow.retryRestore()
            } label: {
                actionRow(icon: "arrow.clockwise", title: "Retry now")
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("restoreInterruptedRetryButton")
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
        Button {
            flow.signOutLocally()
            dismiss()
        } label: {
            Text("Sign out")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.Palette.inkSoft)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("restoreInterruptedSignOutButton")
        .padding(.horizontal, 26)
        .padding(.bottom, 24)
    }

    private func monthYear(_ date: Date?) -> String {
        guard let date else { return "–" }
        return RestoringView.monthYearFormatter.string(from: date)
    }
}

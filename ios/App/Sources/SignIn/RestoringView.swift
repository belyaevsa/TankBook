import SwiftUI
import TankbookCore

/// The Restoring screen (design/screens/Restoring.dc.html): the F7 verification
/// stats shown *before* finishing, with an honest photo-download progress line.
/// Pull-from-zero is the restore (docs/API.md -> "fetching the latest data IS
/// pulling from 0"), so this screen is progress over a pull; the progress lives
/// on the flow controller so being torn down and re-presented never resets or
/// inflates it (the resume itself is P4.7 - here it must not lie, hard rule 7).
struct RestoringView: View {
    let flow: SignInFlow
    let snapshot: RestoreSnapshot
    @Environment(\.dismiss) private var dismiss

    private static let monthYearFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = DateFormatter.dateFormat(fromTemplate: "MMM yyyy",
                                                        options: 0, locale: Locale.current)
        return formatter
    }()

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 20) {
                    identityBlock
                    foundCard
                    photosCard
                }
                .padding(.horizontal, 28)
                .padding(.top, 12)
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

    private var identityBlock: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Theme.Palette.headlight.opacity(0.1))
                    .frame(width: 62, height: 62)
                Circle()
                    .stroke(Theme.Palette.headlight, lineWidth: 1.5)
                    .frame(width: 62, height: 62)
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 26))
                    .foregroundStyle(Theme.Palette.headlight)
            }
            VStack(spacing: 4) {
                Text("Welcome back")
                    .font(.title2.bold())
                    .foregroundStyle(Theme.Palette.ink)
                Text(L10n.signedInSubtitle(email: snapshot.email, provider: snapshot.provider))
                    .font(.footnote)
                    .foregroundStyle(Theme.Palette.inkSoft)
            }
        }
    }

    private var foundCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Found in your account")
                .font(.caption)
                .textCase(.uppercase)
                .tracking(1.2)
                .foregroundStyle(Theme.Palette.inkSoft)
            VStack(alignment: .leading, spacing: 10) {
                foundRow(carsLine)
                foundRow(entriesLine)
                foundRow(lastOdometerLine)
                foundRow(Text("Reminders and tire sets included"))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .formCard()
        .accessibilityIdentifier("restoringFoundCard")
    }

    private var carsLine: Text {
        Text(L10n.restoreCarsLine(carCount: snapshot.carCount,
                                  names: snapshot.carNames.joined(separator: ", ")))
    }

    private var entriesLine: Text {
        Text(L10n.restoreEntriesLine(
            entryCount: snapshot.entryCount,
            startMonthYear: monthYear(snapshot.earliestEntry),
            endMonthYear: monthYear(snapshot.latestEntry)))
    }

    private var lastOdometerLine: Text {
        Text("Last odometer")
            + Text(verbatim: " ")
            + Text(OdometerFormat.grouped(snapshot.lastOdometerKm ?? 0))
                .font(.custom(AppFonts.dinAlternateBold, size: 13))
                .bold()
            + Text(verbatim: " \(L10n.distanceUnit(.km))")
            + Text(verbatim: sourceSuffix)
    }

    private var sourceSuffix: String {
        guard let device = snapshot.lastOdometerDeviceName,
              let daysAgo = snapshot.lastOdometerDaysAgo else {
            return ""
        }
        return " · \(L10n.lastOdometerSource(deviceName: L10n.localize(device), daysAgo: daysAgo))"
    }

    private func foundRow(_ text: Text) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.Palette.headlight)
            text
                .font(.footnote)
                .foregroundStyle(Theme.Palette.ink)
        }
    }

    private func monthYear(_ date: Date?) -> String {
        guard let date else { return "–" }
        return Self.monthYearFormatter.string(from: date)
    }

    private var photosCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Receipt photos")
                    .font(.footnote)
                    .foregroundStyle(Theme.Palette.inkSoft)
                Spacer()
                if flow.restoreProgress.isActive {
                    Text(L10n.downloading(percent: Int((flow.restoreProgress.fraction * 100).rounded())))
                        .font(.footnote.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.Palette.ink)
                }
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.Palette.hairline)
                    Capsule()
                        .fill(Theme.Palette.headlight)
                        .frame(width: geometry.size.width * flow.restoreProgress.fraction)
                }
            }
            .frame(height: 6)
            Text("Continues in the background – no need to wait.")
                .font(.caption2)
                .foregroundStyle(Theme.Palette.inkSoft.opacity(0.7))
        }
        .padding(18)
        .formCard()
        .accessibilityIdentifier("restoringPhotosCard")
    }

    private var footer: some View {
        VStack(spacing: 10) {
            Button {
                flow.onFinished()
            } label: {
                Text("Open my garage")
                    .font(.body.weight(.bold))
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 17)
                    .background(Theme.Palette.taillight)
                    .clipShape(RoundedRectangle(cornerRadius: 15))
                    .shadow(color: Theme.Palette.taillight.opacity(0.3), radius: 18, y: 4)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("restoringOpenGarageButton")

            Text("Everything is already usable – photos fill in as they arrive.")
                .font(.caption2)
                .foregroundStyle(Theme.Palette.inkSoft.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 26)
        .padding(.bottom, 24)
    }
}

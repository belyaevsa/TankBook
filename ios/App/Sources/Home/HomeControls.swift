import SwiftUI
import TankbookCore

// MARK: - The controls Home's two layouts share

/// The car switcher chip. ONE control (RV.251): the signed-in header row and
/// the guest Home both render this view, so a guest with two cars gets the same
/// switcher and the two layouts cannot drift into two different buttons.
/// Whether it appears is `HomeLayout.showsCarSwitcher(liveCarCount:)`'s
/// decision, never this view's - and that function takes no session input.
struct HomeCarSwitcherButton: View {
    let vehicleName: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                Text(vehicleName)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.Palette.ink)
                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(Theme.Palette.inkSoft)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(Theme.Palette.dash))
            .overlay(Capsule().stroke(Theme.Palette.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("carSwitcherButton")
    }
}

/// Home's typed doors: one chip per entry form - Fill-up, Service, Expense -
/// side by side and equal, each opening its form empty in one tap (hard rule
/// 15). The forms are visible, not behind a menu: a user with no receipts read
/// a single "Type it" button as "this app logs fuel only". Rendered by the
/// signed-in header and the guest capture card, never copied; the chips come
/// from `CaptureEntryForm.allCases`, so a fourth entry form appears on both
/// doors the moment it exists. The fill-up chip keeps the `typeItButton`
/// identity the entry tests drive.
struct HomeTypeItControl: View {
    let presentSheet: (SheetRoute) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(CaptureEntryForm.allCases, id: \.self) { form in
                Button {
                    presentSheet(form.sheetRoute)
                } label: {
                    Label(form.doorLabel, systemImage: form.doorSymbol)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.Palette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Capsule().fill(Theme.Palette.dash))
                        .overlay(Capsule().stroke(Theme.Palette.hairline, lineWidth: 1))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(form.doorAccessibilityLabel)
                .accessibilityIdentifier(form.doorIdentifier)
            }
        }
    }
}

/// The filled Add-car button. ONE control (PJ.101): the signed-in no-car layout
/// and the guest no-car card both render it, so the two no-car states cannot
/// drift into one with an Add-car door and one without.
struct HomeAddFirstCarButton: View {
    var body: some View {
        NavigationLink(value: Route.addVehicle) {
            Text("Add your first car")
                .font(.body.weight(.bold))
                .foregroundStyle(Theme.Palette.midnight)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(Theme.Palette.taillight)
                .clipShape(RoundedRectangle(cornerRadius: 15))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("homeAddFirstCarButton")
    }
}

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

/// Home's "Type it" control. ONE control (RV.61): the primary button opens the
/// fill-up form in one tap (the commonest entry must never get slower, hard rule
/// 15); the trailing chevron is a menu offering the other entry forms (Service,
/// Expense) - the same choice the capture screen's mode row presents. A plain
/// `Button` + `Menu` pair, not `Menu(primaryAction:)`, so the two affordances
/// have separate, deterministic accessibility identities. Rendered by the
/// signed-in header row and the guest capture card (PJ.100), never copied; the
/// menu items come from `CaptureEntryForm.doorMenuForms`, so a fourth entry form
/// appears on both doors the moment it exists.
struct HomeTypeItControl: View {
    let presentSheet: (SheetRoute) -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button {
                presentSheet(.confirmManual)
            } label: {
                Label("Type it", systemImage: "square.and.pencil")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.Palette.ink)
                    .padding(.leading, 12)
                    .padding(.trailing, 8)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("typeItButton")

            Menu {
                ForEach(CaptureEntryForm.doorMenuForms, id: \.self) { form in
                    Button {
                        presentSheet(form.sheetRoute)
                    } label: {
                        Text(form.doorMenuLabel)
                    }
                }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.Palette.inkSoft)
                    .padding(.leading, 2)
                    .padding(.trailing, 10)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("More entry types")
            .accessibilityIdentifier("typeItMenu")
        }
        .background(Capsule().fill(Theme.Palette.dash))
        .overlay(Capsule().stroke(Theme.Palette.hairline, lineWidth: 1))
        .modifier(TypeItScreenshotMenu(presentSheet: presentSheet))
    }
}

/// `simctl` cannot tap a SwiftUI `Menu`, so `-presentTypeItMenu` renders the
/// same `doorMenuForms` choices as a dialog for the screenshot pose. Debug-only
/// and derived from the same source as the menu, so the captured options cannot
/// drift from the ones a user sees.
private struct TypeItScreenshotMenu: ViewModifier {
    let presentSheet: (SheetRoute) -> Void

    @State private var isOpen = false

    func body(content: Content) -> some View {
        #if DEBUG
        content
            .task {
                if ProcessInfo.processInfo.arguments.contains("-presentTypeItMenu") {
                    isOpen = true
                }
            }
            .confirmationDialog("Type it", isPresented: $isOpen, titleVisibility: .visible) {
                ForEach(CaptureEntryForm.doorMenuForms, id: \.self) { form in
                    Button(form.doorMenuLabel) {
                        presentSheet(form.sheetRoute)
                    }
                }
            }
        #else
        content
        #endif
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

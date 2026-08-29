import SwiftUI
import TankbookCore
import UIKit

// MARK: - Empty entries card

/// The zero-entries state under a car: no fabricated numbers anywhere, just the
/// next step - the capture path (docs/ERRORS.md -> Home, "Car, zero entries").
struct HomeEmptyEntriesCard: View {
    let onTypeIt: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "fuelpump")
                .font(.system(size: 22))
                .foregroundStyle(Theme.Palette.taillight)
            Text("No entries yet")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.Palette.ink)
            Text("Scan or type your first fill-up – consumption appears after two full tanks.")
                .font(.caption)
                .foregroundStyle(Theme.Palette.inkSoft)
                .multilineTextAlignment(.center)
            HStack(spacing: 16) {
                Button("Type it", action: onTypeIt)
                    .buttonStyle(.plain)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.Palette.action)
                    .accessibilityIdentifier("homeEmptyEntriesButton")
                NavigationLink(value: Route.editEntry(nil)) {
                    Text("Edit entry")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.Palette.action)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("editEntryButton")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(Theme.Palette.dash)
        .clipShape(RoundedRectangle(cornerRadius: 15))
        .overlay(
            RoundedRectangle(cornerRadius: 15)
                .stroke(Theme.Palette.inkSoft.opacity(0.35),
                        style: StrokeStyle(lineWidth: 1.5, dash: [6]))
        )
    }
}

// MARK: - No car layout

/// The "No car yet" Home: the Add-car path, not an empty dashboard
/// (docs/ERRORS.md -> Confirm row is about the manual form; this is the Home
/// face of the same truth - logging needs a car). The shell affordances stay
/// reachable in a compact quick-actions card so navigation never dead-ends.
struct HomeNoCarLayout: View {
    let presentSheet: (SheetRoute) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Welcome to Tankbook")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Theme.Palette.ink)
                Text("Add a car and your consumption, spend and price history appear here.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.Palette.inkSoft)
            }
            .padding(.top, 8)

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

            quickActions
        }
    }

    private var quickActions: some View {
        VStack(spacing: 0) {
            quickAction("Select car", systemImage: "car") {
                presentSheet(.carSwitcher)
            }
            .accessibilityIdentifier("carSwitcherButton")
            CardDivider()
            quickAction("Type it", systemImage: "square.and.pencil") {
                presentSheet(.confirmManual)
            }
            .accessibilityIdentifier("typeItButton")
            CardDivider()
            NavigationLink(value: Route.editEntry(nil)) {
                Label("Edit entry", systemImage: "pencil")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.Palette.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Theme.Spacing.cardPadding)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("editEntryButton")
        }
        .formCard()
    }

    private func quickAction(_ title: String, systemImage: String,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.Palette.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .padding(.horizontal, Theme.Spacing.cardPadding)
                .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }
}

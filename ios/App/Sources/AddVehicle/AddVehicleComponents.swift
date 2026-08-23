import SwiftUI
import TankbookCore

// MARK: - Typography

/// The bundled DIN faces (docs/DESIGN.md: "numbers in DIN, UI text in SF Pro").
/// DIN is used for the odometer figure and any inline digits; units and labels
/// stay SF Pro and typographically subordinate.
enum AppFonts {
    static let dinAlternateBold = "DINAlternate-Bold"
    static let dinCondensedBold = "DINCondensed-Bold"
}

// MARK: - Card chrome

/// The standard surface: `dash` fill, 12pt radius, hairline border
/// (docs/DESIGN.md: "Cards use 12pt corner radius, 1px hairline border").
struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Theme.Palette.dash)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card)
                    .stroke(Theme.Palette.hairline, lineWidth: 1)
            )
    }
}

extension View {
    func formCard() -> some View {
        modifier(CardBackground())
    }
}

/// The uppercase section eyebrow ("POWERTRAIN", "FUEL", "IMPROVES ACCURACY").
struct SectionEyebrow: View {
    let text: LocalizedStringKey
    let trailing: () -> AnyView

    init(_ text: LocalizedStringKey, @ViewBuilder trailing: @escaping () -> some View) {
        self.text = text
        self.trailing = { AnyView(trailing()) }
    }

    init(_ text: LocalizedStringKey) {
        self.text = text
        self.trailing = { AnyView(EmptyView()) }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(text)
                .font(.caption)
                .textCase(.uppercase)
                .tracking(1.2)
                .foregroundStyle(Theme.Palette.inkSoft)
            trailing()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 2)
        .padding(.vertical, 7)
    }
}

/// A card row: label on the left, value on the right (artboard layout).
struct FieldRow<Value: View>: View {
    let label: LocalizedStringKey
    @ViewBuilder let value: () -> Value

    init(_ label: LocalizedStringKey, @ViewBuilder value: @escaping () -> Value) {
        self.label = label
        self.value = value
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(Theme.Palette.inkSoft)
                .fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: 8)
            value()
        }
        .padding(.horizontal, Theme.Spacing.cardPadding)
        .padding(.vertical, 12)
    }
}

/// A hairline divider between card rows.
struct CardDivider: View {
    var body: some View {
        Divider().overlay(Theme.Palette.hairline)
    }
}

/// Amber underline shown under a field in its warn state
/// (docs/ERRORS.md: "Warn amber underline"); cyan while focused (artboard).
extension View {
    func fieldUnderline(isFocused: Bool, warn: Bool) -> some View {
        overlay(alignment: .bottom) {
            if warn {
                Rectangle().fill(Theme.Palette.warn).frame(height: 2)
            } else if isFocused {
                Rectangle().fill(Theme.Palette.headlight).frame(height: 2)
            }
        }
    }
}

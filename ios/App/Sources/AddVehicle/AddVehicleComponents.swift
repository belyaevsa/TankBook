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
///
/// docs/DESIGN.md -> Accessibility floor: Increase Contrast is respected. The
/// border is `Theme.Palette.hairline` (ink at 0.08) by default; when the user
/// has Increase Contrast on it is raised to the `ContrastPolicy` value so card
/// edges stay legible. The opacity decision lives in core (testable), the
/// environment read lives here.
struct CardSurface<Content: View>: View {
    @Environment(\.colorSchemeContrast) private var contrast
    let content: Content

    var body: some View {
        content
            .background(Theme.Palette.dash)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card)
                    .stroke(Theme.Palette.ink.opacity(
                        ContrastPolicy.hairlineOpacity(increasedContrast: contrast == .increased)),
                        lineWidth: 1)
            )
    }
}

extension View {
    func formCard() -> some View {
        CardSurface(content: self)
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

/// A card row: label on the left, value on the right (artboard layout). The
/// row is for values that are NOT a keyboard field - a picker/menu, a chip
/// row, a static value - so it stays INERT: no tap gesture of its own, because
/// such a row either has its own tap targets or must not pretend to be a
/// button. A row whose value IS a text field is `FocusableFieldRow`, which
/// carries the focus action this type deliberately does not have.
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

/// A card row whose VALUE is a keyboard-editable field. The WHOLE row is the
/// tap target (RV.47): tapping the label - or the empty stretch between label
/// and value - focuses the field, the `<label for>` behaviour a web form gives
/// and a typist on a capture-first form expects. An empty, placeholder-less
/// text field collapses to a near-zero-width strip pinned to the row's right
/// edge - nothing on screen says "field here" until it is focused or warned -
/// so the row itself enforces the 44pt accessibility floor (docs/DESIGN.md)
/// and answers taps across its full extent.
///
/// The focusable/inert split is TYPE-LEVEL, not a flag (RV.47): this type
/// cannot be constructed without naming the focus state and target its field
/// binds to (`Focus` is the row's case in its screen's focus enum, exactly as
/// `.focused(_:equals:)` spells it), and `FieldRow` has no focus parameter and
/// no tap gesture - so a picker or read-only row can never be silently turned
/// into a fake button, and an editable row is never built without stating which
/// field the whole row focuses.
struct FocusableFieldRow<Value: View, Focus: Hashable>: View {
    let label: LocalizedStringKey
    @FocusState.Binding var focus: Focus?
    let target: Focus
    var rowIdentifier: String?
    @ViewBuilder let value: () -> Value

    init(_ label: LocalizedStringKey,
         _ focus: FocusState<Focus?>.Binding,
         equals target: Focus,
         rowIdentifier: String? = nil,
         @ViewBuilder value: @escaping () -> Value) {
        self.label = label
        self._focus = focus
        self.target = target
        self.rowIdentifier = rowIdentifier
        self.value = value
    }

    @ViewBuilder
    var body: some View {
        // Simultaneous, not exclusive: a tap that lands ON the field itself
        // must still reach the field (caret placement must keep working);
        // only the taps the field does not claim - the label and the gap -
        // exist to focus it.
        let rowElement = HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(Theme.Palette.inkSoft)
                .fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: 8)
            value()
        }
        .padding(.horizontal, Theme.Spacing.cardPadding)
        .padding(.vertical, 12)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded { focus = target })
        .accessibilityElement(children: .contain)
        if let rowIdentifier {
            rowElement.accessibilityIdentifier(rowIdentifier)
        } else {
            rowElement
        }
    }
}

/// A hairline divider between card rows.
struct CardDivider: View {
    var body: some View {
        Divider().overlay(Theme.Palette.hairline)
    }
}

/// Amber underline shown under a field in its warn state
/// (docs/ERRORS.md: "Warn amber underline"); `action` while focused
/// (P6.7: the focus indicator is interactive, never an accent).
extension View {
    func fieldUnderline(isFocused: Bool, warn: Bool) -> some View {
        overlay(alignment: .bottom) {
            if warn {
                Rectangle().fill(Theme.Palette.warn).frame(height: 2)
            } else if isFocused {
                Rectangle().fill(Theme.Palette.action).frame(height: 2)
            }
        }
    }
}

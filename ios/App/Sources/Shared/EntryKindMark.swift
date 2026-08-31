import SwiftUI
import TankbookCore

// MARK: - Kind meaning (colour is never the only channel)

extension LogStream.Kind {
    /// The kind of an entry, derived from its concrete type - one place, so
    /// Home, Recently deleted and every future surface can never disagree
    /// about what a `FillUp` looks like.
    init(_ entry: any Entry) {
        switch entry {
        case is FillUp: self = .fuel
        case is ChargeSession: self = .charge
        case is ServiceRecord: self = .service
        default: self = .expense
        }
    }

    /// taillight = fuel, headlight = electric (hard rule 5); service and
    /// expense are inert inkSoft - the accent is meaning, never chrome.
    var color: Color {
        switch self {
        case .fuel: return Theme.Palette.taillight
        case .charge: return Theme.Palette.headlight
        case .service, .expense: return Theme.Palette.inkSoft
        }
    }

    /// The glyph that carries the kind when colour cannot (docs/DESIGN.md ->
    /// Accessibility floor: "fuel vs electric entries also differ by glyph").
    /// A circle in `taillight` and a circle in `headlight` differ only by hue,
    /// which is invisible to a colour-blind reader and to VoiceOver; the glyph
    /// is the second channel.
    var glyph: String {
        switch self {
        case .fuel: return "fuelpump.fill"
        case .charge: return "bolt.fill"
        case .service: return "wrench.adjustable.fill"
        case .expense: return "tag.fill"
        }
    }

    /// The spoken kind, announced as the first word of an entry's VoiceOver
    /// label so a colour-blind or blind reader hears fuel vs electric without
    /// seeing the dot.
    var accessibilityName: String {
        switch self {
        case .fuel: return L10n.localize("Fuel")
        case .charge: return L10n.localize("Charge")
        case .service: return L10n.localize("Service")
        case .expense: return L10n.localize("Expense")
        }
    }
}

// MARK: - The marker view

/// The small kind marker on an entry row: a glyph, never colour-only. Shared by
/// Home's log stream and the Recently deleted rows so the two surfaces can
/// never disagree about what a kind looks like. The glyph is the visual channel
/// (fuel vs electric differ by icon, not just hue); its accessibility label is
/// the spoken channel, so a blind reader hears the kind a colour-blind reader
/// cannot see.
struct EntryKindMark: View {
    let kind: LogStream.Kind
    var dimmed = false

    var body: some View {
        Image(systemName: kind.glyph)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(kind.color)
            .frame(width: 16, height: 16)
            .opacity(dimmed ? 0.55 : 1)
            .accessibilityLabel(kind.accessibilityName)
    }
}

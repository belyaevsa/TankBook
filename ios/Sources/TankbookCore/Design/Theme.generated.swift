// GENERATED FILE – do not edit. Source: design/tokens.json
// Regenerate with: swift scripts/generate-theme.swift

import SwiftUI

/// The Tankbook design system (Night Drive palette).
/// All values derive from `design/tokens.json`; do not hand-edit.
public enum Theme {
    /// Semantic colours, resolved per system colour scheme.
    public enum Palette {
        public static let action = Color(themeHexLight: "#2F6690", themeHexDark: "#8FB4D9")
        public static let dash = Color(themeHexLight: "#FFFFFF", themeHexDark: "#1A1F27")
        public static let headlight = Color(themeHexLight: "#0A6A8C", themeHexDark: "#4FC3E8")
        public static let ink = Color(themeHexLight: "#1A2028", themeHexDark: "#EAEDF2")
        public static let inkSoft = Color(themeHexLight: "#55606E", themeHexDark: "#98A2B3")
        public static let midnight = Color(themeHexLight: "#F5F6F8", themeHexDark: "#101318")
        public static let ok = Color(themeHexLight: "#0E7A46", themeHexDark: "#4FD18C")
        public static let tabBar = Color(themeHexLight: "#EFF1F4", themeHexDark: "#0D1015")
        public static let tabBarBorder = Color(themeHexLight: "#E1E4EA", themeHexDark: "#1C222C")
        public static let taillight = Color(themeHexLight: "#CE3422", themeHexDark: "#F4503A")
        public static let warn = Color(themeHexLight: "#9A5F0A", themeHexDark: "#F0A030")
        /// Hairline border: `ink` at 0.08 opacity.
        public static let hairline = Theme.Palette.ink.opacity(0.08)
        static let hairlineOpacity: Double = 0.08

        /// Every palette colour keyed by token name.
        public static let all: [String: Color] = [
            "action": action,
            "dash": dash,
            "headlight": headlight,
            "ink": ink,
            "inkSoft": inkSoft,
            "midnight": midnight,
            "ok": ok,
            "tabBar": tabBar,
            "tabBarBorder": tabBarBorder,
            "taillight": taillight,
            "warn": warn,
        ]
    }

    public enum Spacing {
        public static let base: CGFloat = 4
        public static let screenMargin: CGFloat = 20
        public static let cardPadding: CGFloat = 16
    }

    public enum Radius {
        public static let card: CGFloat = 12
    }
}

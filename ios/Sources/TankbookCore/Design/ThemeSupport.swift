import SwiftUI
import CoreGraphics

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

extension Color {
    /// Creates a `Color` that resolves to the light or dark hex value per the
    /// current system colour scheme. Called from generated code only (P0.2).
    init(themeHexLight lightHex: String, themeHexDark darkHex: String) {
        #if canImport(UIKit)
        self.init(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? darkHex : lightHex
            guard let components = hexComponents(hex) else { return .clear }
            return UIColor(cgColor: CGColor(srgbRed: components.red,
                                            green: components.green,
                                            blue: components.blue,
                                            alpha: 1))
        })
        #elseif canImport(AppKit)
        self.init(nsColor: NSColor(name: nil) { appearance in
            let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let hex = dark ? darkHex : lightHex
            guard let components = hexComponents(hex) else { return .clear }
            return NSColor(cgColor: CGColor(srgbRed: components.red,
                                            green: components.green,
                                            blue: components.blue,
                                            alpha: 1)) ?? .clear
        })
        #endif
    }

    /// The concrete sRGB components (0-1) of this colour when resolved for the
    /// given appearance. Used by tests to keep generated tokens in sync with
    /// `design/tokens.json`.
    func resolvedSRGBComponents(isDark: Bool) -> (red: Double, green: Double, blue: Double) {
        #if canImport(UIKit)
        let uiColor = UIColor(self)
        let style: UIUserInterfaceStyle = isDark ? .dark : .light
        let resolved = uiColor.resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return (Double(red), Double(green), Double(blue))
        #elseif canImport(AppKit)
        let nsColor = NSColor(self)
        let appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)!
        var result: (red: Double, green: Double, blue: Double) = (0, 0, 0)
        appearance.performAsCurrentDrawingAppearance {
            guard let srgb = nsColor.usingColorSpace(.sRGB) else { return }
            result = (Double(srgb.redComponent), Double(srgb.greenComponent), Double(srgb.blueComponent))
        }
        return result
        #endif
    }
}

/// Parses "#RRGGBB" into normalized sRGB components.
func hexComponents(_ hex: String) -> (red: CGFloat, green: CGFloat, blue: CGFloat)? {
    var value = hex
    if value.hasPrefix("#") { value.removeFirst() }
    guard value.count == 6, let number = UInt64(value, radix: 16) else { return nil }
    return (CGFloat((number >> 16) & 0xFF) / 255,
            CGFloat((number >> 8) & 0xFF) / 255,
            CGFloat(number & 0xFF) / 255)
}

import Foundation

/// A simulated detection result (P2.1: presentation only - no Vision, no
/// parsing; P2.2 wires the real pipeline). The extracted lines mirror the
/// artboard's receipt (design/screens/Capture.dc.html).
struct CaptureDetection: Sendable, Equatable {
    var lines: [String]

    /// The artboard's extracted lines.
    static let sample = CaptureDetection(lines: [
        "SHELL 1234",
        "DIESEL B7",
        "42.30 L    1.679/L",
        "TOTAL     71.02 EUR"
    ])
}

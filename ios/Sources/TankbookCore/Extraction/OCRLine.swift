import CoreGraphics
import Foundation

/// One recognized text line with its position. The bounding box uses Vision's
/// normalized coordinate space (origin bottom-left), so a higher `midY` sits
/// higher on the page. The pure extraction core reads only this type - no
/// Vision import - so it stays testable from plain `[OCRLine]` on macOS.
public struct OCRLine: Sendable, Equatable {
    public let text: String
    public let confidence: Float
    public let boundingBox: CGRect

    public init(text: String, confidence: Float = 1.0, boundingBox: CGRect = .zero) {
        self.text = text
        self.confidence = confidence
        self.boundingBox = boundingBox
    }
}

extension OCRLine {
    /// Vertical centre of the line, used to pair a label with the value on its
    /// own baseline (the reading-order fix for the total-finder).
    var midY: CGFloat { boundingBox.midY }

    /// Horizontal centre, used to assign numbers to a labelled column.
    var midX: CGFloat { boundingBox.midX }
}

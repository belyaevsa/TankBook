import CoreGraphics
import Foundation

// MARK: - PJ.1 the capture assembler
//
// The pure decision core of the capture pipeline: OCR lines and an optional
// fiscal-QR payload in, one `FuelExtraction` + a `FiscalQRAnchor` + a crop rect
// per resolved field out. Lives in TankbookCore (never the app target) so its
// decision-making is L1-testable from `[OCRLine]` values with no Vision, no
// image and no view - the P3.7 lesson: a decision that lives in the app target
// is "verified by looking at one device", and a double-counted inset survived
// two phases that way.
//
// It assembles, never invents: `FuelExtractor` owns the parsing, `FiscalQRParser`
// owns the QR, and this type only composes them and derives the crop rect each
// resolved field points at. Crop RECTS are values (core); the `UIImage` crop
// itself is app-side.

/// The output of one capture: the extraction (default input, hard rule 13), the
/// fiscal-QR anchor when a QR was present, and the OCR crop rect for each field
/// the extraction actually resolved (Vision-normalised coordinates, origin
/// bottom-left, exactly as `OCRLine.boundingBox`).
public struct CaptureAssembly: Sendable, Equatable {
    public var extraction: FuelExtraction
    public var qrAnchor: FiscalQRAnchor?
    public var cropRects: [ManualFillUpMath.Field: CGRect]

    public init(extraction: FuelExtraction,
                qrAnchor: FiscalQRAnchor?,
                cropRects: [ManualFillUpMath.Field: CGRect]) {
        self.extraction = extraction
        self.qrAnchor = qrAnchor
        self.cropRects = cropRects
    }
}

/// The single entry point the capture pipeline calls. Nothing in the app target
/// reasons about OCR lines, QR payloads or crop rects - it only hands an image
/// to Vision and wraps the result.
public enum ExtractionAssembler {

    /// Runs the full pipeline: OCR -> extraction, QR -> anchor, and the crop
    /// rect per field the extraction resolved. A nil `qrPayload` (no QR found,
    /// or the detector failed) is a plain absence - never an error; the same is
    /// true of an all-nil extraction, which the confirm sheet renders as the
    /// ordinary empty manual form (hard rule 15).
    public static func assemble(
        lines: [OCRLine],
        qrPayload: String?,
        source: ExtractionSource,
        timeZone: TimeZone = .current,
        bandProvider: (any FuelPriceBandProvider)? = nil
    ) -> CaptureAssembly {
        let extraction = FuelExtractor(bandProvider: bandProvider)
            .extract(lines: lines, source: source)
        let qrAnchor = qrPayload.flatMap { raw in
            (try? FiscalQRParser.parse(raw, timeZone: timeZone))?.anchor
        }
        return CaptureAssembly(extraction: extraction,
                               qrAnchor: qrAnchor,
                               cropRects: cropRects(for: extraction, lines: lines))
    }

    // MARK: - Crop rects
    //
    // A crop rect points at the OCR line a resolved field came from. Volume and
    // unit price come from the same operand line; the total comes from the total
    // label. The rects are the OCR line's own bounding box (Vision normalised
    // space), so the app can attach the source image and crop a real `UIImage`
    // later (PJ.2). A field the extraction did NOT resolve gets no crop - the
    // confirm sheet's tap-to-verify degrades to absent, never a dead affordance.

    static func cropRects(for extraction: FuelExtraction,
                          lines: [OCRLine]) -> [ManualFillUpMath.Field: CGRect] {
        guard !lines.isEmpty else { return [:] }
        var rects: [ManualFillUpMath.Field: CGRect] = [:]

        let needsOperandCrop = extraction.liters != nil || extraction.unitPrice != nil
        if needsOperandCrop, let box = operandCropRect(lines) {
            if extraction.liters != nil { rects[.volume] = box }
            if extraction.unitPrice != nil { rects[.unitPrice] = box }
        }
        if extraction.total != nil, let box = totalCropRect(lines) {
            rects[.total] = box
        }
        return rects
    }

    /// The operand line the volume/price came from: the fuel line (the pair
    /// carrying a volume marker) first, else the first operand pair - the same
    /// ladder `FuelExtractor.resolveVolumeAndPrice` walks, so the crop points at
    /// the line that produced the value.
    private static func operandCropRect(_ lines: [OCRLine]) -> CGRect? {
        let index = OperandPair.fuelLine(in: lines)?.index
            ?? OperandPair.first(in: lines)?.1
        guard let index, lines.indices.contains(index) else { return nil }
        return lines[index].boundingBox
    }

    /// The total label line (a primary `ИТОГ`/`TOTAL` label preferred) - the
    /// region the receipt's own total came from.
    private static func totalCropRect(_ lines: [OCRLine]) -> CGRect? {
        var primary: CGRect?
        var any: CGRect?
        for line in lines {
            guard let kind = TotalLabel.classify(line.text) else { continue }
            if case .primary = kind, primary == nil { primary = line.boundingBox }
            if any == nil { any = line.boundingBox }
        }
        return primary ?? any
    }
}

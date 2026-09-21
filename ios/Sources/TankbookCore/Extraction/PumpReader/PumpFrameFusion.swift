import CoreGraphics
import Foundation

// Per-cell fusion over the frames of a Live record. The still fixes the cell
// count and rects (the slicer runs on the still alone); a frame whose slicer
// finds a different number of digit cells is skipped whole, the same rule
// `realglyphs.py` applies. Surviving cells are classified per frame and their
// eight probabilities fused element-wise by median, so glare and reflections -
// which move between frames – average out while the digits do not. The still
// is the fallback when no frame agrees.

/// One frame of a tracked record: the frame's pixels and the still's hand
/// quads carried into it, one per field.
struct PumpTrackedFrame {
    let image: PumpRGBImage
    let windows: [PumpReader.Window]
}

/// One window's still-side state, fixed before the frames are read: the strip
/// it was sliced into, its digit cells, and whether its row carries a mark.
private struct PendingFusionWindow {
    let window: PumpReader.Window
    let allCells: [GlyphCell]
    let cells: [GlyphCell]
    let slicerMarked: Bool
}

/// The still-side state plus every frame's per-cell contributions, gathered
/// before the median is taken.
private struct FusionAccumulator {
    var windows: [PendingFusionWindow] = []
    /// window -> cell -> the eight-probability vector from the still and each
    /// agreeing frame.
    var vectors: [[[[Double]]]] = []
    /// window -> cell -> the warped cell crop from the still and each agreeing
    /// frame, for the pixel-median mode.
    var crops: [[[PumpRGBImage]]] = []
}

extension PumpReader {

    /// How the frames are combined, cell by cell.
    enum FusionMode: Sendable {
        /// Element-wise median of the eight probabilities over the still and
        /// the agreeing frames, then one reading per cell.
        case probabilities
        /// Element-wise median of the warped cell pixels over the still and
        /// the agreeing frames, classified once.
        case pixels
    }

    /// The per-window fused read. `frames` is consumed once and may be a lazy
    /// sequence: a record captured beside a 4K movie holds hundreds of frames
    /// whose decoded buffers do not fit in memory together. `stride` keeps
    /// every n-th frame, since the app cannot afford a whole record's frames
    /// inside its capture budget.
    func readFused<S: Sequence>(still: PumpRGBImage, windows: [Window], frames: S,
                                stride: Int = 1,
                                mode: FusionMode = .probabilities) throws -> [WindowRead]
        where S.Element == PumpTrackedFrame {
        var accumulator = try prepareFusion(still: still, windows: windows, mode: mode)
        try addFrames(frames, step: max(1, stride), to: &accumulator, mode: mode)
        return try fuse(accumulator, mode: mode)
    }

    /// `readFused` and then the law, mirroring `resolve` for the still path.
    func resolveFused<S: Sequence>(still: PumpRGBImage, windows: [Window], frames: S,
                                   stride: Int = 1, mode: FusionMode = .probabilities,
                                   currency: CurrencyCode?,
                                   priceBand: FuelPriceBand?) throws -> PumpDisplayReading
        where S.Element == PumpTrackedFrame {
        let reads = try readFused(still: still, windows: windows, frames: frames,
                                  stride: stride, mode: mode)
        return PumpReadingLaw.resolve(
            windows: reads.map { PumpLocatedWindow(field: $0.field, cells: $0.cells) },
            currency: currency, priceBand: priceBand)
    }

    /// Slices the still and classifies each window's own cells, the baseline
    /// every frame's contribution is added to.
    private func prepareFusion(still: PumpRGBImage, windows: [Window],
                               mode: FusionMode) throws -> FusionAccumulator {
        var accumulator = FusionAccumulator()
        for window in windows {
            guard let strip = PumpQuadWarp.warpToStrip(rgb: still, quad: window.quad,
                                                       stripHeight: Self.stripHeight) else { continue }
            let stripRGB = PumpQuadWarp.rgbImage(from: strip)
            let allCells = PumpGlyphSlicer.slice(stripRGB.grayscale())
            let cells = allCells.filter { !$0.isBlank }
            guard !cells.isEmpty else { continue }
            guard PumpRowAssignment.plausibleCount(cells.count, for: window.field)
                    || window.field == .board else { continue }
            var windowVectors: [[[Double]]] = []
            var windowCrops: [[PumpRGBImage]] = []
            for cell in cells {
                if mode == .probabilities {
                    windowVectors.append([try Self.averaged(
                        model: model, crops: Self.cropCell(stripRGB, rect: cell.rect))])
                } else if let crop = Self.resample(stripRGB, rect: cell.rect,
                                                   width: PumpSegmentsModel.inputWidth,
                                                   height: PumpSegmentsModel.inputHeight) {
                    windowCrops.append([crop])
                }
            }
            accumulator.windows.append(PendingFusionWindow(
                window: window, allCells: allCells, cells: cells,
                slicerMarked: cells.contains { $0.hasDecimalPoint }))
            accumulator.vectors.append(windowVectors)
            accumulator.crops.append(windowCrops)
        }
        return accumulator
    }

    /// One pass over the frames: each is decoded once for every window on it,
    /// and only a frame whose slicer count equals the still's contributes.
    private func addFrames<S: Sequence>(_ frames: S, step: Int, to accumulator: inout FusionAccumulator,
                                        mode: FusionMode) throws where S.Element == PumpTrackedFrame {
        var frameIndex = 0
        for frame in frames {
            let take = frameIndex % step == 0
            frameIndex += 1
            guard take else { continue }
            for windowIndex in accumulator.windows.indices {
                let entry = accumulator.windows[windowIndex]
                guard let frameWindow = frame.windows.first(where: { $0.field == entry.window.field }),
                      let frameStrip = PumpQuadWarp.warpToStrip(rgb: frame.image, quad: frameWindow.quad,
                                                                stripHeight: Self.stripHeight) else { continue }
                let frameRGB = PumpQuadWarp.rgbImage(from: frameStrip)
                let frameCells = PumpGlyphSlicer.slice(frameRGB.grayscale()).filter { !$0.isBlank }
                guard frameCells.count == entry.cells.count else { continue }
                for index in entry.cells.indices {
                    if mode == .probabilities {
                        accumulator.vectors[windowIndex][index].append(try Self.averaged(
                            model: model, crops: Self.cropCell(frameRGB, rect: frameCells[index].rect)))
                    } else if let crop = Self.resample(frameRGB, rect: frameCells[index].rect,
                                                       width: PumpSegmentsModel.inputWidth,
                                                       height: PumpSegmentsModel.inputHeight) {
                        accumulator.crops[windowIndex][index].append(crop)
                    }
                }
            }
        }
    }

    /// The fused reading per window, then the mark and single-mark rules the
    /// still path applies.
    private func fuse(_ accumulator: FusionAccumulator, mode: FusionMode) throws -> [WindowRead] {
        var out: [WindowRead] = []
        for windowIndex in accumulator.windows.indices {
            let entry = accumulator.windows[windowIndex]
            var readings: [PumpCellReading] = []
            for (index, cell) in entry.cells.enumerated() {
                var probabilities: [Double]
                switch mode {
                case .probabilities:
                    probabilities = Self.elementwiseMedian(accumulator.vectors[windowIndex][index])
                case .pixels:
                    guard let image = Self.elementwiseMedianImage(accumulator.crops[windowIndex][index])
                    else { continue }
                    probabilities = try model.probabilities(cell: image)
                }
                if probabilities.count > 7 {
                    probabilities[7] = Self.markProbability(classifier: probabilities[7],
                                                            cellMarked: cell.hasDecimalPoint,
                                                            rowMarked: entry.slicerMarked)
                }
                readings.append(PumpCellReading(probabilities: probabilities))
            }
            out.append(WindowRead(field: entry.window.field, cells: Self.singleDecimalMark(readings),
                                  glyphCount: entry.allCells.count))
        }
        return out
    }

    /// The element-wise median of equal-length probability vectors. An even
    /// count averages the two middle values.
    static func elementwiseMedian(_ vectors: [[Double]]) -> [Double] {
        guard let first = vectors.first else { return [] }
        var out = [Double](repeating: 0, count: first.count)
        for index in first.indices {
            let values = vectors.compactMap { index < $0.count ? $0[index] : nil }.sorted()
            guard !values.isEmpty else { continue }
            out[index] = values.count % 2 == 1
                ? values[values.count / 2]
                : (values[values.count / 2 - 1] + values[values.count / 2]) / 2
        }
        return out
    }

    /// The element-wise median of equal-sized images, per channel per pixel.
    static func elementwiseMedianImage(_ images: [PumpRGBImage]) -> PumpRGBImage? {
        guard let first = images.first else { return nil }
        var out = [UInt8](repeating: 0, count: first.pixels.count)
        for index in out.indices {
            let values = images.compactMap { index < $0.pixels.count ? $0.pixels[index] : nil }.sorted()
            guard !values.isEmpty else { continue }
            out[index] = values.count % 2 == 1
                ? values[values.count / 2]
                : UInt8((Int(values[values.count / 2 - 1]) + Int(values[values.count / 2])) / 2)
        }
        return PumpRGBImage(width: first.width, height: first.height, pixels: out)
    }
}

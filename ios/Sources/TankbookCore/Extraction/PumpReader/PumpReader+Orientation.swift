import CoreGraphics
import Foundation

/// The orientation search: which quarter turn shows the display upright, for a
/// photo whose own orientation the reader cannot trust.
extension PumpReader {
    /// The orientations the live search tries, in tie-break order: 0 first, so
    /// an upright photo keeps its orientation. 180 is not searched - a display
    /// photographed upside down is not a case the corpus has, and a fourth pass
    /// would buy nothing on it.
    static let searchedRotations = [0, 90, 270]

    /// The confidence a row needs before the search counts it: a wrong
    /// orientation still yields horizontal fragments that pass
    /// `PumpRowGeometry`'s shape rules, and they come back unsure. The same 0.5
    /// the fast path calls "sure of a row" (`PumpDisplayCapture.fastConfidenceHigh`).
    static let searchMinimumConfidence: Double = 0.5

    /// One orientation's geometry score. `keptRows` is how many of the
    /// detector's confident rows pass `PumpRowGeometry`; `inkBandArea` (pixels)
    /// breaks a tie, the taller and wider a band the more ink it carries.
    struct OrientationScore: Equatable {
        let rotationCW: Int
        let keptRows: Int
        let inkBandArea: CGFloat
        /// The classifier's mean top-digit margin over the kept rows' cells,
        /// measured only for the geometry's pick and the rotation opposite it:
        /// an upside-down display passes the same geometry as an upright one,
        /// and its glyphs read with low margins.
        var readMargin: Double?
    }

    /// The rotation whose detected rows best pass `PumpRowGeometry`. Per
    /// orientation only the locator and the slicer run - never the law - so the
    /// full pipeline still runs once, at the winner; the classifier runs only to
    /// choose between the geometry's pick and its 180-degree opposite
    /// (`readMargin`).
    /// `seed` - the capture's own orientation where the app knows it - is the
    /// first candidate, so it wins a tie; without one the order is
    /// `searchedRotations` and 0 wins ties.
    func bestOrientation(for image: PumpRGBImage, seed: Int? = nil, trace: PumpTrace? = nil) -> Int {
        let rotations = Self.rotationCandidates(seed: seed)
        var scores = rotations.map { rotation in
            orientationScore(PumpPanelLocator.rotatedRGB(image, rotationCW: rotation), rotationCW: rotation)
        }
        var best = Self.bestRotation(scores)
        // The geometry cannot tell a display from itself turned 180 degrees;
        // when the opposite rotation also keeps rows, the classifier decides.
        if let i = scores.firstIndex(where: { $0.rotationCW == best }),
           let j = scores.firstIndex(where: { $0.rotationCW == (best + 180) % 360 }),
           scores[i].keptRows > 0, scores[j].keptRows > 0 {
            for k in [i, j] {
                scores[k].readMargin = readMargin(PumpPanelLocator.rotatedRGB(image, rotationCW: scores[k].rotationCW))
            }
            if let a = scores[j].readMargin, let b = scores[i].readMargin, a > b { best = scores[j].rotationCW }
        }
        trace?.orientationScores = scores
        return best
    }

    /// The rotations to score: the seed first (normalised), then the standard
    /// three without it.
    static func rotationCandidates(seed: Int?) -> [Int] {
        guard let seed else { return searchedRotations }
        let normalized = ((seed % 360) + 360) % 360
        return [normalized] + searchedRotations.filter { $0 != normalized }
    }

    /// Picks the best-scoring rotation; ties go to the earlier entry, so the
    /// seed (or 0) wins. Pure, so the tie rule is testable without an image.
    static func bestRotation(_ scores: [OrientationScore]) -> Int {
        var best: OrientationScore?
        for score in scores {
            guard let current = best else { best = score; continue }
            if score.keptRows > current.keptRows
                || (score.keptRows == current.keptRows && score.inkBandArea > current.inkBandArea) {
                best = score
            }
        }
        return best?.rotationCW ?? 0
    }

    /// The geometry score of an already-oriented image: each confident detected
    /// row is sliced and judged by `PumpRowGeometry`, never by the classifier.
    private func orientationScore(_ upright: PumpRGBImage, rotationCW: Int) -> OrientationScore {
        var kept = 0
        var ink: CGFloat = 0
        for row in detectedRows(for: upright) where row.confidence >= Self.searchMinimumConfidence {
            let pixels = row.quad.map { CGPoint(x: $0.x * CGFloat(upright.width), y: $0.y * CGFloat(upright.height)) }
            guard let sliced = Self.sliceDetectedOrOriginal(pixels, detected: true, in: upright) else { continue }
            let geometry = PumpRowGeometry.verdict(cells: sliced.fullCells, stripWidth: sliced.strip.width,
                                                   stripHeight: sliced.strip.height)
            guard geometry.kept else { continue }
            kept += 1
            let band = sliced.fullCells.first(where: { !$0.isBlank })?.rect.height ?? 0
            ink += band * CGFloat(sliced.strip.width)
        }
        return OrientationScore(rotationCW: rotationCW, keptRows: kept, inkBandArea: ink)
    }

    /// The classifier's mean top-digit margin over the cells of the rows an
    /// orientation keeps - one centre crop per cell, one batched prediction.
    private func readMargin(_ upright: PumpRGBImage) -> Double {
        var margins: [Double] = []
        for row in detectedRows(for: upright) where row.confidence >= Self.searchMinimumConfidence {
            let pixels = row.quad.map { CGPoint(x: $0.x * CGFloat(upright.width), y: $0.y * CGFloat(upright.height)) }
            guard let sliced = Self.sliceDetectedOrOriginal(pixels, detected: true, in: upright),
                  PumpRowGeometry.verdict(cells: sliced.fullCells, stripWidth: sliced.strip.width,
                                          stripHeight: sliced.strip.height).kept,
                  !sliced.cells.isEmpty, sliced.cells.count <= PumpReadingLaw.maxCells else { continue }
            let crops = sliced.cells.compactMap {
                Self.resample(sliced.rgb, rect: $0.rect, width: PumpSegmentsModel.inputWidth,
                              height: PumpSegmentsModel.inputHeight)
            }
            guard let probabilities = try? model.probabilities(cells: crops) else { continue }
            margins += probabilities.map { PumpCellReading(probabilities: $0).margin }
        }
        return margins.isEmpty ? 0 : margins.reduce(0, +) / Double(margins.count)
    }

}

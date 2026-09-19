import CoreGraphics
import Foundation
import ImageIO
import Vision

/// Region proposals for number windows from Vision's text-rectangle detector:
/// its character boxes, never its strings. Seven-segment digits detect as
/// text boxes reliably even where recognition misreads them, and a display
/// window is a row of such boxes of one height on one baseline.
///
/// Output quads are normalised [0, 1] over the image given, TL TR BR BL, the
/// same frame `PumpPanelLocator.Candidate` uses.
enum PumpVisionProposer {
    struct Row: Sendable, Equatable {
        let quad: [CGPoint]
        let boxCount: Int
        let height: CGFloat
    }

    /// Boxes on one row: vertical centres within this fraction of the height,
    /// heights within `heightTolerance`, horizontal gaps below `gapFactor` heights.
    static let baselineTolerance: CGFloat = 0.5
    static let heightTolerance: CGFloat = 0.6
    static let gapFactor: CGFloat = 2.5
    static let minimumBoxes = 2
    /// The pads were swept against the annotated quads (corpus median IoU
    /// 0.49 at 1.5 heights of left pad, 0.61 at 0.1): Vision's line box
    /// already covers the dim leading zeros, so only a sliver is added.
    static let horizontalPad: CGFloat = 0.1
    static let horizontalPadRight: CGFloat = 0.1
    static let verticalPad: CGFloat = 0.0

    static func rows(in image: CGImage) -> [Row] {
        // Two detectors, both for their boxes only: the text recognizer's
        // line boxes (it reads seven-segment digits as a line, however badly)
        // and the rectangle detector's character boxes for fragments.
        let recognize = VNRecognizeTextRequest()
        recognize.recognitionLevel = .accurate
        recognize.usesLanguageCorrection = false
        let rectangles = VNDetectTextRectanglesRequest()
        rectangles.reportCharacterBoxes = true
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        guard (try? handler.perform([recognize, rectangles])) != nil else { return [] }
        var lines: [Row] = []
        for observation in recognize.results ?? [] {
            let box = flipped(observation.boundingBox)
            let count = max(2, observation.topCandidates(1).first?.string.count ?? 2)
            lines.append(Row(quad: corners(box), boxCount: count, height: box.height))
        }
        var boxes: [CGRect] = []
        for observation in rectangles.results ?? [] {
            if let characters = observation.characterBoxes, !characters.isEmpty {
                boxes.append(contentsOf: characters.map(\.boundingBox))
            } else {
                boxes.append(observation.boundingBox)
            }
        }
        return merged(lines + group(boxes.map(flipped))).map { padded($0) }
    }

    /// How many text lines Vision recognises in the frame - the receipt
    /// discriminator: a display carries a handful of labels, a receipt dozens
    /// of lines. Boxes only; the strings are never read.
    static func textLineCount(in image: CGImage) -> Int {
        let recognize = VNRecognizeTextRequest()
        recognize.recognitionLevel = .fast
        recognize.usesLanguageCorrection = false
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        guard (try? handler.perform([recognize])) != nil else { return 0 }
        return recognize.results?.count ?? 0
    }

    static func corners(_ box: CGRect) -> [CGPoint] {
        [CGPoint(x: box.minX, y: box.minY), CGPoint(x: box.maxX, y: box.minY),
         CGPoint(x: box.maxX, y: box.maxY), CGPoint(x: box.minX, y: box.maxY)]
    }

    static func padded(_ row: Row) -> Row {
        let box = bounds(row.quad)
        let height = box.height
        let minX = max(0, box.minX - horizontalPad * height)
        let maxX = min(1, box.maxX + horizontalPadRight * height)
        let minY = max(0, box.minY - verticalPad * height)
        let maxY = min(1, box.maxY + verticalPad * height)
        return Row(quad: corners(CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)),
                   boxCount: row.boxCount, height: height)
    }

    /// Vision's boxes have a bottom-left origin; the reader's frame is top-left.
    static func flipped(_ box: CGRect) -> CGRect {
        CGRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height)
    }

    /// Greedy left-to-right row building over boxes sorted by x.
    static func group(_ boxes: [CGRect]) -> [Row] {
        let sorted = boxes.filter { $0.height > 0.004 && $0.width > 0.002 }.sorted { $0.minX < $1.minX }
        var used = [Bool](repeating: false, count: sorted.count)
        var rows: [Row] = []
        for i in sorted.indices where !used[i] {
            var members = [sorted[i]]
            used[i] = true
            var changed = true
            while changed {
                changed = false
                for j in sorted.indices where !used[j] {
                    let box = sorted[j]
                    let height = members.map(\.height).reduce(0, +) / CGFloat(members.count)
                    let midY = members.map(\.midY).reduce(0, +) / CGFloat(members.count)
                    let right = members.map(\.maxX).max()!
                    let left = members.map(\.minX).min()!
                    let sameHeight = abs(box.height - height) <= heightTolerance * height
                    let sameLine = abs(box.midY - midY) <= baselineTolerance * height
                    let adjacent = (box.minX >= right - height * 0.3 && box.minX - right <= gapFactor * height)
                        || (box.maxX <= left + height * 0.3 && left - box.maxX <= gapFactor * height)
                    if sameHeight && sameLine && adjacent {
                        members.append(box)
                        used[j] = true
                        changed = true
                    }
                }
            }
            guard members.count >= minimumBoxes else { continue }
            let height = members.map(\.height).reduce(0, +) / CGFloat(members.count)
            let union = members.dropFirst().reduce(members[0]) { $0.union($1) }
            rows.append(Row(quad: corners(union), boxCount: members.count, height: height))
        }
        return rows
    }

    /// Rows whose boxes overlap vertically and touch or overlap horizontally
    /// are one window Vision fragmented.
    static func merged(_ rows: [Row]) -> [Row] {
        var out: [Row] = []
        var pending = rows.sorted { $0.quad[0].x < $1.quad[0].x }
        while let first = pending.first {
            pending.removeFirst()
            var current = first
            var changed = true
            while changed {
                changed = false
                for (i, other) in pending.enumerated() {
                    let a = bounds(current.quad), b = bounds(other.quad)
                    let vertical = min(a.maxY, b.maxY) - max(a.minY, b.minY)
                    let horizontalGap = max(a.minX, b.minX) - min(a.maxX, b.maxX)
                    let sameHeight = abs(a.height - b.height) <= 0.4 * max(a.height, b.height)
                    if sameHeight, vertical > 0.7 * min(a.height, b.height), horizontalGap < 0.4 * current.height {
                        let u = a.union(b)
                        current = Row(
                            quad: [CGPoint(x: u.minX, y: u.minY), CGPoint(x: u.maxX, y: u.minY),
                                   CGPoint(x: u.maxX, y: u.maxY), CGPoint(x: u.minX, y: u.maxY)],
                            boxCount: current.boxCount + other.boxCount,
                            height: max(current.height, other.height))
                        pending.remove(at: i)
                        changed = true
                        break
                    }
                }
            }
            out.append(current)
        }
        return out
    }

    static func bounds(_ quad: [CGPoint]) -> CGRect {
        let xs = quad.map(\.x), ys = quad.map(\.y)
        return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
    }
}

import CoreGraphics
import Foundation
import Testing
@testable import TankbookCore

/// The row-angle estimator against the owner's hand quads: each heldout
/// transaction window's upright bound goes in, and the angle out is compared
/// with the angle the hand drew (its top edge, in pixels). This is PU.69's
/// agreement gate (agents/research/PU.69.md F1). The 72-trial sweep it replaced,
/// run through this same test in Release, read median 0.73 deg, p90 1.98 deg
/// (docs/EXTRACTION.md -> the PU.69 paragraph).
@Suite("Pump row deskew on the corpus")
struct PumpRowDeskewCorpusTests {
    @Test("the row angle agrees with the hand-drawn angle", .pumpFixturesPresent,
          .enabled(if: ProcessInfo.processInfo.environment["PUMP_DESKEW"] == "1", "PUMP_DESKEW=1"))
    func angleAgreesWithHandQuads() throws {
        let data = try Data(contentsOf: PumpReaderTestSupport.windowsURL)
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        var errors: [Double] = []
        var large: [Double] = []
        var seconds = 0.0
        for (name, value) in root.sorted(by: { $0.key < $1.key }) {
            guard name != "_about", PumpReaderTestSupport.isHeldout(name), let ann = value as? [String: Any],
                  ((ann["rotationCW"] as? NSNumber)?.intValue ?? 0) == 0,
                  let image = PumpReaderTestSupport.loadRGB(
                      url: PumpReaderTestSupport.pumpFixturesRoot.appendingPathComponent(name)) else { continue }
            for raw in ann["windows"] as? [[String: Any]] ?? [] {
                guard let field = raw["field"] as? String, ["total", "liters", "unitPrice"].contains(field),
                      let quad = raw["quad"] as? [[Double]], quad.count == 4 else { continue }
                let hand = PumpReaderTestSupport.quadPixels(quad, width: image.width, height: image.height)
                let drawn = atan2(Double(hand[1].y - hand[0].y), Double(hand[1].x - hand[0].x)) * 180 / .pi
                let xs = hand.map(\.x), ys = hand.map(\.y)
                let upright = [CGPoint(x: xs.min()!, y: ys.min()!), CGPoint(x: xs.max()!, y: ys.min()!),
                               CGPoint(x: xs.max()!, y: ys.max()!), CGPoint(x: xs.min()!, y: ys.max()!)]
                let started = Date()
                let found = PumpRowDeskew.deskew(upright, in: image)
                seconds += Date().timeIntervalSince(started)
                let error = abs(found.degrees - drawn)
                errors.append(error)
                if abs(drawn) > 6 { large.append(error) }
            }
        }
        let sorted = errors.sorted()
        let within = errors.filter { $0 <= 1 }.count
        let bound = PumpPrecisionBounds.wilson(within, errors.count, z: PumpPrecisionBounds.z95TwoSided)
        print(String(format: "PU.69 within 1 deg: %d of %d = %.3f, Wilson 95%% [%.3f, %.3f]",
                     within, errors.count, Double(within) / Double(max(errors.count, 1)), bound.lower, bound.upper))
        func quantile(_ q: Double) -> Double { sorted.isEmpty ? .nan : sorted[min(sorted.count - 1, Int(Double(sorted.count) * q))] }
        let format = "PU.69 deskew vs hand quads: n %d, median %.2f deg, p90 %.2f deg, mean %.2f deg; "
            + ">6 deg n %d median %.2f; %.1f ms/row (this build)"
        print(String(format: format,
                     errors.count, quantile(0.5), quantile(0.9), errors.reduce(0, +) / Double(max(errors.count, 1)),
                     large.count, large.sorted().dropFirst(large.count / 2).first ?? .nan,
                     seconds * 1000 / Double(max(errors.count, 1))))
        #expect(!errors.isEmpty)
    }

    /// PU.69's F6: whether the estimator's confidence separates a good angle
    /// (within 1 deg of the drawn one) from a bad one (more than 2 deg off), on
    /// the TRAIN split, where a threshold on it would be fitted. Printed as the area
    /// under the ROC curve per statistic: 0.5 separates nothing.
    @Test("the angle's confidence separates good angles from bad ones", .pumpFixturesPresent,
          .enabled(if: ProcessInfo.processInfo.environment["PUMP_DESKEW"] == "1", "PUMP_DESKEW=1"))
    func confidenceSeparatesGoodFromBad() throws {
        let data = try Data(contentsOf: PumpReaderTestSupport.windowsURL)
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        var good: [PumpRowDeskew.Confidence] = [], bad: [PumpRowDeskew.Confidence] = []
        for (name, value) in root.sorted(by: { $0.key < $1.key }) {
            guard name != "_about", PumpReaderTestSupport.isReviewedTrain(name), let ann = value as? [String: Any],
                  ((ann["rotationCW"] as? NSNumber)?.intValue ?? 0) == 0,
                  let image = PumpReaderTestSupport.loadRGB(
                      url: PumpReaderTestSupport.pumpFixturesRoot.appendingPathComponent(name)) else { continue }
            for raw in ann["windows"] as? [[String: Any]] ?? [] {
                guard let field = raw["field"] as? String, ["total", "liters", "unitPrice"].contains(field),
                      let quad = raw["quad"] as? [[Double]], quad.count == 4 else { continue }
                let hand = PumpReaderTestSupport.quadPixels(quad, width: image.width, height: image.height)
                let drawn = atan2(Double(hand[1].y - hand[0].y), Double(hand[1].x - hand[0].x)) * 180 / .pi
                let xs = hand.map(\.x), ys = hand.map(\.y)
                let upright = [CGPoint(x: xs.min()!, y: ys.min()!), CGPoint(x: xs.max()!, y: ys.min()!),
                               CGPoint(x: xs.max()!, y: ys.max()!), CGPoint(x: xs.min()!, y: ys.max()!)]
                let found = PumpRowDeskew.deskew(upright, in: image)
                guard let confidence = found.confidence else { continue }
                let error = abs(found.degrees - drawn)
                if error <= 1 { good.append(confidence) } else if error > 2 { bad.append(confidence) }
            }
        }
        func auroc(_ key: (PumpRowDeskew.Confidence) -> Double) -> Double {
            var wins = 0.0
            for g in good { for b in bad { wins += key(g) > key(b) ? 1 : (key(g) == key(b) ? 0.5 : 0) } }
            return wins / Double(max(good.count * bad.count, 1))
        }
        print(String(format: "PU.69 F6 (train): good %d, bad %d; AUROC peakRatio %.3f, dominance %.3f, peakMass %.3f",
                     good.count, bad.count, auroc(\.peakRatio), auroc(\.dominance), auroc(\.peakMass)))
        #expect(!good.isEmpty && !bad.isEmpty)
    }

}

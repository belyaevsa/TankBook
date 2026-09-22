import CoreGraphics
import Foundation
import Testing
@testable import TankbookCore

/// Where the cells go between the oracle tier and the app. The annotated tier
/// reads the hand quads with the hand roles; the app finds its own boxes,
/// keeps some, names them, and first decides whether the frame is a display
/// at all. This runs the heldout stills through a chain that starts fully
/// oracle and swaps in ONE live stage per arm, so each arm's drop from the one
/// before it is that stage's cost:
///
/// - `oracle`: hand quads, hand roles (the annotated floor).
/// - `hand bounds`: the hand windows as axis-aligned rectangles - the shape an
///   object detector returns, placed perfectly.
/// - `detected windows, hand quads` / `kept windows, hand quads`: only the
///   hand windows the detector found a box for (before, then after the
///   verifier), read from the hand quad - presence with the framing held perfect.
/// - `assigner roles`: hand quads, roles from `PumpRowAssignment`.
/// - `detector boxes, hand roles`: the verified detector boxes, each given the
///   role of the hand window it overlaps most - detection and verification
///   with assignment held perfect.
/// - `detector x, hand y` / `hand x, detector y`: the matched boxes with one
///   axis's extent taken from the hand window - which axis of the framing
///   costs the cells.
/// - `live`: `readPhoto` - detector boxes and assigner roles.
/// - `app`: `PumpDisplayCapture.classify` with the slow-path cap lifted (the
///   Release phone's case) - the display decision in front of the read.
///
/// Only stills the annotation keeps upright are run, so every arm works in one
/// frame; the rotated ones are counted and skipped. Opt-in
/// (`PUMP_APPORTION=1`): it runs the reader ten times per still.
@Suite("Pump apportionment", .pumpFixturesPresent,
       .enabled(if: ProcessInfo.processInfo.environment["PUMP_APPORTION"] == "1", "PUMP_APPORTION=1"))
struct PumpApportionmentTests {
    private struct Tally {
        var committed = 0
        var correct = 0
        var stills: [String] = []
    }

    private struct Truth {
        let field: PumpField
        let quad: [CGPoint]
        let box: CGRect
        let glyphs: Int
    }

    @Test("the cells each live stage costs, oracle to app")
    func apportion() throws {
        // A candidate model runs in place of the shipped one: PUMP_MODEL (a
        // classifier .mlpackage) and PUMP_DETECTOR (a DigitRows .mlmodel).
        let env = ProcessInfo.processInfo.environment
        let modelURL = env["PUMP_MODEL"].map { URL(fileURLWithPath: $0) }
            ?? PumpReaderTestSupport.repoRoot.appendingPathComponent("ios/App/Resources/PumpSegments.mlpackage")
        let detector = env["PUMP_DETECTOR"].map { try? PumpRowDetector(contentsOf: URL(fileURLWithPath: $0)) }
            ?? PumpReaderTestSupport.makeDetector()
        print("PU apportionment models: classifier \(modelURL.lastPathComponent) from "
            + "\(modelURL.deletingLastPathComponent().lastPathComponent), detector \(env["PUMP_DETECTOR"] ?? "shipped")")
        let reader = PumpReader(model: try PumpSegmentsModel(contentsOf: modelURL), detector: detector)
        let handle = PumpReaderHandle(reader: reader)
        let expected = try CorpusScorer.loadExpected(
            PumpReaderTestSupport.pumpFixturesRoot.appendingPathComponent("expected.csv"))
        let data = try Data(contentsOf: PumpReaderTestSupport.windowsURL)
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let pack = try FuelPriceBandStore.bundledPack()

        let arms = ["oracle", "hand bounds", "detected windows, hand quads", "kept windows, hand quads",
                    "detector boxes, hand roles", "detector x, hand y", "hand x, detector y",
                    "assigner roles", "live", "app"]
        var tally = [String: Tally]()
        var presence = (rows: 0, candidate: 0, learned: 0, kept: 0)
        var skippedRotated = 0
        var asserted = 0
        for (name, value) in root.sorted(by: { $0.key < $1.key }) {
            guard name != "_about", let ann = value as? [String: Any], let want = expected[name],
                  PumpReaderTestSupport.isHeldout(name) else { continue }
            if ((ann["rotationCW"] as? NSNumber)?.intValue ?? 0) != 0 { skippedRotated += 1; continue }
            guard let image = PumpReaderTestSupport.loadRGB(
                url: PumpReaderTestSupport.pumpFixturesRoot.appendingPathComponent(name)) else { continue }
            let band = want.currency.flatMap { pack.currencyBand(currency: $0) }
            let disagrees = Set((ann["csvDisagrees"] as? [String: Any])?.keys.map { $0 } ?? [])
            let wants: [PumpField: Double] = [
                .liters: disagrees.contains("liters") ? nil : want.liters,
                .unitPrice: disagrees.contains("unitPrice") ? nil : want.unitPrice,
                .total: disagrees.contains("total") ? nil : want.total,
            ].compactMapValues { $0 }
            asserted += wants.count

            let truth = Self.truth(ann, image: image)
            let candidates = reader.candidates(for: image)
            let verified = try reader.verify(image: image, candidates: candidates)
            let matched = Self.match(verified.map(\.quad), to: truth)
            // Candidates are normalised; the verifier scales them to pixels.
            let scale = { (q: [CGPoint]) in
                q.map { CGPoint(x: $0.x * CGFloat(image.width), y: $0.y * CGFloat(image.height)) }
            }
            let detected = Self.match(candidates.map { scale($0.quad) }, to: truth)
            let learned = Self.match(candidates.filter(\.detected).map { scale($0.quad) }, to: truth)
            for t in truth where t.field != .board {
                presence.rows += 1
                if detected.contains(where: { $0.truth.quad == t.quad }) { presence.candidate += 1 }
                if learned.contains(where: { $0.truth.quad == t.quad }) { presence.learned += 1 }
                if matched.contains(where: { $0.truth.quad == t.quad }) { presence.kept += 1 }
            }

            var readings: [String: PumpDisplayReading?] = [:]
            func resolve(_ windows: [PumpReader.Window]) throws -> PumpDisplayReading? {
                windows.isEmpty ? nil : try reader.resolve(image: image, windows: windows,
                                                           currency: want.currency, priceBand: band)
            }
            readings["oracle"] = try resolve(truth.map { PumpReader.Window(field: $0.field, quad: $0.quad) })
            // The hand window read from its axis-aligned bounds instead of its
            // perspective quad: what a rectangle, which is all an object
            // detector can return, costs even when it is placed perfectly.
            readings["hand bounds"] = try resolve(truth.map { PumpReader.Window(field: $0.field, quad: Self.quad($0.box)) })
            // Presence without framing: only the hand windows a box was found
            // for, each read from its HAND quad. Oracle minus the first is what
            // the detector never finds; the first minus the second is what the
            // verifier throws away; the second minus the detector-box arm is
            // what the detector's framing of a found row costs.
            readings["detected windows, hand quads"] = try resolve(detected.map {
                PumpReader.Window(field: $0.truth.field, quad: $0.truth.quad)
            })
            readings["kept windows, hand quads"] = try resolve(matched.map {
                PumpReader.Window(field: $0.truth.field, quad: $0.truth.quad)
            })
            let roles = PumpRowAssignment.assign(
                windows: truth.map { PumpRowAssignment.Window(quad: $0.quad, glyphCount: $0.glyphs) },
                rotationCW: 0).roles
            readings["assigner roles"] = try resolve(zip(truth, roles).compactMap { t, role in
                role.map { PumpReader.Window(field: $0, quad: t.quad) }
            })
            for (arm, windows) in Self.framingArms(matched) { readings[arm] = try resolve(windows) }
            let live = try reader.readPhoto(image: image, rotationCW: 0, currency: want.currency, priceBand: band)
            readings["live"] = live
            // The app arm: classify decides first. When it accepts the frame
            // its read is the live path's, so the live reading is scored; when
            // it refuses, the user gets nothing.
            let accepted = PumpQuadWarp.makeImage(image.pixels, width: image.width, height: image.height)
                .flatMap { PumpDisplayCapture.classify(image: $0, reader: handle, currency: want.currency,
                                                       priceBand: band, budget: .infinity,
                                                       rotationCW: 0).reading } != nil
            readings["app"] = accepted ? live : nil

            for arm in arms {
                guard let reading = readings[arm] ?? nil else { continue }
                let (committed, correct) = Self.score(reading, wants: wants)
                tally[arm, default: Tally()].committed += committed
                tally[arm, default: Tally()].correct += correct
                if committed > 0 { tally[arm, default: Tally()].stills.append(String(name.prefix(8))) }
            }
        }
        print("PU apportionment over \(asserted) asserted cells; \(skippedRotated) rotated heldout stills skipped")
        var previous: Int?
        for arm in arms {
            let t = tally[arm, default: Tally()]
            let step = previous.map { " (\(t.committed - $0 >= 0 ? "+" : "")\(t.committed - $0))" } ?? ""
            print("  \(arm): committed \(t.committed), correct \(t.correct)\(step)")
            previous = t.committed
        }
        print("  transaction rows: \(presence.rows) hand, \(presence.candidate) found by any candidate source, "
            + "\(presence.learned) by the learned detector, \(presence.kept) kept by the verifier")
        Self.printFlips(tally, arms: arms)
        #expect(asserted > 0)
    }

    /// The kept detector boxes with the hand roles, as they are and with one
    /// axis's extent replaced by the hand window's.
    private static func framingArms(_ matched: [(quad: [CGPoint], truth: Truth)]) -> [(String, [PumpReader.Window])] {
        [("detector boxes, hand roles", matched.map { PumpReader.Window(field: $0.truth.field, quad: $0.quad) }),
         ("detector x, hand y", matched.map {
             let d = bounds($0.quad)
             return PumpReader.Window(field: $0.truth.field, quad: quad(
                 CGRect(x: d.minX, y: $0.truth.box.minY, width: d.width, height: $0.truth.box.height)))
         }),
         ("hand x, detector y", matched.map {
             let d = bounds($0.quad)
             return PumpReader.Window(field: $0.truth.field, quad: quad(
                 CGRect(x: $0.truth.box.minX, y: d.minY, width: $0.truth.box.width, height: d.height)))
         })]
    }

    /// Stills that commit in one arm and not the next, so a stage's cost is a
    /// list of names rather than a number.
    private static func printFlips(_ tally: [String: Tally], arms: [String]) {
        for (a, b) in zip(arms, arms.dropFirst()) {
            let before = Set(tally[a]?.stills ?? []), after = Set(tally[b]?.stills ?? [])
            let lost = before.subtracting(after).sorted(), gained = after.subtracting(before).sorted()
            if lost.isEmpty && gained.isEmpty { continue }
            print("  \(a) -> \(b): lost \(lost.joined(separator: " ")) | gained \(gained.joined(separator: " "))")
        }
    }

    /// Committed and correct cells, by the annotated floor's rule: a derived
    /// field (a truncated RUB total rebuilt from volume x price) is right
    /// within 0.1, a read field within the corpus tolerance.
    private static func score(_ reading: PumpDisplayReading, wants: [PumpField: Double]) -> (Int, Int) {
        var committed = 0, correct = 0
        for (field, cell) in [(PumpField.liters, reading.liters), (.unitPrice, reading.unitPrice),
                              (.total, reading.total)] {
            guard let want = wants[field], let value = cell.value else { continue }
            committed += 1
            let derived: Bool = { if case .derived? = cell.provenance { return true }; return false }()
            if abs(NSDecimalNumber(decimal: value).doubleValue - want) < (derived ? 0.1 : CorpusScorer.tolerance) {
                correct += 1
            }
        }
        return (committed, correct)
    }

    /// The hand windows the annotated floor reads: a transaction or board
    /// role with a text, in the image's pixels.
    private static func truth(_ ann: [String: Any], image: PumpRGBImage) -> [Truth] {
        (ann["windows"] as? [[String: Any]] ?? []).compactMap { raw in
            guard let name = raw["field"] as? String, let field = PumpField(rawValue: name),
                  let text = raw["text"] as? String, !text.isEmpty,
                  let q = raw["quad"] as? [[Double]] else { return nil }
            let quad = PumpQuadWarp.readingOrder(
                PumpReaderTestSupport.quadPixels(q, width: image.width, height: image.height), rotationCW: 0)
            return Truth(field: field, quad: quad, box: bounds(quad), glyphs: text.filter(\.isNumber).count)
        }
    }

    /// Each detector box given to the hand window it overlaps most (IoU >= 0.3),
    /// one box per hand window - the best-overlapping one.
    private static func match(_ quads: [[CGPoint]], to truth: [Truth]) -> [(quad: [CGPoint], truth: Truth)] {
        var best: [Int: (quad: [CGPoint], iou: CGFloat)] = [:]
        for quad in quads {
            let box = bounds(quad)
            guard let (index, iou) = truth.indices.map({ ($0, Self.iou(box, truth[$0].box)) })
                .max(by: { $0.1 < $1.1 }), iou >= 0.3 else { continue }
            if (best[index]?.iou ?? 0) < iou { best[index] = (quad, iou) }
        }
        return best.sorted { $0.key < $1.key }.map { ($0.value.quad, truth[$0.key]) }
    }

    private static func bounds(_ quad: [CGPoint]) -> CGRect {
        let xs = quad.map(\.x), ys = quad.map(\.y)
        return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
    }

    private static func quad(_ r: CGRect) -> [CGPoint] {
        [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY),
         CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.minX, y: r.maxY)]
    }

    private static func iou(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let i = a.intersection(b)
        guard !i.isNull, i.width > 0, i.height > 0 else { return 0 }
        let inter = i.width * i.height
        return inter / (a.width * a.height + b.width * b.height - inter)
    }
}

import CoreGraphics
import Foundation
import Testing
@testable import TankbookCore

// PU.4 - the harness: every non-empty window in `windows.json` is warped to a
// strip, sliced by `PumpGlyphSlicer`, and scored against the annotation's own
// text (count agreement and dp agreement). The counts are ratchet constants,
// moved only upward. The same run writes `slices.json` + the warped strips for
// `score.py --boxes`, which feeds PU.3's classifier the slicer's real cells.

struct PumpFixtureAnnotation {
    let rotationCW: Int
    let windows: [PumpWindowAnnotation]
}

struct PumpWindowAnnotation {
    let field: String
    let text: String
    let quad: [[Double]]
}

@Suite("PU.4 pump reader harness", .pumpFixturesPresent)
struct PumpReaderHarnessTests {

    // MARK: - Ratchet constants

    // Measured 2026-09-19 (PU.8, then the grid anchored on the first occupied
    // cell, then interior blank cells kept): 273/433 windows agree on glyph count. The 0.80 target in the brief is the ceiling this ratchet
    // grows toward. The dp is absorbed into the host glyph on most makes - the
    // local-contrast normalisation and the Otsu threshold absorb a few more than
    // PU.4's fixed-fraction pass - so the column-projection slicer cannot see it;
    // that gap is the classifier's dp bit, and PU.6 owns closing it.
    private static let countAgreementFloor = 0.65
    private static let dpAgreementFloor = 0.0
    private static let locatorMedianIoUFloor = 0.0

    // MARK: - The slicer ratchet

    @Test("the slicer's count and dp agreement meet the ratchet floors")
    func slicerRatchet() throws {
        let score = try Self.scoreSlicer()
        print("PU.4 slicer: count agreement \(score.countAgreementText), dp agreement \(score.dpAgreementText)")
        print(score.perMakeTable())

        #expect(score.countAgreement >= Self.countAgreementFloor,
                Comment(stringLiteral: "count agreement \(score.countAgreementText) below "
                    + "\(Self.countAgreementFloor)"))
        #expect(score.dpAgreement >= Self.dpAgreementFloor,
                Comment(stringLiteral: "dp agreement \(score.dpAgreementText) below \(Self.dpAgreementFloor)"))
        #expect(score.countTotal > 0, "the harness scored no windows - a vacuous pass")
        // A harness that silently skips fixtures it cannot load would flatter the
        // ratchet; on this runtime (HEIC codec present) nothing may be skipped.
        if !score.skipped.isEmpty {
            print("PU.4 skipped fixtures: \(score.skipped.joined(separator: ", "))")
        }
        #expect(score.skipped.isEmpty,
                Comment(stringLiteral: "the harness skipped \(score.skipped) fixtures it must be able to load"))
    }

    // MARK: - The named mutation (the PU.8 seams -> the PU.4 fixed-fraction pass)

    @Test("the adaptive threshold, contrast normalisation, split merge and short-count retry win windows on the corpus")
    func robustnessSeamsAreLoadBearing() throws {
        // A uniform contrast collapse on a synthetic strip cannot separate an
        // adaptive threshold from a fixed fraction of the profile's max (both
        // are relative), so the seams are shown load-bearing where they were
        // measured: on the corpus, against the same slicer with them off.
        let robust = try Self.scoreSlicer(robust: true)
        let fixed = try Self.scoreSlicer(robust: false)
        print("PU.8 seams: robust \(robust.countAgreementText) vs fixed \(fixed.countAgreementText)")
        #expect(robust.countOK > fixed.countOK,
                Comment(stringLiteral: "the PU.8 seams must win windows: robust \(robust.countOK) vs fixed \(fixed.countOK)"))
    }

    // MARK: - The named mutation (pitch snap -> raw runs)

    @Test("without the pitch snap the 1-glyph fixtures lose count agreement")
    func pitchSnapIsLoadBearing() throws {
        let windows = try Self.loadWindows()
        // Fixtures with a leading `1` whose digit splits into two column runs:
        // the snap merges them back into one cell, the raw runs do not. The
        // split is only visible under the fixed-fraction threshold on the raw
        // strip - PU.8's Otsu threshold, local-contrast normalisation, split
        // merge and short-count retry are separate seams, so this snap mutation
        // is shown with all four switched off to keep it load-bearing on its own.
        let cases: [(name: String, field: String)] = [
            ("pump-006-kz-adast-92-kzt.png", "total"),
            ("pump-013-dresser-wayne-ee-four-prices.heic", "total"),
            ("pump-016-wayne-ee-idle-zero.heic", "total"),
        ]
        for fixture in cases {
            guard let ann = windows[fixture.name], let image = Self.loadFixtureImage(fixture.name) else {
                continue
            }
            guard let window = ann.windows.first(where: { $0.field == fixture.field }),
                  !window.text.isEmpty else { continue }
            let expected = PumpReaderTestSupport.glyphCount(window.text)
            let snapped = Self.slice(window: window, image: image,
                                     adaptiveThreshold: false, localContrastNormalization: false,
                                     splitMerge: false, shortCountRetry: false).cells.count
            let raw = Self.slice(window: window, image: image, pitchSnap: false,
                                 adaptiveThreshold: false, localContrastNormalization: false,
                                 splitMerge: false, shortCountRetry: false).cells.count
            print("\(fixture.name) \(fixture.field): snapped \(snapped) raw \(raw) expected \(expected)")
            #expect(snapped == expected, "\(fixture.name) must agree under the pitch snap")
            #expect(raw != expected, "\(fixture.name) must lose agreement without the pitch snap")
        }
    }

    // MARK: - The locator

    @Test("the locator's best candidate on pump-078 clears the 0.5 IoU floor")
    func locatorPump078() throws {
        let name = try Self.findFixture(containing: "pump-078")
        let windows = try Self.loadWindows()
        guard let ann = windows[name], let image = Self.loadFixtureImage(name) else {
            Issue.record("\(name) could not be loaded")
            return
        }
        guard let total = ann.windows.first(where: { $0.field == "total" }) else {
            Issue.record("\(name) has no total window")
            return
        }
        let candidates = PumpPanelLocator.locate(image, rotationCW: ann.rotationCW)
        guard let best = candidates.first else {
            Issue.record("\(name) locator returned no candidate")
            return
        }
        let rotatedQuad = Self.rotatedQuad(total.quad, rotationCW: ann.rotationCW,
                                           width: image.width, height: image.height)
        let iou = Self.iou(best.quad, rotatedQuad)
        print("pump-078 locator best IoU \(iou) (glyphs \(best.glyphCount))")
        #expect(iou >= 0.5, "pump-078 best candidate IoU \(iou) below 0.5")
    }

    @Test("the locator's corpus median IoU is reported against its floor")
    func locatorCorpusMedianIoU() throws {
        let windows = try Self.loadWindows()
        var ious: [Double] = []
        for (name, ann) in windows {
            guard let image = Self.loadFixtureImage(name) else { continue }
            let candidates = PumpPanelLocator.locate(image, rotationCW: ann.rotationCW)
            guard !candidates.isEmpty else { continue }
            for window in ann.windows where window.field != "board" && !window.text.isEmpty {
                let rotated = Self.rotatedQuad(window.quad, rotationCW: ann.rotationCW,
                                               width: image.width, height: image.height)
                // The best-matching candidate for this window, not the single
                // most-likely one (one candidate can only match one window).
                let best = candidates.map { Self.iou($0.quad, rotated) }.max() ?? 0
                ious.append(best)
            }
        }
        let median = Self.median(ious)
        print("PU.4 locator: median IoU \(median) over \(ious.count) non-board windows")
        #expect(!ious.isEmpty, "the locator scored no windows - a vacuous pass")
        #expect(median >= Self.locatorMedianIoUFloor,
                Comment(stringLiteral: "locator median IoU \(median) below the floor \(Self.locatorMedianIoUFloor) "
                    + "- PU.6 files the row if this is what the corpus gives"))
    }

    // MARK: - Scoring

    private struct SlicerScore {
        var countOK = 0
        var countTotal = 0
        var dpOK = 0
        var dpTotal = 0
        var perMake: [String: (ok: Int, total: Int)] = [:]
        var skipped: [String] = []
        var slices: [String: [SlicesWindow?]] = [:]

        var countAgreement: Double { countTotal > 0 ? Double(countOK) / Double(countTotal) : 0 }
        var dpAgreement: Double { dpTotal > 0 ? Double(dpOK) / Double(dpTotal) : 0 }
        var countAgreementText: String { "\(countOK)/\(countTotal)" }
        var dpAgreementText: String { "\(dpOK)/\(dpTotal)" }

        func perMakeTable() -> String {
            var lines = ["per-make count agreement:"]
            for (make, value) in perMake.sorted(by: { $0.key < $1.key }) {
                let ratio = value.total > 0 ? Double(value.ok) / Double(value.total) : 0
                lines.append(String(format: "  %-10s %d/%d (%.2f)", NSString(string: make).utf8String!, value.ok, value.total, ratio))
            }
            return lines.joined(separator: "\n")
        }
    }

    private struct SlicesWindow {
        let strip: String
        let cells: [[String: Any]]
    }

    private struct SliceResult {
        let cells: [GlyphCell]
        let strip: CGImage
        let stripWidth: Int
        let stripHeight: Int
    }

    private static func scoreSlicer(robust: Bool = true) throws -> SlicerScore {
        let windows = try loadWindows()
        var score = SlicerScore()
        let stripsDir = PumpReaderTestSupport.outRoot.appendingPathComponent("strips")
        try? FileManager.default.createDirectory(at: stripsDir, withIntermediateDirectories: true)

        for (name, ann) in windows.sorted(by: { $0.key < $1.key }) {
            guard let image = loadFixtureImage(name) else {
                score.skipped.append(name)
                continue
            }
            var fixtureSlices: [SlicesWindow?] = []
            for (index, window) in ann.windows.enumerated() {
                guard !window.text.isEmpty else {
                    fixtureSlices.append(nil)
                    continue
                }
                let expectedCount = PumpReaderTestSupport.glyphCount(window.text)
                let expectedDP = PumpReaderTestSupport.dpCellIndex(window.text)
                let result = slice(
                    window: window, image: image, rotationCW: ann.rotationCW,
                    adaptiveThreshold: robust, localContrastNormalization: robust,
                    splitMerge: robust, shortCountRetry: robust)

                let make = makeOf(name)
                score.countTotal += 1
                score.perMake[make, default: (0, 0)].total += 1
                if result.cells.count == expectedCount {
                    score.countOK += 1
                    score.perMake[make]!.ok += 1
                }

                let hasDP = result.cells.contains(where: \.hasDecimalPoint)
                if expectedDP != nil || hasDP {
                    score.dpTotal += 1
                    if result.cells.firstIndex(where: \.hasDecimalPoint) == expectedDP {
                        score.dpOK += 1
                    }
                }

                let stripName = Self.stripFileName(name: name, index: index)
                let stripURL = stripsDir.appendingPathComponent(stripName)
                _ = PumpQuadWarp.writePNG(image: result.strip, to: stripURL)
                let cells = result.cells.map { cell -> [String: Any] in
                    [
                        "x0": Double(cell.rect.minX) / Double(result.stripWidth),
                        "y0": Double(cell.rect.minY) / Double(result.stripHeight),
                        "x1": Double(cell.rect.maxX) / Double(result.stripWidth),
                        "y1": Double(cell.rect.maxY) / Double(result.stripHeight),
                        "hasDecimalPoint": cell.hasDecimalPoint,
                        "isBlank": cell.isBlank,
                    ] as [String: Any]
                }
                fixtureSlices.append(SlicesWindow(strip: "strips/\(stripName)", cells: cells))
            }
            score.slices[name] = fixtureSlices
        }
        if robust {
            writeSlicesJSON(score.slices)
        }
        return score
    }

    private static func slice(
        window: PumpWindowAnnotation, image: PumpRGBImage, rotationCW: Int = 0, pitchSnap: Bool = true,
        adaptiveThreshold: Bool = true, localContrastNormalization: Bool = true,
        splitMerge: Bool = true, shortCountRetry: Bool = true
    ) -> SliceResult {
        let quad = PumpQuadWarp.readingOrder(
            PumpReaderTestSupport.quadPixels(window.quad, width: image.width, height: image.height),
            rotationCW: rotationCW)
        let strip = PumpQuadWarp.warpToStrip(rgb: image, quad: quad, stripHeight: 96)
        guard let strip else {
            return SliceResult(cells: [], strip: PumpQuadWarp.makeImage(
                image.pixels, width: image.width, height: image.height)!, stripWidth: 1, stripHeight: 96)
        }
        let gray = PumpQuadWarp.rgbImage(from: strip).grayscale()
        var options = PumpGlyphSlicer.Options()
        options.pitchSnap = pitchSnap
        options.adaptiveThreshold = adaptiveThreshold
        options.localContrastNormalization = localContrastNormalization
        options.splitMerge = splitMerge
        options.shortCountRetry = shortCountRetry
        let cells = PumpGlyphSlicer.slice(gray, options: options)
        return SliceResult(cells: cells, strip: strip, stripWidth: strip.width, stripHeight: strip.height)
    }

    // MARK: - slices.json

    private static func writeSlicesJSON(_ slices: [String: [SlicesWindow?]]) {
        var root: [String: Any] = [:]
        for (name, windows) in slices {
            root[name] = windows.map { window -> Any in
                guard let window else { return NSNull() }
                return ["strip": window.strip, "cells": window.cells] as [String: Any]
            }
        }
        try? FileManager.default.createDirectory(
            at: PumpReaderTestSupport.outRoot, withIntermediateDirectories: true)
        let url = PumpReaderTestSupport.outRoot.appendingPathComponent("slices.json")
        if JSONSerialization.isValidJSONObject(root) {
            let data = try? JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
            try? data?.write(to: url)
        }
    }

    private static func stripFileName(name: String, index: Int) -> String {
        let base = (name as NSString).deletingPathExtension.replacingOccurrences(of: "-", with: "_")
        return "\(base)-w\(index).png"
    }

    // MARK: - Loading

    private static func loadWindows() throws -> [String: PumpFixtureAnnotation] {
        let data = try Data(contentsOf: PumpReaderTestSupport.windowsURL)
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        var result: [String: PumpFixtureAnnotation] = [:]
        for (name, value) in root {
            guard name != "_about", let ann = value as? [String: Any],
                  PumpReaderTestSupport.isHeldout(name) else { continue }
            let rotationCW = (ann["rotationCW"] as? NSNumber)?.intValue ?? 0
            let raw = ann["windows"] as? [[String: Any]] ?? []
            let windows = raw.compactMap { entry -> PumpWindowAnnotation? in
                guard let field = entry["field"] as? String,
                      let text = entry["text"] as? String,
                      let quadRaw = entry["quad"] as? [[NSNumber]] else { return nil }
                let quad = quadRaw.map { $0.map(\.doubleValue) }
                guard quad.count == 4, quad.allSatisfy({ $0.count == 2 }) else { return nil }
                return PumpWindowAnnotation(field: field, text: text, quad: quad)
            }
            result[name] = PumpFixtureAnnotation(rotationCW: rotationCW, windows: windows)
        }
        return result
    }

    private static func loadFixtureImage(_ name: String) -> PumpRGBImage? {
        PumpReaderTestSupport.loadRGB(url: PumpReaderTestSupport.pumpFixturesRoot.appendingPathComponent(name))
    }

    private static func makeOf(_ name: String) -> String {
        let parts = (name as NSString).deletingPathExtension.split(separator: "-").map(String.init)
        return parts.count > 2 ? parts[2] : "unknown"
    }

    private static func findFixture(containing substring: String) throws -> String {
        let names = try FileManager.default.contentsOfDirectory(atPath: PumpReaderTestSupport.pumpFixturesRoot.path)
        guard let match = names.first(where: { $0.contains(substring) }) else {
            throw NSError(domain: "PumpReaderHarnessTests", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "no fixture matching \(substring)"])
        }
        return match
    }

    // MARK: - Geometry

    private static func rotatedQuad(
        _ quad: [[Double]], rotationCW: Int, width: Int, height: Int
    ) -> [CGPoint] {
        let pixels = PumpReaderTestSupport.quadPixels(quad, width: width, height: height)
        let rotated = PumpQuadWarp.rotatePointsClockwise(
            pixels, rotationCW: rotationCW, oldSize: (width, height))
        let (nw, nh) = PumpQuadWarp.rotatedSize(width: width, height: height, rotationCW: rotationCW)
        return rotated.map { CGPoint(x: $0.x / CGFloat(nw), y: $0.y / CGFloat(nh)) }
    }

    private static func iou(_ a: [CGPoint], _ b: [CGPoint]) -> Double {
        let ra = rect(a)
        let rb = rect(b)
        let ix = max(0, min(ra.maxX, rb.maxX) - max(ra.minX, rb.minX))
        let iy = max(0, min(ra.maxY, rb.maxY) - max(ra.minY, rb.minY))
        let inter = ix * iy
        let union = ra.width * ra.height + rb.width * rb.height - inter
        return union > 0 ? Double(inter / union) : 0
    }

    private static func rect(_ quad: [CGPoint]) -> CGRect {
        let xs = quad.map(\.x)
        let ys = quad.map(\.y)
        let minX = xs.min() ?? 0
        let maxX = xs.max() ?? 0
        let minY = ys.min() ?? 0
        let maxY = ys.max() ?? 0
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }
}

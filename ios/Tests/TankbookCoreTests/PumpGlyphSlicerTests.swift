import CoreGraphics
import Foundation
import Testing
@testable import TankbookCore

// PU.4 - the slicer's synthetic oracle tests. Test 1 replays a PU.1 row render
// (seed 3, the committed renderer is the oracle) and checks the slicer recovers
// one cell per glyph box with each cell centre inside the matching box. Test 2
// checks the polarity decision: the same string on an LCD (dark on light) and an
// LED (light on dark) strip must slice to the same count.

struct SynthBox {
    let x: Double
    let y: Double
    let w: Double
    let h: Double
    /// A separator drawn in its own narrow cell (some makes). The slicer's
    /// contract attaches a decimal mark to the glyph it follows, so such a box
    /// is not a cell the slicer is expected to emit.
    let isDecimalOnly: Bool
}

extension SynthRow {
    /// The boxes the slicer is expected to produce: one per glyph cell, a
    /// separator-only box folded into the glyph before it.
    var glyphBoxes: [SynthBox] { boxes.filter { !$0.isDecimalOnly } }
}

struct SynthRow {
    let file: String
    let text: String
    let boxes: [SynthBox]
}

@Suite("PU.4 pump glyph slicer")
struct PumpGlyphSlicerTests {

    private static let synth = loadSynth()

    private static var pythonAvailable: Bool {
        FileManager.default.fileExists(
            atPath: PumpReaderTestSupport.repoRoot
                .appendingPathComponent("ml/pump-reader/.venv/bin/python").path)
    }

    @Test(
        "a PU.1 row slices into its box count with each centre inside its box",
        .enabled(if: pythonAvailable, "ml/pump-reader/.venv/bin/python is not available to replay the PU.1 render")
    )
    func slicesSyntheticRowToItsBoxes() throws {
        let loaded = try #require(Self.synth)
        // Perspective-free rows are straight strips with axis-aligned boxes.
        let rows = loaded.rows.filter { Self.isPerspectiveFree($0) }
        #expect(rows.count >= 5, "only \(rows.count) perspective-free rows - a thin oracle")
        var agreed = 0
        var centresInside = 0
        var centresTotal = 0
        for row in rows {
            let image = try #require(PumpReaderTestSupport.loadRGB(url: loaded.imagesDir.appendingPathComponent(row.file)))
            let cells = PumpGlyphSlicer.slice(image.grayscale())
            let boxes = row.glyphBoxes
            if cells.count == boxes.count {
                agreed += 1
                for (cell, box) in zip(cells, boxes) {
                    centresTotal += 1
                    let centre = cell.rect.midX
                    if centre >= CGFloat(box.x) && centre <= CGFloat(box.x + box.w) { centresInside += 1 }
                }
            } else {
                print("PU.4 synthetic miscount: \(row.text) sliced \(cells.count), oracle \(boxes.count)")
            }
        }
        // Oracle: the renderer's own boxes. Rendered rows carry the same glare
        // and reflection the corpus does, so a row that washes out is a real
        // miss, not an oracle defect; the floor is the share that must agree.
        let agreement = Double(agreed) / Double(max(rows.count, 1))
        print("PU.4 synthetic count agreement \(agreed)/\(rows.count)")
        #expect(agreement >= 0.8, "count agreement \(agreement) on \(rows.count) synthetic rows")
        #expect(centresTotal > 0 && centresInside == centresTotal,
                "\(centresTotal - centresInside) cell centres outside their box")
    }

    @Test("an LCD and an LED strip of the same string slice to the same count")
    func polarityDoesNotChangeCount() {
        let lcd = Self.makeStrip(darkOnLight: true)
        let led = Self.makeStrip(darkOnLight: false)
        #expect(PumpGlyphSlicer.slice(lcd).count == 3, "LCD strip should slice to 3 cells")
        #expect(PumpGlyphSlicer.slice(led).count == 3, "LED strip should slice to 3 cells")
    }

    @Test(
        "a PU.1 render collapsed to 15 % contrast still slices to its box count",
        .enabled(if: pythonAvailable, "ml/pump-reader/.venv/bin/python is not available to replay the PU.1 render")
    )
    func faintDisplaySlicesToItsBoxes() throws {
        let loaded = try #require(Self.synth)
        let row = try #require(loaded.rows.first(where: { Self.isPerspectiveFree($0) }))
        let image = try #require(PumpReaderTestSupport.loadRGB(url: loaded.imagesDir.appendingPathComponent(row.file)))
        let gray = image.grayscale()
        let faint = Self.collapseContrast(gray, remaining: 0.15)

        let cells = PumpGlyphSlicer.slice(faint)
        #expect(cells.count == row.glyphBoxes.count,
                "faint display sliced \(cells.count) cells, the oracle has \(row.glyphBoxes.count) glyph boxes")

    }

    // MARK: - Synthetic strips

    /// Scales every pixel toward the strip mean until the ink/background
    /// contrast is `remaining` of the original, matching a faint display.
    private static func collapseContrast(_ gray: PumpGrayscale, remaining: Float) -> PumpGrayscale {
        let mean = gray.pixels.reduce(0, +) / Float(gray.pixels.count)
        let pixels = gray.pixels.map { mean + ($0 - mean) * remaining }
        return PumpGrayscale(width: gray.width, height: gray.height, pixels: pixels)
    }

    private static func makeStrip(darkOnLight: Bool) -> PumpGrayscale {
        let pitch = 24
        let width = 3 * pitch
        let height = 40
        let background: Float = darkOnLight ? 0.85 : 0.08
        let ink: Float = darkOnLight ? 0.10 : 0.85
        var pixels = [Float](repeating: background, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let inCell = x % pitch
                if inCell >= 3 && inCell < 15 && y >= 4 && y < 36 {
                    pixels[y * width + x] = ink
                }
            }
        }
        return PumpGrayscale(width: width, height: height, pixels: pixels)
    }

    // MARK: - The PU.1 render replay

    private static func isPerspectiveFree(_ row: SynthRow) -> Bool {
        guard let first = row.boxes.first else { return false }
        let y = first.y
        let h = first.h
        return row.boxes.allSatisfy { abs($0.y - y) < 0.5 && abs($0.h - h) < 0.5 }
    }

    private static func loadSynth() -> (rows: [SynthRow], imagesDir: URL)? {
        let out = PumpReaderTestSupport.outRoot.appendingPathComponent("synth")
        let python = PumpReaderTestSupport.repoRoot
            .appendingPathComponent("ml/pump-reader/.venv/bin/python")
        guard FileManager.default.fileExists(atPath: python.path) else { return nil }

        let process = Process()
        process.executableURL = python
        process.arguments = [
            "-m", "pump_reader.render",
            "--count", "300", "--seed", "3", "--rows",
            "--out", out.path,
        ]
        process.currentDirectoryURL = PumpReaderTestSupport.repoRoot
            .appendingPathComponent("ml/pump-reader")
        let stderr = Pipe()
        process.standardError = stderr
        process.standardOutput = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }

        let rowsURL = out.appendingPathComponent("rows.json")
        guard let data = try? Data(contentsOf: rowsURL),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return nil
        }
        let rows: [SynthRow] = array.compactMap { entry in
            guard let file = entry["file"] as? String,
                  let text = entry["text"] as? String,
                  let boxesRaw = entry["boxes"] as? [[String: Any]] else { return nil }
            let boxes = boxesRaw.compactMap { box -> SynthBox? in
                guard let x = (box["x"] as? NSNumber)?.doubleValue,
                      let y = (box["y"] as? NSNumber)?.doubleValue,
                      let w = (box["w"] as? NSNumber)?.doubleValue,
                      let h = (box["h"] as? NSNumber)?.doubleValue else { return nil }
                return SynthBox(x: x, y: y, w: w, h: h,
                                isDecimalOnly: (box["class"] as? String) == "dp-only")
            }
            guard boxes.count == boxesRaw.count else { return nil }
            return SynthRow(file: file, text: text, boxes: boxes)
        }
        guard !rows.isEmpty else { return nil }
        return (rows, out)
    }
}

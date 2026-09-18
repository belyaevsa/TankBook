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
        // A perspective-free row is a straight strip; its boxes are axis-aligned.
        let row = try #require(loaded.rows.first(where: { Self.isPerspectiveFree($0) }))
        let image = try #require(PumpReaderTestSupport.loadRGB(url: loaded.imagesDir.appendingPathComponent(row.file)))
        let gray = image.grayscale()
        let cells = PumpGlyphSlicer.slice(gray)

        #expect(cells.count == row.boxes.count,
                "sliced \(cells.count) cells, the oracle has \(row.boxes.count) boxes")

        for (index, cell) in cells.enumerated() {
            guard index < row.boxes.count else { break }
            let box = row.boxes[index]
            let centre = cell.rect.midX
            #expect(centre >= CGFloat(box.x) && centre <= CGFloat(box.x + box.w),
                    "cell \(index) centre \(centre) outside box [\(box.x), \(box.x + box.w)]")
        }
    }

    @Test("an LCD and an LED strip of the same string slice to the same count")
    func polarityDoesNotChangeCount() {
        let lcd = Self.makeStrip(darkOnLight: true)
        let led = Self.makeStrip(darkOnLight: false)
        #expect(PumpGlyphSlicer.slice(lcd).count == 3, "LCD strip should slice to 3 cells")
        #expect(PumpGlyphSlicer.slice(led).count == 3, "LED strip should slice to 3 cells")
    }

    // MARK: - Synthetic strips

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
            "--count", "1", "--seed", "3", "--rows",
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
                return SynthBox(x: x, y: y, w: w, h: h)
            }
            guard boxes.count == boxesRaw.count else { return nil }
            return SynthRow(file: file, text: text, boxes: boxes)
        }
        guard !rows.isEmpty else { return nil }
        return (rows, out)
    }
}

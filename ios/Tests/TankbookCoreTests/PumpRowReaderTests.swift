import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import TankbookCore

/// The row reader's decoding against the Python reference
/// (`ml/pump-reader/tests/test_rowreader.py`), and - opt-in - the whole reader
/// against the reference's posteriors on the exported heldout strips.
@Suite("Pump row reader")
struct PumpRowReaderTests {
    /// Frames that say each token, then a blank, with probability 0.9.
    private static func peaked(_ tokens: [Int], perFrame: Int = 3) -> [[Double]] {
        var frames: [Int] = []
        for token in tokens { frames += Array(repeating: token, count: perFrame) + [PumpRowReader.blank] }
        let rest = log(0.1 / Double(PumpRowReader.classCount - 1))
        return frames.map { token in
            (0..<PumpRowReader.classCount).map { $0 == token ? log(0.9) : rest }
        }
    }

    @Test("prefix search decodes a peaked string and the marginals rank its digits first")
    func peakedString() {
        let tokens = [2, 3, PumpRowReader.separator, 4, 9]  // "12.38"
        let frames = Self.peaked(tokens)
        #expect(PumpRowReader.prefixSearch(frames) == tokens)
        let cells = PumpRowReader.posteriors(frames, tokens: tokens)
        #expect(cells.map(\.top.digit) == [1, 2, 3, 8])
        #expect(cells.map(\.decimalPoint) == [false, true, false, false])
    }

    @Test("the forward recursion equals the sum over every alignment that collapses to the label")
    func forwardMatchesEnumeration() {
        var rng = SystemRandomNumberGenerator()
        for _ in 0..<20 {
            let t = 4
            let classes = 4  // blank and three symbols keep the enumeration small
            let frames: [[Double]] = (0..<t).map { _ in
                let raw = (0..<classes).map { _ in Double.random(in: 0.05...1, using: &rng) }
                let sum = raw.reduce(0, +)
                return raw.map { log($0 / sum) } + Array(repeating: -Double.infinity,
                                                         count: PumpRowReader.classCount - classes)
            }
            let label = (0..<Int.random(in: 1...2, using: &rng)).map { _ in Int.random(in: 1..<classes, using: &rng) }
            var total = -Double.infinity
            for code in 0..<Int(pow(Double(classes), Double(t))) {
                var path: [Int] = [], c = code
                for _ in 0..<t { path.append(c % classes); c /= classes }
                var dedup: [Int] = [], last = PumpRowReader.blank
                for s in path {
                    if s != last, s != PumpRowReader.blank { dedup.append(s) }
                    last = s
                }
                guard dedup == label else { continue }
                total = PumpRowReader.logAdd(total, path.enumerated().map { frames[$0.offset][$0.element] }.reduce(0, +))
            }
            let forward = PumpRowReader.logLikelihood(frames, label: label)
            #expect(abs(forward - total) < 1e-9 || (forward == -.infinity && total == -.infinity))
        }
    }

    @Test("a strip narrower than the minimum is padded with its own edge column")
    func narrowStripIsPadded() {
        let width = 30, height = 96
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height { for x in 0..<width { pixels[(y * width + x) * 4] = UInt8(x * 8) } }
        let input = PumpRowReader.input(PumpRGBImage(width: width, height: height, pixels: pixels))
        #expect(input.width == PumpRowReader.minimumWidth)
        let row = (0..<input.width).map { input.rgb[$0 * 3] }
        #expect(Set(row[10...]).count == 1)
    }

    /// `PUMP_ROWREADER_PARITY=<posteriors-raw.json>` and `PUMP_ROWREADER_MODEL=<RowRead.mlpackage>`:
    /// the Swift reader over the strips `PumpRowReaderSpikeTests` exported, against the Python
    /// reference's decoded strings and top posteriors for the same model.
    @Test("parity with the Python reference on the exported heldout strips",
          .enabled(if: ProcessInfo.processInfo.environment["PUMP_ROWREADER_PARITY"] != nil, "PUMP_ROWREADER_PARITY"))
    func parity() throws {
        let env = ProcessInfo.processInfo.environment
        let reader = try PumpRowReader(contentsOf: URL(fileURLWithPath: try #require(env["PUMP_ROWREADER_MODEL"])))
        let posteriors = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(
            fileURLWithPath: try #require(env["PUMP_ROWREADER_PARITY"])))) as? [[String: Any]] ?? []
        let dir = PumpReaderTestSupport.outRoot.appendingPathComponent("rowreader/heldout")
        let index = try JSONSerialization.jsonObject(
            with: Data(contentsOf: dir.appendingPathComponent("index.json"))) as? [[String: Any]] ?? []
        var strips: [String: String] = [:]
        for e in index { strips["\(e["fixture"]!)#\(e["window"]!)"] = e["strip"] as? String }
        var same = 0, total = 0, worst = 0.0
        var differ: [String] = []
        for entry in posteriors {
            guard let fixture = entry["fixture"] as? String, let window = entry["window"] as? Int,
                  let positions = entry["positions"] as? [[[String: Any]]], let sep = entry["sep"] as? [Double],
                  let path = strips["\(fixture)#\(window)"],
                  let source = CGImageSourceCreateWithURL(dir.appendingPathComponent(path) as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { continue }
            let want = positions.enumerated().map { i, p in
                "\(p[0]["digit"] as? Int ?? -1)" + (i < sep.count && sep[i] >= 0.5 ? "." : "")
            }.joined()
            let cells = try reader.read(strip: PumpQuadWarp.rgbImage(from: image)) ?? []
            let got = cells.map { "\($0.top.digit)" + ($0.decimalPoint ? "." : "") }.joined()
            total += 1
            if got == want {
                same += 1
                for (cell, p) in zip(cells, positions) {
                    worst = max(worst, abs(cell.top.logPosterior - (p[0]["logp"] as? Double ?? 0)))
                }
            } else {
                differ.append("\(fixture.prefix(8))#\(window)")
            }
        }
        print("PU.89 row reader parity: \(same)/\(total) strings agree, worst top-posterior gap "
              + String(format: "%.4f", worst) + " nats; differ: \(differ)")
        #expect(total > 200)
        #expect(Double(same) / Double(max(total, 1)) >= 0.99)
    }

    /// Opt-in (`PUMP_ROWREADER_TIMING=1`), meaningful only optimised:
    /// `swift test -c release -Xswiftc -enable-testing --filter PumpRowReaderTests`.
    /// The read step per window on the heldout hand quads: the row reader
    /// against the slicer and cell classifier, the same strips.
    @Test("median milliseconds per window: row reader against slicer and classifier",
          .enabled(if: ProcessInfo.processInfo.environment["PUMP_ROWREADER_TIMING"] == "1"
                   && PumpReaderTestSupport.fixturesPresent))
    func timing() throws {
        let root = PumpReaderTestSupport.repoRoot
        let model = try PumpSegmentsModel(contentsOf: root.appendingPathComponent("ios/App/Resources/PumpSegments.mlpackage"))
        let rowReader = try PumpRowReader(contentsOf: root.appendingPathComponent("ios/App/Resources/RowRead.mlpackage"))
        let cellsArm = PumpReader(model: model)
        let rowArm = PumpReader(model: model, rowReader: rowReader)
        let annotations = try JSONSerialization.jsonObject(
            with: Data(contentsOf: PumpReaderTestSupport.windowsURL)) as? [String: Any] ?? [:]
        var jobs: [(PumpRGBImage, PumpReader.Window)] = []
        for (name, value) in annotations.sorted(by: { $0.key < $1.key }) where jobs.count < 60 {
            guard PumpReaderTestSupport.isHeldout(name), let ann = value as? [String: Any],
                  let image = PumpReaderTestSupport.loadRGB(url: PumpReaderTestSupport.pumpFixturesRoot
                    .appendingPathComponent(name)) else { continue }
            let rotation = (ann["rotationCW"] as? NSNumber)?.intValue ?? 0
            for raw in ann["windows"] as? [[String: Any]] ?? [] {
                guard let field = (raw["field"] as? String).flatMap(PumpField.init(rawValue:)), field != .board,
                      let quad = raw["quad"] as? [[Double]] else { continue }
                jobs.append((image, PumpReader.Window(field: field, quad: PumpQuadWarp.readingOrder(
                    PumpReaderTestSupport.quadPixels(quad, width: image.width, height: image.height),
                    rotationCW: rotation))))
            }
        }
        func median(_ reader: PumpReader) throws -> Double {
            _ = try reader.read(image: jobs[0].0, windows: [jobs[0].1])
            let ms = try jobs.map { image, window -> Double in
                let start = CFAbsoluteTimeGetCurrent()
                _ = try reader.read(image: image, windows: [window])
                return (CFAbsoluteTimeGetCurrent() - start) * 1000
            }.sorted()
            return ms[ms.count / 2]
        }
        let cells = try median(cellsArm), row = try median(rowArm)
        // The row reader's share: the model pass against the decoding.
        var pass = [Double](), decode = [Double]()
        for (image, window) in jobs {
            guard let strip = PumpQuadWarp.warpToStrip(rgb: image, quad: window.quad,
                                                      stripHeight: PumpReader.stripHeight) else { continue }
            let rgb = PumpQuadWarp.rgbImage(from: strip)
            var start = CFAbsoluteTimeGetCurrent()
            let frames = try rowReader.frames(strip: rgb)
            pass.append((CFAbsoluteTimeGetCurrent() - start) * 1000)
            start = CFAbsoluteTimeGetCurrent()
            _ = PumpRowReader.posteriors(frames, tokens: PumpRowReader.prefixSearch(frames))
            decode.append((CFAbsoluteTimeGetCurrent() - start) * 1000)
        }
        print("Row reader split: model pass " + String(format: "%.1f", pass.sorted()[pass.count / 2])
              + " ms, decoding " + String(format: "%.1f", decode.sorted()[decode.count / 2]) + " ms (medians)")
        print("Read step median over \(jobs.count) heldout windows: slicer + classifier "
              + String(format: "%.1f", cells) + " ms, row reader " + String(format: "%.1f", row) + " ms")
        #expect(jobs.count >= 40)
    }
}

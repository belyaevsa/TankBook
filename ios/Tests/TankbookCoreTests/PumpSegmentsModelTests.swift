import CoreGraphics
import Foundation
import Testing
@testable import TankbookCore

/// The exported Core ML classifier, driven from Swift the way the app will
/// drive it, against cells the Python side rendered and labelled.
@Suite("Pump segments model (Core ML)")
struct PumpSegmentsModelTests {

    private static let modelURL = PumpReaderTestSupport.repoRoot
        .appendingPathComponent("ios/App/Resources/PumpSegments.mlpackage")
    private static let python = PumpReaderTestSupport.repoRoot
        .appendingPathComponent("ml/pump-reader/.venv/bin/python")
    private static let cellsDir = PumpReaderTestSupport.outRoot.appendingPathComponent("cells-swift")

    private static var available: Bool {
        FileManager.default.fileExists(atPath: modelURL.path)
            && FileManager.default.fileExists(atPath: python.path)
    }

    @Test("the decoder never returns a non-glyph and recovers a one-bit loss")
    func decoderIsConstrained() {
        // A `9` (a b c d f g) whose segment c reads 0.45: the per-bit threshold
        // would drop c and emit a pattern no display has; the decoder keeps 9.
        var probs = [0.95, 0.95, 0.45, 0.95, 0.05, 0.95, 0.95, 0.05]
        #expect(PumpSegmentsModel.decode(probs).digit == "9")
        probs = [Double](repeating: 0.5, count: 8)
        let tie = PumpSegmentsModel.decode(probs)
        #expect(PumpSegmentsModel.digitPatterns.contains { $0.digit == tie.digit })
        #expect(tie.margin >= 0)
    }

    @Test(
        "the exported model reads Python-rendered slicer cells at >= 90 % and agrees with the Python model",
        .enabled(if: available, "PumpSegments.mlpackage or the training venv is not present")
    )
    func exportedModelReadsRenderedCells() throws {
        try Self.renderCells(count: 300, seed: 11)
        let model = try PumpSegmentsModel(contentsOf: Self.modelURL)
        let labels = try String(contentsOf: Self.cellsDir.appendingPathComponent("labels.csv"), encoding: .utf8)
            .components(separatedBy: .newlines).filter { !$0.isEmpty }.dropFirst()

        var total = 0
        var unloadable = 0
        var digitRight = 0
        var agreeWithPython = 0
        var eight: PumpSegmentsModel.Read?
        for line in labels {
            let cols = line.split(separator: ",", omittingEmptySubsequences: false)
            guard cols.count >= 4 else { continue }
            let file = String(cols[0]); let digit = String(cols[1]); let pyDigit = String(cols[3])
            guard digit != "blank", digit != "none" else { continue }
            guard let image = PumpReaderTestSupport.loadRGB(url: Self.cellsDir.appendingPathComponent(file)) else {
                unloadable += 1
                continue
            }
            let read = try model.read(cell: image)
            total += 1
            if String(read.digit) == digit { digitRight += 1 }
            if String(read.digit) == pyDigit { agreeWithPython += 1 }
            if digit == "8", eight == nil { eight = read }
        }
        #expect(unloadable == 0, "\(unloadable) rendered cells could not be loaded")
        #expect(total >= 200, "rendered \(total) digit cells - a vacuous run")
        let accuracy = Double(digitRight) / Double(max(total, 1))
        let agreement = Double(agreeWithPython) / Double(max(total, 1))
        print("PumpSegmentsModel: \(digitRight)/\(total) digits right (\(accuracy)), agrees with Python on \(agreement)")
        // Oracle: the labels the renderer wrote. Synthetic validation is 0.98
        // per-digit in Python; the Core ML export must not lose that.
        #expect(accuracy >= 0.90)
        // Oracle: the Python model on the identical cells (same weights).
        #expect(agreement >= 0.97)
        let e = try #require(eight)
        #expect(e.probabilities.prefix(7).allSatisfy { $0 >= 0.5 }, "an 8 lights every segment: \(e.probabilities)")
    }

    /// The five test-time-augmentation crops of one real fixture cell, the
    /// input `PumpReader.averaged` sees for a glyph.
    private static func fixtureCrops() throws -> [PumpRGBImage] {
        let name = "pump-032-gilbarco-circlek-ee-clean.jpg"
        let url = PumpReaderTestSupport.pumpFixturesRoot.appendingPathComponent(name)
        let image = try #require(PumpReaderTestSupport.loadRGB(url: url))
        let data = try Data(contentsOf: PumpReaderTestSupport.windowsURL)
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let annotation = try #require(root[name] as? [String: Any])
        let windows = PumpReaderTestSupport.annotatedWindows(annotation, image: image)
        let window = try #require(windows.first)
        let strip = try #require(PumpQuadWarp.warpToStrip(
            rgb: image, quad: window.quad, stripHeight: PumpReader.stripHeight))
        let stripRGB = PumpQuadWarp.rgbImage(from: strip)
        let cells = PumpGlyphSlicer.slice(stripRGB.grayscale())
        let cell = try #require(cells.first { !$0.isBlank })
        return PumpReader.cropCell(stripRGB, rect: cell.rect)
    }

    /// M2: one batched prediction must equal the per-crop sequence, bitwise,
    /// and the average must sum in the crops' order. A different order or a
    /// dropped crop in the batched path fails this.
    @Test("batched prediction equals the sequential one, bitwise", .pumpFixturesPresent)
    func batchedEqualsSequential() throws {
        let model = try PumpSegmentsModel(contentsOf: Self.modelURL)
        let crops = try Self.fixtureCrops()
        #expect(crops.count == 5)
        let sequential = try crops.map { try model.probabilities(cell: $0) }
        let batched = try model.probabilities(cells: crops)
        #expect(batched.count == crops.count)
        for (b, s) in zip(batched, sequential) {
            #expect(zip(b, s).allSatisfy { $0.bitPattern == $1.bitPattern },
                    "batched differs from sequential: \(b) vs \(s)")
        }
        let averaged = try PumpReader.averaged(model: model, crops: crops)
        var sum = [Double](repeating: 0, count: 8)
        for p in sequential { for i in 0..<8 { sum[i] += p[i] } }
        let reference = sum.map { $0 / Double(crops.count) }
        #expect(zip(averaged, reference).allSatisfy { $0.bitPattern == $1.bitPattern },
                "batched average differs from the sequential order: \(averaged) vs \(reference)")
    }

    /// Renders labelled slicer-framed cells and the Python model's own read of each.
    private static func renderCells(count: Int, seed: Int) throws {
        try? FileManager.default.removeItem(at: cellsDir)
        try FileManager.default.createDirectory(at: cellsDir, withIntermediateDirectories: true)
        let script = """
        import csv, sys, numpy as np, torch
        from PIL import Image
        from pump_reader.dataset import SyntheticDataset, target_to_bits
        from pump_reader.glyph import SegmentLabel, decode_constrained
        from pump_reader.model import SegmentNet
        out = sys.argv[1]; n = int(sys.argv[2]); seed = int(sys.argv[3]); ckpt = sys.argv[4]
        ds = SyntheticDataset(seed=seed, length=n, cache=False)
        m = SegmentNet(); m.load_state_dict(torch.load(ckpt, map_location='cpu')['state_dict']); m.eval()
        with open(out + '/labels.csv', 'w', newline='') as f:
            w = csv.writer(f); w.writerow(['file', 'digit', 'bits', 'python_digit'])
            for i in range(n):
                arr, t = ds[i]
                img = Image.fromarray((arr.transpose(1, 2, 0) * 255).astype(np.uint8))
                name = f'{i:04d}.png'; img.save(out + '/' + name)
                bits = target_to_bits(t); digit = SegmentLabel(bits & 0x7F).digit or 'none'
                with torch.no_grad():
                    p = torch.sigmoid(m(torch.from_numpy(arr).unsqueeze(0)))[0].numpy()
                pd = SegmentLabel(decode_constrained(p, allow_blank=False)[0] & 0x7F).digit or 'none'
                w.writerow([name, digit, bits, pd])
        """
        let checkpoint = PumpReaderTestSupport.repoRoot
            .appendingPathComponent("ml/pump-reader/.out/current/segmentnet.pt")
        let process = Process()
        process.executableURL = python
        process.currentDirectoryURL = PumpReaderTestSupport.repoRoot.appendingPathComponent("ml/pump-reader")
        process.arguments = ["-c", script, cellsDir.path, String(count), String(seed), checkpoint.path]
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0, "the Python renderer exited \(process.terminationStatus)")
    }
}

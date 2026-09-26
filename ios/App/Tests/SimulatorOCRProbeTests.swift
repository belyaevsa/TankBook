import XCTest
import TankbookCore

/// The receipt parser over the receipt corpus on the SIMULATOR's Vision - the
/// iOS build of the recognizer, which the macOS package tests never run. It is
/// the nearest thing to a phone this machine has: the simulator runs Vision on
/// the CPU where a device may use the Neural Engine, so it is a proxy for the
/// device's reading, not the device. It mirrors RV.56 (a committed total the
/// corpus contradicts) and the litres counterpart, on the same extraction path
/// (`FuelExtractor` with the bundled band pack, receipt source, no fiscal QR).
///
/// Opt-in: `xcodebuild test ... -only-testing:TankbookTests/SimulatorOCRProbeTests`
/// with `TEST_RUNNER_SIM_OCR_PROBE=1` in the environment.
final class SimulatorOCRProbeTests: XCTestCase {
    private static let fixtures = URL(fileURLWithPath: #filePath).standardizedFileURL
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Spike/ReceiptSpike/fixtures/receipts")
    private static let languages = ["en-US", "de-DE", "pl-PL", "cs-CZ", "ru-RU"]
    private static let tolerance = 0.005

    func testReceiptTotalsAndVolumesAgainstTheCorpus() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SIM_OCR_PROBE"] == "1", "SIM_OCR_PROBE=1")
        let csv = try String(contentsOf: Self.fixtures.appendingPathComponent("expected.csv"), encoding: .utf8)
        var expected: [String: (liters: Double?, total: Double?)] = [:]
        for line in csv.split(separator: "\n").dropFirst() {
            let cols = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            guard cols.count >= 4 else { continue }
            expected[cols[0]] = (Double(cols[1]), Double(cols[3]))
        }
        let extractor = FuelExtractor(bandProvider: DefaultFuelPriceBandProvider(
            pack: try FuelPriceBandStore.bundledPack()))
        var wrongTotals: [String] = [], wrongLiters: [String] = []
        var totalsRight = 0, litersRight = 0, scored = 0
        for name in expected.keys.sorted() {
            let url = Self.fixtures.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            let lines = try await VisionTextRecognizer.recognizeText(in: url, languages: Self.languages)
            let result = extractor.extract(lines: lines, source: .receipt)
            scored += 1
            let want = expected[name]!
            if let wantTotal = want.total, let got = result.total.map({ NSDecimalNumber(decimal: $0).doubleValue }) {
                if abs(got - wantTotal) < Self.tolerance { totalsRight += 1 } else {
                    wrongTotals.append("\(name): got \(got), want \(wantTotal)")
                }
            }
            if let wantLiters = want.liters, let got = result.liters {
                if abs(got - wantLiters) < Self.tolerance { litersRight += 1 } else {
                    wrongLiters.append("\(name): got \(got) L, want \(wantLiters) L")
                }
            }
        }
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        print("SIM OCR PROBE (\(os)): \(scored) receipts; totals right \(totalsRight), wrong \(wrongTotals.count); "
              + "litres right \(litersRight), wrong \(wrongLiters.count)")
        for w in wrongTotals { print("  WRONG TOTAL \(w)") }
        for w in wrongLiters { print("  WRONG LITRES \(w)") }
        XCTAssertGreaterThan(scored, 50)
    }
}

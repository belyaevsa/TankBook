import Foundation
import Testing
@testable import TankbookCore

/// What a non-pump photo the display decision routes as a pump then COMMITS.
/// Routing alone is not the harm: a routed receipt the law closes on reaches
/// Confirm as a `.pumpPhoto` pre-fill with reader values. Each fixture is read
/// by the reader the app builds, in the four currencies that carry most of the
/// pump corpus's cells (EUR, RUB, KZT, GBP), because the phone's locale - not
/// the photo - picks the currency. Only
/// which fields committed is reported, never their values (hard rule 12).
@Suite("Pump reader on non-pump photos")
struct PumpLeakConsequenceTests {
    private static let modelURL = PumpReaderTestSupport.repoRoot
        .appendingPathComponent("ios/App/Resources/PumpSegments.mlpackage")
    private static let folders = ["receipts", "screenshots", "expenses", "fiscal"]
    private static let currencies = ["EUR", "RUB", "KZT", "GBP"]

    // Measured over the four folders (116 photos) with the detector present and
    // no slow-path cap - the phone's worst case: 6 routed, none committing a
    // field in any currency. Both move only downward: a change that routes or
    // commits on one more non-pump photo fails here and names it.
    private static let routedCeiling = 6
    private static let committingCeiling = 0

    // Opt-in: the uncapped verifier over 116 photos runs ~45 minutes in Debug.
    @Test("a non-pump photo routed as a pump commits nothing", .pumpFixturesPresent,
          .enabled(if: ProcessInfo.processInfo.environment["PUMP_LEAK"] == "1", "PUMP_LEAK=1"))
    func routedNonPumpPhotosCommitNothing() throws {
        let reader = try #require(PumpDisplayCapture.makeReader(
            modelURL: Self.modelURL, detectorURL: PumpReaderTestSupport.detectorURL,
            rowReaderURL: PumpReaderTestSupport.rowReaderURL))
        let pack = try FuelPriceBandStore.bundledPack()
        let root = PumpReaderTestSupport.repoRoot.appendingPathComponent("Spike/ReceiptSpike/fixtures")
        var total = 0
        var routed: [String] = []
        var committing: [String] = []
        for folder in Self.folders {
            let dir = root.appendingPathComponent(folder)
            let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
            for name in names.sorted() where ["jpg", "jpeg", "png", "heic"].contains(
                (name as NSString).pathExtension.lowercased()) {
                guard let image = PumpQuadWarp.loadOrientedImage(from: dir.appendingPathComponent(name)) else { continue }
                total += 1
                let decision = PumpDisplayCapture.classify(image: image, reader: reader, currency: nil,
                                                           priceBand: nil, budget: .infinity, rotationCW: 0)
                guard decision.detection.isPumpDisplay else { continue }
                routed.append("\(folder)/\(name)")
                for code in Self.currencies {
                    guard let currency = CurrencyCode(rawValue: code) else { continue }
                    let reading = PumpDisplayCapture.classify(
                        image: image, reader: reader, currency: currency,
                        priceBand: pack.currencyBand(currency: currency), budget: .infinity, rotationCW: 0)
                    let law = reading.reading?.law ?? .abstained
                    let named: [(String, PumpFieldReading)] = [("liters", law.liters), ("unitPrice", law.unitPrice),
                                                                ("total", law.total)]
                    let fields = named.filter { $0.1.value != nil }.map(\.0)
                    if !fields.isEmpty { committing.append("\(folder)/\(name) [\(code)] \(fields.joined(separator: ","))") }
                }
            }
        }
        print("Pump leak: \(routed.count) of \(total) non-pump photos routed as a pump; "
              + "\(committing.count) (photo, currency) reads commit a field")
        for name in routed { print("  ROUTED \(name)") }
        for line in committing { print("  COMMITS \(line)") }
        #expect(total > 0, "no non-pump fixtures found")
        #expect(routed.count <= Self.routedCeiling, "routed \(routed.count), ceiling \(Self.routedCeiling)")
        #expect(committing.count <= Self.committingCeiling,
                "\(committing.count) routed non-pump reads commit a field, ceiling \(Self.committingCeiling)")
    }
}

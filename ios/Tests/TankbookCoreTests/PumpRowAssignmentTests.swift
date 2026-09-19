import CoreGraphics
import Foundation
import Testing
@testable import TankbookCore

/// PU.23: roles from geometry alone, scored against the annotation's `field`
/// on every window of every fixture (empty-text windows included - in
/// production every window is present whether or not it is readable).
@Suite("PU.23 pump row assignment")
struct PumpRowAssignmentTests {

    // The floor moves only upward on the same corpus; a new hard fixture
    // re-measures it and names why. pump-121 / pump-122 are two lit price
    // cells side by side on a Wayne row with the transaction price on the
    // right (121) and on the left (122): geometry alone cannot tell them
    // apart, the law's board-as-price trial does, and the recorded rate is
    // what the geometry pass achieves on its own (docs/TASKS.md PU.23).
    private static let accuracyFloor = 0.975

    @Test("every fixture's windows get the roles the annotation gives them", .pumpFixturesPresent)
    func corpusAssignment() throws {
        let data = try Data(contentsOf: PumpReaderTestSupport.windowsURL)
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        var total = 0
        var right = 0
        var misses: [String] = []
        for (name, value) in root.sorted(by: { $0.key < $1.key }) {
            guard name != "_about", let ann = value as? [String: Any] else { continue }
            let rotation = (ann["rotationCW"] as? NSNumber)?.intValue ?? 0
            var windows: [PumpRowAssignment.Window] = []
            var truth: [PumpField] = []
            for raw in ann["windows"] as? [[String: Any]] ?? [] {
                guard let fieldName = raw["field"] as? String, let field = PumpField(rawValue: fieldName),
                      let quad = raw["quad"] as? [[Double]] else { continue }
                let text = raw["text"] as? String ?? ""
                // The image size only scales the quads; 1000 x 1000 keeps the geometry.
                windows.append(PumpRowAssignment.Window(
                    quad: PumpReaderTestSupport.quadPixels(quad, width: 1000, height: 1000),
                    glyphCount: text.filter(\.isNumber).count))
                truth.append(field)
            }
            let assigned = PumpRowAssignment.assign(windows: windows, rotationCW: rotation)
            // On a four-price board without a separate price window the
            // transaction price IS a board cell; geometry cannot single it out
            // and the arithmetic does (the law tries every board cell), so a
            // `.board` role on the annotated price is right here.
            let separatePrice = zip(assigned.roles, truth).contains { $0 == .unitPrice && $1 == .unitPrice }
            for (got, want) in zip(assigned.roles, truth) {
                total += 1
                if got == want || (want == .unitPrice && got == .board && !separatePrice) {
                    right += 1
                } else {
                    misses.append("\(name.prefix(8)) want \(want) got \(got.map(\.rawValue) ?? "nil")")
                }
            }
        }
        let accuracy = Double(right) / Double(max(total, 1))
        print("PU.23 row assignment: \(right)/\(total) (\(String(format: "%.3f", accuracy)))")
        for m in misses.prefix(30) { print("  MISS \(m)") }
        #expect(total > 400)
        #expect(accuracy >= Self.accuracyFloor)
    }

    @Test("pump-009's board of four never becomes the transaction price")
    func boardIsNotThePrice() {
        // Four equal windows in a column at the left (the board), and the
        // transaction column at the right - as pump-009 lays them out.
        func box(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> [CGPoint] {
            [CGPoint(x: x, y: y), CGPoint(x: x + w, y: y), CGPoint(x: x + w, y: y + h), CGPoint(x: x, y: y + h)]
        }
        let windows = [
            PumpRowAssignment.Window(quad: box(300, 200, 330, 125), glyphCount: 6),  // total
            PumpRowAssignment.Window(quad: box(330, 335, 255, 90), glyphCount: 6),   // liters
            PumpRowAssignment.Window(quad: box(380, 600, 140, 70), glyphCount: 5),   // price
            PumpRowAssignment.Window(quad: box(140, 210, 75, 55), glyphCount: 5),    // board row (vertical column on this head)
            PumpRowAssignment.Window(quad: box(135, 345, 75, 55), glyphCount: 5),
            PumpRowAssignment.Window(quad: box(125, 480, 80, 55), glyphCount: 5),
            PumpRowAssignment.Window(quad: box(115, 615, 80, 65), glyphCount: 5),
        ]
        let roles = PumpRowAssignment.assign(windows: windows, rotationCW: 0).roles
        #expect(roles[0] == .total && roles[1] == .liters && roles[2] == .unitPrice)
    }

    @Test("a liters or total window with fewer cells than its decimals allow is implausible")
    func minimumCells() {
        #expect(!PumpRowAssignment.plausibleCount(2, for: .liters))
        #expect(PumpRowAssignment.plausibleCount(3, for: .liters))
        #expect(!PumpRowAssignment.plausibleCount(2, for: .total))
    }
}

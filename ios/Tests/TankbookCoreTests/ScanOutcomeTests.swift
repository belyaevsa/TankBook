import Foundation
import Testing
@testable import TankbookCore

/// The beta's scan outcome (`ScanOutcome`): where each pump field's pre-fill
/// came from, what the user did with it, and that the outcome is kept beside
/// the scan and sent with it in a debug case.
@Suite("Scan outcome")
struct ScanOutcomeTests {
    private func extraction(_ liters: Double?, _ price: String?, _ total: String?) -> FuelExtraction {
        var read = FuelExtraction()
        read.liters = liters
        read.unitPrice = price.flatMap { Decimal(string: $0) }
        read.total = total.flatMap { Decimal(string: $0) }
        return read
    }

    @Test("a closed read is closed; the rules arm's fill is rules; nothing is empty")
    func closedAndRules() {
        let reader = extraction(20.17, nil, "41.23")
        let rules = extraction(nil, "2.044", nil)
        let form = extraction(20.17, "2.044", "41.23")
        let kinds = ScanOutcome.prefillKinds(reader: reader, rules: rules, form: form, caution: nil)
        #expect(kinds == ["liters": .closed, "unitPrice": .rules, "total": .closed])
        let empty = ScanOutcome.prefillKinds(reader: nil, rules: FuelExtraction(), form: FuelExtraction(),
                                             caution: nil)
        #expect(Set(empty.values) == [.empty])
    }

    @Test("an unclosed read's fields are warned unless the rules arm filled them")
    func warned() {
        let reader = extraction(1.849, nil, "26.5")
        let rules = extraction(nil, nil, "51.65")
        let form = extraction(1.849, nil, "51.65")
        let kinds = ScanOutcome.prefillKinds(reader: reader, rules: rules, form: form, caution: .unclosed)
        #expect(kinds == ["liters": .warned, "unitPrice": .empty, "total": .rules])
    }

    @Test("a shown-price caution marks the reader's fields cautioned")
    func cautioned() {
        let reader = extraction(7.17, nil, "13.19")
        let kinds = ScanOutcome.prefillKinds(
            reader: reader, rules: FuelExtraction(), form: reader,
            caution: .shownPriceDiffers(shown: Decimal(string: "1.834")!, implied: Decimal(string: "1.840")!))
        #expect(kinds == ["liters": .cautioned, "unitPrice": .empty, "total": .cautioned])
    }

    @Test("kept, edited, cleared, added and untouched")
    func actions() {
        #expect(ScanOutcome.action(prefilled: 20.17, saved: 20.17) == .kept)
        #expect(ScanOutcome.action(prefilled: 20.17, saved: 20.172) == .kept)
        #expect(ScanOutcome.action(prefilled: 1.849, saved: 26.5) == .edited)
        #expect(ScanOutcome.action(prefilled: 1.849, saved: nil) == .cleared)
        #expect(ScanOutcome.action(prefilled: nil, saved: 2.044) == .added)
        #expect(ScanOutcome.action(prefilled: nil, saved: nil) == .untouched)
    }

    @Test("the outcome records each field's kind and, for a save, its action")
    func outcomeBody() throws {
        let kinds: [String: ScanPrefillKind] = ["liters": .warned, "unitPrice": .empty, "total": .closed]
        let saved = ScanOutcome.data(result: .saved, at: Date(timeIntervalSince1970: 0), kinds: kinds,
                                     prefilled: extraction(1.849, nil, "51.65"),
                                     saved: ScanSavedValues(liters: 26.5, unitPrice: Decimal(string: "1.949"),
                                                            total: Decimal(string: "51.65")))
        let body = try #require(JSONSerialization.jsonObject(with: saved) as? [String: Any])
        let fields = try #require(body["fields"] as? [String: [String: String]])
        #expect(body["result"] as? String == "saved")
        #expect(fields["liters"] == ["prefill": "warned", "action": "edited"])
        #expect(fields["unitPrice"] == ["prefill": "empty", "action": "added"])
        #expect(fields["total"] == ["prefill": "closed", "action": "kept"])
        let discarded = ScanOutcome.data(result: .discarded, at: Date(), kinds: kinds,
                                         prefilled: FuelExtraction(), saved: nil)
        let discardedFields = try #require(
            (JSONSerialization.jsonObject(with: discarded) as? [String: Any])?["fields"] as? [String: [String: String]])
        #expect(discardedFields["liters"] == ["prefill": "warned"])
    }

    @Test("the outcome is kept in the scan's folder and travels in a debug case")
    func keptAndSent() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("scan-outcome-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let history = ScanHistory(directory: root)
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        let folder = history.folder(at: date, id: "abcdef1234")
        history.record(photo: Data([0xFF, 0xD8]), record: Data("{}".utf8), trace: nil, at: date, id: "abcdef1234")
        history.recordOutcome(Data("{\"result\":\"saved\"}".utf8), in: folder)
        let entry = try #require(history.recent().first)
        #expect(entry.folder.standardizedFileURL == folder.standardizedFileURL)
        #expect(entry.files.contains(ScanHistory.outcomeFile))
        let parts = DebugCase.parts(log: "", scans: [entry], app: "test", build: nil)
        #expect(parts.contains { $0.name == "scan-1-outcome.json" && $0.contentType == "application/json" })
    }
}

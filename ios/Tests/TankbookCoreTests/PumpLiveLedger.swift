import Foundation
@testable import TankbookCore

/// The live arm's per-photo record (`docs/TESTING.md`, `ml/pump-reader/REPORT.md` -> round protocol).
/// The live gate is one number, so a change that swaps five gains for five
/// losses reads as "no change"; the ledger keeps, per still, what each field
/// committed, whether it was right, and why it abstained, so
/// `scripts/pump-live-diff.py` can say which stills flipped and to which reason.
struct PumpLiveLedger: Codable {
    struct Field: Codable, Equatable {
        /// `right`, `wrong`, `abstained`, or `unscored` (the CSV asserts nothing
        /// for the field, or the annotation marks it `csvDisagrees`).
        var outcome: String
        var got: Double?
        var want: Double?
        /// The law's reason when the field abstained.
        var reason: String?
        /// The unclosed top read the form got under the warning, if any.
        var warned: Double?
    }

    struct Still: Codable, Equatable {
        var name: String
        var head: String
        var split: String?
        /// The whole reading's refusal reason when nothing committed.
        var reason: String?
        /// The caution the reading carried, by case name.
        var caution: String?
        var fields: [String: Field]
    }

    struct Totals: Codable, Equatable {
        var numericTotal: Int
        var committed: Int
        var committedCorrect: Int
    }

    var about = "One row per scored still of the live arm; scripts/pump-live-diff.py diffs two."
    var detector: String?
    var totals: Totals
    var stills: [Still]

    /// The totals the rows themselves add up to - the check that the ledger
    /// describes the same run the suite printed.
    var recount: Totals {
        let fields = stills.flatMap(\.fields.values)
        return Totals(numericTotal: fields.filter { $0.outcome != "unscored" }.count,
                      committed: fields.filter { $0.outcome == "right" || $0.outcome == "wrong" }.count,
                      committedCorrect: fields.filter { $0.outcome == "right" }.count)
    }

    /// `PUMP_LIVE_LEDGER` or `ios/.build/pump-reader-out/live-ledger.json`.
    static var outputURL: URL {
        if let path = ProcessInfo.processInfo.environment["PUMP_LIVE_LEDGER"], !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        return PumpReaderTestSupport.outRoot.appendingPathComponent("live-ledger.json")
    }

    func write(to url: URL = Self.outputURL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url)
    }

    static func cautionName(_ caution: PumpReadingCaution?) -> String? {
        switch caution {
        case .none: return nil
        case .shownPriceDiffers: return "shownPriceDiffers"
        case .unclosed: return "unclosed"
        }
    }
}

import Foundation
import os
import TankbookCore

/// RV.88's UI-test/screenshot seam (`-stubRatesEcho`): answers `/rates/pack`
/// with a EUR->USD and EUR->PLN row for EVERY date in the requested `from..to`
/// span, so an import dated outside the fixed `-stubRates` pack window (e.g. the
/// current month) can be drained end to end without a live feed. Deterministic
/// fixed rates; the response is capped to the same 400-day window the store asks
/// in, mirroring the server's `Rates:MaxPackDays`. Stateless; any other path is
/// a 404 (a miss, never an error - F9).
#if DEBUG
struct RateEchoStubTransport: TankbookHTTPTransport {
    func execute(_ request: TankbookHTTPRequest) async throws -> TankbookHTTPResponse {
        guard request.url.path.hasPrefix("/v1/rates/pack"),
              let components = URLComponents(url: request.url, resolvingAgainstBaseURL: false),
              let fromItem = components.queryItems?.first(where: { $0.name == "from" }),
              let toItem = components.queryItems?.first(where: { $0.name == "to" }),
              let from = Self.day(fromItem.value),
              let to = Self.day(toItem.value),
              to >= from else {
            return TankbookHTTPResponse(status: 404)
        }
        var rows: [String] = []
        var cursor = from
        let calendar = Calendar(identifier: .gregorian)
        while cursor <= to, rows.count < 800 {
            let date = Self.dayString(cursor)
            rows.append("{\"date\":\"\(date)\",\"quote\":\"USD\",\"rate\":1.10,\"source\":\"ecb\"}")
            rows.append("{\"date\":\"\(date)\",\"quote\":\"PLN\",\"rate\":4.2706,\"source\":\"ecb\"}")
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        let body = "{\"base\":\"EUR\",\"rates\":[\(rows.joined(separator: ","))]}"
        return TankbookHTTPResponse(status: 200, body: Data(body.utf8))
    }

    static func day(_ iso: String?) -> Date? {
        guard let iso else { return nil }
        let parts = iso.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]) else {
            return nil
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: DateComponents(year: year, month: month, day: day))
    }

    static func dayString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

/// RV.106's UI-test seam (`-stubRatesMissThenHit`): the FIRST `/rates/pack`
/// request answers an EMPTY pack (the server has not yet published those
/// dates - the owner's state at import time, 05:10-05:17 while the archive
/// backfill was still running) and every LATER request answers the echo pack
/// (the server has since published them). A launch therefore renders the
/// pending state deterministically, and a user tap on the F9 footnote's
/// "Check for rates" - or a second launch - gets the second request and the
/// S8 backfill fills the rows: the owner's exact "it resolves once the
/// archive reaches those dates" sequence, testable offline.
final class MissThenHitRateStubTransport: TankbookHTTPTransport, @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: 0)

    func execute(_ request: TankbookHTTPRequest) async throws -> TankbookHTTPResponse {
        guard request.url.path.hasPrefix("/v1/rates/pack") else {
            return TankbookHTTPResponse(status: 404)
        }
        let attempt = lock.withLock { state -> Int in
            state += 1
            return state
        }
        guard attempt > 1 else {
            return TankbookHTTPResponse(status: 200, body: Data("{\"base\":\"EUR\",\"rates\":[]}".utf8))
        }
        return try await RateEchoStubTransport().execute(request)
    }
}

/// RV.132's UI-test seam (`-stubRatesSlowEcho`): the echo pack, DELAYED by a
/// fixed beat, so a footnote tap's immediate "Checking for rates…"
/// acknowledgement is observable while the demand is still on the wire - the
/// acknowledgement-before-the-network-resolves test (a response that lands
/// before the busy state renders cannot prove the ordering). Echo rather than
/// empty, so the demand also completes: the rows fill and the outcome toast
/// lands, which the same test asserts afterwards.
final class SlowEchoRateStubTransport: TankbookHTTPTransport, @unchecked Sendable {
    private static let delayNanoseconds: UInt64 = 2_500_000_000

    func execute(_ request: TankbookHTTPRequest) async throws -> TankbookHTTPResponse {
        guard request.url.path.hasPrefix("/v1/rates/pack") else {
            return TankbookHTTPResponse(status: 404)
        }
        try? await Task.sleep(nanoseconds: Self.delayNanoseconds)
        return try await RateEchoStubTransport().execute(request)
    }
}
#endif

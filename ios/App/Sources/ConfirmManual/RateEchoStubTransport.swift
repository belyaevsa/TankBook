import Foundation
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
#endif

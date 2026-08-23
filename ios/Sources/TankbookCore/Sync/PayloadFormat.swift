import Foundation

/// Shared formatting rules for the payload contract (docs/SYNC.md -> Payload
/// contract and versioning, docs/SCHEMA.md -> Payload schemas):
///
/// - Dates are ISO-8601 UTC strings (fractional seconds kept, so the LWW
///   `updatedAt` timestamp never loses precision).
/// - Decimals are JSON strings, never numbers - exactness matters for money
///   (docs/SCHEMA.md, Money). Swift's `Decimal` prints without trailing zeros
///   ("289.50" -> "289.5"); the *value* round-trips exactly, which is what the
///   contract requires (the fixture may carry either spelling).
///
/// Formatters are created per call: `ISO8601DateFormatter` is not Sendable, and
/// the module is used from parallel swift-testing tests.
internal enum PayloadFormat {

    /// ISO-8601 UTC with fractional seconds ("2026-08-22T12:10:00.000Z").
    static func dateString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    /// Parses both fractional and whole-second ISO-8601 UTC strings.
    static func date(from string: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: string) { return date }
        let whole = ISO8601DateFormatter()
        whole.formatOptions = [.withInternetDateTime]
        return whole.date(from: string)
    }

    /// A Decimal as a JSON string token ("1.679", "289.5"). The value round-trips
    /// exactly through `decimal(from:)`.
    static func decimalString(_ value: Decimal) -> String {
        var copy = value
        return NSDecimalString(&copy, Locale(identifier: "en_US_POSIX"))
    }

    /// Parses a decimal string. Returns nil on malformed input.
    static func decimal(from string: String) -> Decimal? {
        Decimal(string: string, locale: Locale(identifier: "en_US_POSIX"))
    }
}

import Foundation

// The per-car CSV export (PJ.38, docs/SCHEMA.md -> "Export formats"). One file
// per entry type - fill-ups, charge sessions, service, expenses - with flat
// rows named after SCHEMA.md's canonical field names, the original + home money
// PAIR (hard rule 3 - money is a pair, never one number), ISO-8601 dates in
// UTC, and tombstoned rows INCLUDED (a row whose `deletedAt` is non-empty is
// a tombstone still inside the 30-day undo window - an export that silently
// drops it loses data the user still owns, hard rule 8).
//
// The bytes are deterministic (the golden-fixture test pins them): column order
// is fixed, dates are UTC, decimals print through `PayloadFormat` (POSIX, no
// trailing zeros), and rows are date-ordered exactly as the repository returns
// them. A column rename or a date-format change is therefore a visible diff.

public enum CarCSVExport {
    /// The four per-type file names (one file per entry type).
    public static let fillUpsFile = "fill-ups.csv"
    public static let chargeSessionsFile = "charge-sessions.csv"
    public static let serviceFile = "service.csv"
    public static let expensesFile = "expenses.csv"

    public static let fileNames = [
        fillUpsFile, chargeSessionsFile, serviceFile, expensesFile
    ]

    // The shared envelope columns, in fixed order. Field names are SCHEMA.md's
    // exactly (`amount`/`currency`/`homeAmount`/`homeCurrency`/`rate`/`rateDate`
    // are the flattened `money` pair with its rate snapshot).
    static let commonColumns = [
        "id", "vehicleId", "date", "odometer",
        "amount", "currency", "homeAmount", "homeCurrency", "rate", "rateDate",
        "deletedAt", "note"
    ]

    /// Renders the four CSV files for `vehicleID` as `[fileName: contents]`,
    /// tombstones included. Deterministic and locale-independent.
    public static func render(vehicleID: UUID, repository: TankbookRepository) throws -> [String: String] {
        let fills = try repository.fillUpsIncludingDeleted(forVehicle: vehicleID)
        let charges = try repository.chargeSessionsIncludingDeleted(forVehicle: vehicleID)
        let services = try repository.serviceRecordsIncludingDeleted(forVehicle: vehicleID)
        let expenses = try repository.expensesIncludingDeleted(forVehicle: vehicleID)

        return [
            fillUpsFile: renderFillUps(fills),
            chargeSessionsFile: renderChargeSessions(charges),
            serviceFile: renderServiceRecords(services),
            expensesFile: renderExpenses(expenses)
        ]
    }

    /// Writes the four CSVs into `directory`, returning the written URLs. The
    /// per-car export places them INSIDE the archive directory so the share
    /// sheet carries both (docs/SCHEMA.md -> Backup format).
    @discardableResult
    public static func write(into directory: URL, vehicleID: UUID,
                             repository: TankbookRepository) throws -> [URL] {
        let files = try render(vehicleID: vehicleID, repository: repository)
        return try fileNames.compactMap { name in
            guard let contents = files[name] else { return nil }
            let url = directory.appendingPathComponent(name)
            try ArchiveFileIO.atomicWrite(Data(contents.utf8), to: url)
            return url
        }
    }

    // MARK: - Per-type rendering

    private static func renderFillUps(_ fills: [FillUp]) -> String {
        var lines = [csvLine(commonColumns + ["volumeL", "unitPrice", "fuelKind",
                                              "fuelGrade", "isFull", "tankLevelAfterPct",
                                              "stationId", "crossCheck"])]
        for fill in fills {
            lines.append(csvLine(common(fill)
                + [doubleString(fill.volumeL),
                   decimalString(fill.unitPrice),
                   fill.fuelKind.rawValue,
                   fill.fuelGrade ?? "",
                   fill.isFull ? "true" : "false",
                   optionalDouble(fill.tankLevelAfterPct),
                   uuidString(fill.stationId),
                   crossCheckString(fill.crossCheck)]))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func renderChargeSessions(_ charges: [ChargeSession]) -> String {
        var lines = [csvLine(commonColumns + ["energyKWh", "unitPrice", "chargeType",
                                              "provider", "tariffId", "durationMin",
                                              "socStartPct", "socEndPct"])]
        for charge in charges {
            lines.append(csvLine(common(charge)
                + [doubleString(charge.energyKWh),
                   decimalString(charge.unitPrice),
                   charge.chargeType.rawValue,
                   charge.provider ?? "",
                   uuidString(charge.tariffId),
                   optionalInt(charge.durationMin),
                   optionalDouble(charge.socStartPct),
                   optionalDouble(charge.socEndPct)]))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func renderServiceRecords(_ services: [ServiceRecord]) -> String {
        var lines = [csvLine(commonColumns + ["vendor"])]
        for service in services {
            lines.append(csvLine(common(service) + [service.vendor ?? ""]))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func renderExpenses(_ expenses: [Expense]) -> String {
        var lines = [csvLine(commonColumns + ["category", "title"])]
        for expense in expenses {
            lines.append(csvLine(common(expense)
                + [expenseCategoryString(expense.category), expense.title]))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - Field rendering

    private static func common(_ entry: any Entry) -> [String] {
        [uuidString(entry.id),
         uuidString(entry.vehicleId),
         isoDate(entry.date),
         optionalInt(entry.odometer)]
            + moneyFields(entry.money)
            + [isoDate(entry.deletedAt), entry.note ?? ""]
    }

    private static func moneyFields(_ money: Money?) -> [String] {
        guard let money else {
            return ["", "", "", "", "", ""]
        }
        // Amounts render with the currency's minor units (289.50, never 289.5):
        // a CSV of money is read by humans. The RATE keeps its full precision -
        // 4.2706 must not be rounded to the currency's minor units.
        return [moneyString(money.amount, currency: money.currency),
                money.currency.rawValue,
                money.homeAmount.map { moneyString($0, currency: money.homeCurrency) } ?? "",
                money.homeCurrency.rawValue,
                money.rate.map(PayloadFormat.decimalString) ?? "",
                money.rateDate.map(isoDate) ?? ""]
    }

    /// A Decimal rendered with exactly the currency's minor-unit digits,
    /// locale-independent (POSIX, no grouping).
    private static func moneyString(_ value: Decimal, currency: CurrencyCode) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = currency.minorUnits
        formatter.maximumFractionDigits = currency.minorUnits
        return formatter.string(from: value as NSDecimalNumber) ?? PayloadFormat.decimalString(value)
    }

    private static func crossCheckString(_ state: CrossCheckState) -> String {
        switch state {
        case .verified: "verified"
        case .notApplicable: "notApplicable"
        case .mismatch: "mismatch"
        }
    }

    private static func expenseCategoryString(_ category: ExpenseCategory) -> String {
        switch category {
        case .insurance: "insurance"
        case .tax: "tax"
        case .parking: "parking"
        case .toll: "toll"
        case .fine: "fine"
        case .accessory: "accessory"
        case .parts: "parts"
        case .other(let value): "other:\(value)"
        }
    }

    private static func uuidString(_ id: UUID?) -> String {
        id.map { $0.uuidString.lowercased() } ?? ""
    }

    private static func optionalInt(_ value: Int?) -> String {
        value.map(String.init) ?? ""
    }

    private static func optionalDouble(_ value: Double?) -> String {
        value.map(doubleString) ?? ""
    }

    private static func doubleString(_ value: Double) -> String {
        String(value)
    }

    private static func decimalString(_ value: Decimal?) -> String {
        value.map(PayloadFormat.decimalString) ?? ""
    }

    /// ISO-8601 date in UTC ("2026-08-22"), matching the archive's UTC
    /// convention so an export never depends on the device's timezone.
    private static func isoDate(_ date: Date?) -> String {
        guard let date else { return "" }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        formatter.timeZone = TimeZone(identifier: "UTC") ?? .current
        return formatter.string(from: date)
    }

    // MARK: - RFC 4180 quoting

    private static func csvField(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }

    private static func csvLine(_ fields: [String]) -> String {
        fields.map(csvField).joined(separator: ",")
    }

    // MARK: - Test helpers (parsing a rendered CSV back)

    /// The number of data rows in a rendered CSV (the header excluded) - the
    /// per-type live + tombstoned count assertion's helper.
    static func rowCount(of csv: String) -> Int {
        max(0, parseRecords(csv).count - 1)
    }

    /// Parses a rendered CSV into `(header: [field name: index], rows: [[field
    /// name: value]])` so a test can read a specific cell by SCHEMA.md field
    /// name. Handles RFC 4180 quoting (the comma in a quoted note survives).
    static func dataRows(_ csv: String) -> (header: [String: Int], rows: [[String: String]]) {
        let records = parseRecords(csv)
        guard let headerRecord = records.first else { return ([:], []) }
        var header: [String: Int] = [:]
        for (index, field) in headerRecord.enumerated() {
            header[field] = index
        }
        let rows = records.dropFirst().map { record in
            var row: [String: String] = [:]
            for (name, index) in header {
                row[name] = index < record.count ? record[index] : ""
            }
            return row
        }
        return (header, rows)
    }

    /// A minimal RFC 4180 record parser (quoted fields, doubled quotes, CRLF).
    private static func parseRecords(_ csv: String) -> [[String]] {
        var records: [[String]] = []
        var record: [String] = []
        var field = ""
        var inQuotes = false
        let chars = Array(csv)
        var index = 0
        while index < chars.count {
            let char = chars[index]
            if inQuotes {
                if char == "\"" {
                    if index + 1 < chars.count, chars[index + 1] == "\"" {
                        field.append("\"")
                        index += 2
                        continue
                    }
                    inQuotes = false
                    index += 1
                    continue
                }
                field.append(char)
                index += 1
                continue
            }
            switch char {
            case "\"":
                inQuotes = true
                index += 1
            case ",":
                record.append(field)
                field = ""
                index += 1
            case "\n":
                record.append(field)
                records.append(record)
                record = []
                field = ""
                index += 1
            case "\r":
                index += 1
            default:
                field.append(char)
                index += 1
            }
        }
        if !field.isEmpty || !record.isEmpty {
            record.append(field)
            records.append(record)
        }
        return records
    }
}

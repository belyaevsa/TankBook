using System.Globalization;
using System.Text;
using System.Text.Json.Nodes;
using Microsoft.VisualBasic.FileIO;

namespace Tankbook.Api.Import;

/// <summary>
/// The My Fuel Manager parser (docs/SCHEMA.md "Import mapping", the real export
/// at Spike/ImportFixtures/mfm/). Five properties of this format break a
/// first-attempt reader, and the tests pin each one:
///   1. the header is on line 2 - line 1 is a title ("My Fuel Manager - Fuel");
///   2. the delimiter is ';', not ',';
///   3. dates are M/D/YYYY and ambiguous against D/M/YYYY for any day &lt;= 12 -
///      the ambiguity is returned in <see cref="ImportAmbiguity"/>, never resolved;
///   4. there is no unit-price column - price/L is derived (total / volume);
///   5. Fuel is a numeric code (a bitmask: 1 = petrol, 2 = diesel), not a name.
///
/// The parser is a pure function: it returns candidate proposals and commits
/// nothing (hard rule 9). A row that cannot be mapped lands in
/// <c>Unparsed</c> with a stable reason and the rest keep parsing (F6, hard
/// rule 8). A file that does not look like an MFM export throws
/// <see cref="NotMfmExportException"/> (the 422 path).
/// </summary>
public static class MfmParser
{
    public const string TitlePrefix = "My Fuel Manager - ";

    // The title suffix names the file kind; incomes and costs share a header, so
    // the title is the only thing that tells them apart.
    private static readonly Dictionary<string, string> KindByTitle = new(StringComparer.OrdinalIgnoreCase)
    {
        ["Fuel"] = "fuel",
        ["Vehicles"] = "vehicles",
        ["COSTS"] = "costs",
        ["INCOMES"] = "incomes",
        ["Reminder"] = "reminders",
    };

    // Column counts per kind, checked against the header on line 2.
    private static readonly Dictionary<string, int> ColumnsByKind = new(StringComparer.OrdinalIgnoreCase)
    {
        ["fuel"] = 10,
        ["vehicles"] = 11,
        ["costs"] = 7,
        ["incomes"] = 7,
        ["reminders"] = 5,
    };

    // Reason codes carried in unparsed (stable; the client renders these).
    public const string ReasonWrongColumnCount = "wrong_column_count";
    public const string ReasonInvalidDate = "invalid_date";
    public const string ReasonInvalidNumber = "invalid_number";
    public const string ReasonMissingRequired = "missing_required";
    public const string ReasonUnknownFuelCode = "unknown_fuel_code";
    public const string ReasonUnknownFinanceCategory = "unknown_finance_category";

    /// <summary>The provenance every imported candidate carries (docs/SCHEMA.md import rules).</summary>
    public static readonly JsonObject ImportProvenance = new()
    {
        ["tag"] = "import",
        ["source"] = "mfm",
    };

    public static MfmParseResult Parse(Stream csv, CancellationToken cancellationToken)
    {
        var parser = new TextFieldParser(csv, Encoding.UTF8, detectEncoding: true)
        {
            Delimiters = [";"],
            HasFieldsEnclosedInQuotes = true,
            TextFieldType = FieldType.Delimited,
            TrimWhiteSpace = false,
        };
        try
        {
            return ParseCore(parser, cancellationToken);
        }
        finally
        {
            parser.Close();
        }
    }

    private static MfmParseResult ParseCore(TextFieldParser parser, CancellationToken cancellationToken)
    {
        // Line 1: the title. This is the "does this look like the declared
        // format" check (docs/API.md: 422). A standard CSV reader would take it
        // as the header and produce one column.
        var title = ReadRow(parser)?.FirstOrDefault()?.Trim();
        if (string.IsNullOrEmpty(title))
        {
            throw new NotMfmExportException("The file has no first line; a My Fuel Manager export begins with a title line.");
        }

        if (!title.StartsWith(TitlePrefix, StringComparison.OrdinalIgnoreCase))
        {
            throw new NotMfmExportException($"The first line is not a My Fuel Manager export title (expected '{TitlePrefix}...').");
        }

        var kindToken = title[TitlePrefix.Length..].Trim();
        if (!KindByTitle.TryGetValue(kindToken, out var fileKind))
        {
            throw new NotMfmExportException($"The title names an unknown My Fuel Manager file type ('{kindToken}').");
        }

        // Line 2: the header. It confirms the kind and fixes the column count.
        var header = ReadRow(parser);
        if (header is null || header.Length != ColumnsByKind[fileKind])
        {
            throw new NotMfmExportException(
                $"The header on line 2 does not match a {kindToken} export ({ColumnsByKind[fileKind]} columns expected).");
        }

        var rowNumber = 0;
        var candidates = new List<JsonObject>();
        var unparsed = new List<UnparsedRow>();
        int ambiguousDates = 0;
        int rowsWithCurrency = 0;
        string? currency = null;

        string[]? fields;
        while ((fields = ReadRow(parser)) is not null)
        {
            cancellationToken.ThrowIfCancellationRequested();
            fields = fields.Select(f => f.Trim()).ToArray();

            // A fully empty trailing line is not a data row.
            if (fields.Length == 0 || fields.All(string.IsNullOrEmpty))
            {
                continue;
            }

            rowNumber++;
            if (fields.Length != ColumnsByKind[fileKind])
            {
                unparsed.Add(new UnparsedRow(rowNumber, ReasonWrongColumnCount));
                continue;
            }

            try
            {
                var candidate = MapRow(fileKind, fields, ref ambiguousDates, ref rowsWithCurrency, ref currency, rowNumber);
                if (candidate is not null)
                {
                    candidates.Add(candidate);
                }
            }
            catch (NotMfmExportException)
            {
                throw;
            }
            catch (RowParseException ex)
            {
                unparsed.Add(new UnparsedRow(rowNumber, ex.Reason));
            }
        }

        var ambiguities = new List<ImportAmbiguity>();
        if (ambiguousDates > 0)
        {
            ambiguities.Add(new ImportAmbiguity(
                "dateFormat",
                ["M/D/YYYY", "D/M/YYYY"],
                ambiguousDates));
        }

        if (rowsWithCurrency > 0 && currency is not null)
        {
            // The currency column reads the same on every row - a default the
            // user must be able to correct, never a fact (hard rule 13, F6).
            ambiguities.Add(new ImportAmbiguity("currency", [currency], rowsWithCurrency));
        }

        if (fileKind is "incomes")
        {
            // Income is out of scope in v1 (docs/SCHEMA.md import mapping): the
            // rows are deliberately unmapped, not unparseable.
            ambiguities.Add(new ImportAmbiguity("outOfScope", ["income"], rowNumber));
        }
        else if (fileKind is "reminders")
        {
            ambiguities.Add(new ImportAmbiguity("outOfScope", ["reminder"], rowNumber));
        }

        return new MfmParseResult
        {
            FileKind = fileKind,
            Candidates = candidates,
            Unparsed = unparsed,
            Ambiguities = ambiguities,
            DataRowCount = rowNumber,
        };
    }

    private static string[]? ReadRow(TextFieldParser parser) => parser.EndOfData ? null : parser.ReadFields();

    /// <summary>Maps one data row to a candidate, or null for deliberately unmapped kinds (incomes/reminders).</summary>
    private static JsonObject? MapRow(
        string fileKind,
        string[] f,
        ref int ambiguousDates,
        ref int rowsWithCurrency,
        ref string? currency,
        int rowNumber)
    {
        switch (fileKind)
        {
            case "fuel":
                return MapFuelRow(f, ref ambiguousDates, ref rowsWithCurrency, ref currency, rowNumber);
            case "vehicles":
                return MapVehicleRow(f, rowNumber);
            case "costs":
                return MapCostsRow(f, ref ambiguousDates, ref rowsWithCurrency, ref currency, rowNumber);
            case "incomes":
            case "reminders":
                return null;
            default:
                throw new InvalidOperationException($"Unhandled MFM file kind '{fileKind}'.");
        }
    }

    private static JsonObject MapFuelRow(
        string[] f,
        ref int ambiguousDates,
        ref int rowsWithCurrency,
        ref string? currency,
        int rowNumber)
    {
        // Columns: Date; Fillup volume; Odometer; Total price; Currency; Fuel;
        //          Tank status after fillup; %; Note; Vehicle name
        var date = ParseDate(f[0], ref ambiguousDates);
        var volume = ParseDouble(f[1], ReasonInvalidNumber);
        var odometer = ParseOdometer(f[2]);
        var totalPrice = ParseDecimal(f[3], ReasonInvalidNumber);
        var rowCurrency = f[4];
        var fuelCode = ParseInt(f[5], ReasonInvalidNumber);
        var tankStatus = f[6];
        var tankLevelPct = ParseDouble(f[7], ReasonInvalidNumber);
        var note = string.IsNullOrEmpty(f[8]) ? null : f[8];
        var vehicleName = f[9];

        CountCurrency(rowCurrency, ref rowsWithCurrency, ref currency);

        if (string.IsNullOrEmpty(rowCurrency))
        {
            throw new RowParseException(ReasonMissingRequired);
        }

        // Fuel is a numeric code (bitmask: 1 = petrol, 2 = diesel). The petrol
        // octane is not in the file, so it becomes a petrol95 default the user
        // corrects (hard rule 13) - never a string comparison against a name.
        var fuelKind = fuelCode switch
        {
            1 => "petrol95",
            2 => "diesel",
            _ => throw new RowParseException(ReasonUnknownFuelCode),
        };

        // No unit-price column in this format: price per litre is derived
        // (total / volume), the confidence-checkable figure the preview shows.
        var unitPrice = volume > 0
            ? Math.Round(totalPrice / (decimal)volume, 6, MidpointRounding.AwayFromZero)
            : (decimal?)null;

        var isFull = tankStatus == "F";
        var isPartial = tankStatus == "P";
        if (!isFull && !isPartial)
        {
            throw new RowParseException("unknown_tank_status");
        }

        var money = new JsonObject
        {
            ["amount"] = totalPrice.ToString(CultureInfo.InvariantCulture),
            ["currency"] = rowCurrency,
        };

        return new JsonObject
        {
            ["entityType"] = "fillUp",
            ["date"] = date.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", CultureInfo.InvariantCulture),
            ["odometer"] = odometer,
            ["volumeL"] = volume,
            ["unitPrice"] = unitPrice?.ToString(CultureInfo.InvariantCulture),
            ["money"] = money,
            ["fuelKind"] = fuelKind,
            ["isFull"] = isFull,
            ["tankLevelAfterPct"] = tankLevelPct,
            ["note"] = note,
            ["vehicleName"] = vehicleName,
            ["provenance"] = (JsonNode)ImportProvenance.DeepClone(),
            ["sourceRow"] = rowNumber,
        };
    }

    private static JsonObject MapVehicleRow(string[] f, int rowNumber)
    {
        // Columns: Registration number; Vehicle name; Fuel; Initial odometer*;
        //          Year; Vehicle price; Tank volume; Initial tank status;
        //          LPG tank volume; Initial LPG tank status; Color
        var plate = string.IsNullOrEmpty(f[0]) ? null : f[0];
        var name = f[1];
        var fuelCode = ParseInt(f[2], ReasonInvalidNumber);
        var initialOdometer = ParseInt(f[3], ReasonInvalidNumber);
        var year = ParseInt(f[4], ReasonInvalidNumber);
        var tankCapacity = ParseDouble(f[6], ReasonInvalidNumber);

        var fuelKinds = FuelKindsFromCode(fuelCode);
        if (fuelKinds.Count == 0)
        {
            throw new RowParseException(ReasonUnknownFuelCode);
        }

        return new JsonObject
        {
            ["entityType"] = "vehicle",
            ["name"] = name,
            ["year"] = year,
            ["plate"] = plate,
            ["fuelKinds"] = new JsonArray(fuelKinds.Select(k => (JsonNode)k).ToArray()),
            ["tankCapacityL"] = tankCapacity,
            ["initialOdometer"] = initialOdometer,
            // Every vehicle in the export is an internal-combustion car; the LPG
            // tank column is 0 on all five rows, so nothing here is bi-fuel.
            ["powertrain"] = "ice",
            // The file's currency everywhere (a default the user corrects).
            ["homeCurrency"] = "USD",
            ["units"] = new JsonObject
            {
                ["distance"] = "km",
                ["volume"] = "l",
                ["consumption"] = "lPer100",
                ["energy"] = "kWhPer100",
            },
            ["archived"] = false,
            ["paceLimitKmPerDay"] = 1500,
            ["sourceRow"] = rowNumber,
        };
    }

    private static JsonObject MapCostsRow(
        string[] f,
        ref int ambiguousDates,
        ref int rowsWithCurrency,
        ref string? currency,
        int rowNumber)
    {
        // Columns: Date; Total price; Currency; Finance category; Odometer;
        //          Note; Vehicle name
        var date = ParseDate(f[0], ref ambiguousDates);
        var totalPrice = ParseDecimal(f[1], ReasonInvalidNumber);
        var rowCurrency = f[2];
        var category = f[3];
        var odometer = ParseInt(f[4], ReasonInvalidNumber);
        var note = f[5];
        var vehicleName = f[6];

        CountCurrency(rowCurrency, ref rowsWithCurrency, ref currency);

        var money = new JsonObject
        {
            ["amount"] = totalPrice.ToString(CultureInfo.InvariantCulture),
            ["currency"] = rowCurrency,
        };

        // MFM exports an empty odometer as 0; that is "not recorded", so it maps
        // to null (an optional field on service/expense entries) rather than a
        // nonsense reading of zero kilometres.
        var odometerValue = odometer > 0 ? odometer : (int?)null;

        // WORK / Diagnostic / Oil / Washing are work done to the car
        // (ServiceRecord); "Replacement parts" / Parking are money not tied to
        // work (Expense). An unknown category is a mapping gap: it lands on the
        // review list rather than being silently typed (hard rule 8).
        switch (category)
        {
            case "WORK":
                return ServiceRecordCandidate(date, odometerValue, money, note, vehicleName, "repair", rowNumber);
            case "Diagnostic":
                return ServiceRecordCandidate(date, odometerValue, money, note, vehicleName, "inspection", rowNumber);
            case "Oil":
                return ServiceRecordCandidate(date, odometerValue, money, note, vehicleName, "oil", rowNumber);
            case "Washing":
                return ServiceRecordCandidate(date, odometerValue, money, note, vehicleName, "wash", rowNumber);
            case "Replacement parts":
                return ExpenseCandidate(date, odometerValue, money, note, vehicleName, "parts", rowNumber);
            case "Parking":
                return ExpenseCandidate(date, odometerValue, money, note, vehicleName, "parking", rowNumber);
            default:
                throw new RowParseException(ReasonUnknownFinanceCategory);
        }
    }

    private static JsonObject ServiceRecordCandidate(
        DateTime date,
        int? odometer,
        JsonObject money,
        string note,
        string vehicleName,
        string category,
        int rowNumber)
    {
        var item = new JsonObject
        {
            ["title"] = note,
            ["category"] = new JsonObject { ["tag"] = category },
            ["cost"] = (JsonNode)money.DeepClone(),
        };

        return new JsonObject
        {
            ["entityType"] = "serviceRecord",
            ["date"] = date.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", CultureInfo.InvariantCulture),
            ["odometer"] = odometer,
            ["money"] = (JsonNode)money.DeepClone(),
            ["items"] = new JsonArray(item),
            ["note"] = null,
            ["vehicleName"] = vehicleName,
            ["provenance"] = (JsonNode)ImportProvenance.DeepClone(),
            ["sourceRow"] = rowNumber,
        };
    }

    private static JsonObject ExpenseCandidate(
        DateTime date,
        int? odometer,
        JsonObject money,
        string note,
        string vehicleName,
        string category,
        int rowNumber)
    {
        return new JsonObject
        {
            ["entityType"] = "expense",
            ["date"] = date.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", CultureInfo.InvariantCulture),
            ["odometer"] = odometer,
            ["money"] = (JsonNode)money.DeepClone(),
            ["category"] = new JsonObject { ["tag"] = category },
            ["title"] = note,
            ["vehicleName"] = vehicleName,
            ["provenance"] = (JsonNode)ImportProvenance.DeepClone(),
            ["sourceRow"] = rowNumber,
        };
    }

    private static IReadOnlyList<string> FuelKindsFromCode(int code)
    {
        // MFM fuel is a bitmask: bit 1 (1) = petrol, bit 2 (2) = diesel. The
        // vehicle code carries the fuels a car accepts; petrol octane is not in
        // the file, so it becomes a petrol95 default (hard rule 13).
        var kinds = new List<string>();
        if ((code & 1) != 0)
        {
            kinds.Add("petrol95");
        }

        if ((code & 2) != 0)
        {
            kinds.Add("diesel");
        }

        return kinds;
    }

    private static void CountCurrency(string rowCurrency, ref int rowsWithCurrency, ref string? currency)
    {
        if (string.IsNullOrEmpty(rowCurrency))
        {
            return;
        }

        rowsWithCurrency++;
        if (rowsWithCurrency == 1)
        {
            currency = rowCurrency;
            return;
        }

        if (currency is not null && !string.Equals(currency, rowCurrency, StringComparison.OrdinalIgnoreCase))
        {
            currency = null;
        }
    }

    /// <summary>Parses M/D/YYYY, the format's convention, and counts a row as genuinely ambiguous when its day is also &lt;= 12 (the same string would parse as D/M/YYYY).</summary>
    private static DateTime ParseDate(string text, ref int ambiguousDates)
    {
        if (!TryParseMdy(text, out var date))
        {
            throw new RowParseException(ReasonInvalidDate);
        }

        var parts = text.Split('/');
        if (parts.Length == 3 && int.TryParse(parts[1], NumberStyles.None, CultureInfo.InvariantCulture, out var day) && day <= 12)
        {
            ambiguousDates++;
        }

        return date;
    }

    private static bool TryParseMdy(string text, out DateTime date)
    {
        date = default;
        var parts = text.Split('/');
        if (parts.Length != 3 ||
            !int.TryParse(parts[0], NumberStyles.None, CultureInfo.InvariantCulture, out var month) ||
            !int.TryParse(parts[1], NumberStyles.None, CultureInfo.InvariantCulture, out var day) ||
            !int.TryParse(parts[2], NumberStyles.None, CultureInfo.InvariantCulture, out var year))
        {
            return false;
        }

        if (month is < 1 or > 12 || year is < 1000 or > 9999)
        {
            return false;
        }

        if (day < 1 || day > DateTime.DaysInMonth(year, month))
        {
            return false;
        }

        date = new DateTime(year, month, day, 0, 0, 0, DateTimeKind.Utc);
        return true;
    }

    private static double ParseDouble(string text, string reason)
    {
        if (!double.TryParse(text, NumberStyles.Float, CultureInfo.InvariantCulture, out var value))
        {
            throw new RowParseException(reason);
        }

        return value;
    }

    private static decimal ParseDecimal(string text, string reason)
    {
        if (!decimal.TryParse(text, NumberStyles.Number, CultureInfo.InvariantCulture, out var value))
        {
            throw new RowParseException(reason);
        }

        return value;
    }

    private static int ParseInt(string text, string reason)
    {
        if (!int.TryParse(text, NumberStyles.Integer, CultureInfo.InvariantCulture, out var value))
        {
            throw new RowParseException(reason);
        }

        return value;
    }

    /// <summary>
    /// MFM exports the odometer as a number that can carry a fractional part
    /// (the real fixture has a <c>3.22</c> row); Tankbook stores whole km. The
    /// value is rounded to the nearest kilometre - a format mapping, not a
    /// repair: a <c>3.22</c> still reads 3 and still lies far off the car's
    /// timeline, exactly where the preview's derived-consumption figure catches
    /// it (F6a).
    /// </summary>
    private static int ParseOdometer(string text)
    {
        if (!decimal.TryParse(text, NumberStyles.Number, CultureInfo.InvariantCulture, out var value))
        {
            throw new RowParseException(ReasonInvalidNumber);
        }

        return (int)Math.Round(value, 0, MidpointRounding.AwayFromZero);
    }

    private sealed class RowParseException : Exception
    {
        public RowParseException(string reason)
        {
            Reason = reason;
        }

        public string Reason { get; }
    }
}

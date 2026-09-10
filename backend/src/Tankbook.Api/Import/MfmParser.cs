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
///      the order is decided from the WHOLE file (RV.85), never row by row:
///      one export has one format, so a single row only one order can read
///      settles every row, and only a file no row settles still asks;
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

    // RV.116: the columns the parser has no home for, by their fixed position in
    // the kind's row (docs/SCHEMA.md "Import mapping"). Only vehicles.csv has
    // any - fuel/costs map every column, and incomes/reminders are whole-file
    // out of scope (reported by the `outOfScope` ambiguity, not as columns).
    private static readonly Dictionary<string, (int Index, string Name, bool ZeroIsEmpty)[]> UnsupportedColumnsByKind = new(StringComparer.OrdinalIgnoreCase)
    {
        ["vehicles"] =
        [
            (5, "Vehicle price", true),
            (7, "Initial tank status", true),
            (8, "LPG tank volume", true),
            (9, "Initial LPG tank status", true),
            // A hex colour: "000000" is black, a real value, so zero is not absence.
            (10, "Color", false),
        ],
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

    /// <summary>
    /// Groups candidates by their <c>vehicleName</c> column (RV.86), in order of
    /// first appearance in the file. A candidate whose file row carried no name
    /// (a blank <c>Vehicle name</c>) forms its own unnamed group so nothing is
    /// silently dropped. A single-name file yields one group covering every
    /// candidate.
    /// </summary>
    public static IReadOnlyList<MfmVehicleGroup> GroupByVehicleName(IEnumerable<JsonObject> candidates)
    {
        var orderedNames = new List<string>();
        var rowsByName = new Dictionary<string, List<int>>(StringComparer.Ordinal);
        foreach (var candidate in candidates)
        {
            var name = candidate["vehicleName"]?.GetValue<string>()?.Trim() ?? "";
            if (!rowsByName.TryGetValue(name, out var rows))
            {
                rows = [];
                rowsByName[name] = rows;
                orderedNames.Add(name);
            }

            rows.Add(candidate["sourceRow"]!.GetValue<int>());
        }

        return orderedNames.Select(name => new MfmVehicleGroup(name, rowsByName[name])).ToArray();
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

        // Buffer the data rows before mapping any of them (RV.85): the date
        // order is a property of the WHOLE file - one export has one format -
        // so it is decided over every row first, then applied to each. The real
        // exports are ~500 rows, so buffering costs nothing and keeps the parse
        // a single read -> decide -> map pass.
        var rows = new List<string[]>();
        while (true)
        {
            cancellationToken.ThrowIfCancellationRequested();
            var fields = ReadRow(parser);
            if (fields is null)
            {
                break;
            }

            fields = fields.Select(f => f.Trim()).ToArray();

            // A fully empty trailing line is not a data row.
            if (fields.Length == 0 || fields.All(string.IsNullOrEmpty))
            {
                continue;
            }

            rows.Add(fields);
        }

        var expectedColumns = ColumnsByKind[fileKind];
        // RV.85: decide the date order from the whole file. Only the kinds whose
        // dates map to a candidate participate (fuel and costs); vehicles has no
        // date column and incomes/reminders are unmapped, so neither ever asked.
        DateOrderDecision? dates = fileKind is "fuel" or "costs"
            ? DecideDateOrder(rows, expectedColumns)
            : null;

        var rowNumber = 0;
        var candidates = new List<JsonObject>();
        var unparsed = new List<UnparsedRow>();
        int rowsWithCurrency = 0;
        string? currency = null;
        // RV.116: how many rows carried a value in each column this kind does
        // not map. Only the cell's emptiness is observed; the value is never read.
        var unsupportedCounts = new Dictionary<string, int>();

        foreach (var fields in rows)
        {
            cancellationToken.ThrowIfCancellationRequested();
            rowNumber++;
            if (fields.Length != expectedColumns)
            {
                unparsed.Add(new UnparsedRow(rowNumber, ReasonWrongColumnCount));
                continue;
            }

            CountUnsupported(fileKind, fields, unsupportedCounts);

            try
            {
                var candidate = MapRow(fileKind, fields, dates, ref rowsWithCurrency, ref currency, rowNumber);
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
        // RV.85: the dateFormat question is asked ONLY when the file's own rows
        // cannot settle the order (every date has both components <= 12, so no
        // row proves which reading the file uses). A file any single row proves
        // M/D or D/M is resolved by that proof and does not ask - the parser
        // applies the proven order to every row, including the individually
        // ambiguous ones, and the ambiguity is gone from the wire.
        if (dates?.Ask == true && dates.AmbiguousRows > 0)
        {
            ambiguities.Add(new ImportAmbiguity(
                "dateFormat",
                ["M/D/YYYY", "D/M/YYYY"],
                dates.AmbiguousRows));
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
            // RV.116: only the columns that carried a value, in the format's
            // declared order. An all-empty column is omitted.
            Unsupported = ImportFormats.All.Single(f => f.Id == "mfm").UnsupportedColumns
                .Where(c => unsupportedCounts.GetValueOrDefault(c) > 0)
                .Select(c => new ImportUnsupportedColumn(c, unsupportedCounts[c]))
                .ToArray(),
            VehicleGroups = GroupByVehicleName(candidates),
        };
    }

    /// <summary>
    /// Adds one to the count of every unmapped column that carried a value in
    /// this row (RV.116). Positional, because the header text is not unique in
    /// this format's kinds; the cell's value is never read (hard rule 12).
    /// </summary>
    private static void CountUnsupported(string fileKind, string[] fields, Dictionary<string, int> counts)
    {
        if (!UnsupportedColumnsByKind.TryGetValue(fileKind, out var columns))
        {
            return;
        }

        foreach (var (index, name, zeroIsEmpty) in columns)
        {
            if (index < fields.Length && ImportCell.HasValue(fields[index], zeroIsEmpty))
            {
                counts[name] = counts.GetValueOrDefault(name) + 1;
            }
        }
    }

    private static string[]? ReadRow(TextFieldParser parser) => parser.EndOfData ? null : parser.ReadFields();

    /// <summary>Maps one data row to a candidate, or null for deliberately unmapped kinds (incomes/reminders).</summary>
    private static JsonObject? MapRow(
        string fileKind,
        string[] f,
        DateOrderDecision? dates,
        ref int rowsWithCurrency,
        ref string? currency,
        int rowNumber)
    {
        switch (fileKind)
        {
            case "fuel":
                return MapFuelRow(f, dates!, ref rowsWithCurrency, ref currency, rowNumber);
            case "vehicles":
                return MapVehicleRow(f, rowNumber);
            case "costs":
                return MapCostsRow(f, dates!, ref rowsWithCurrency, ref currency, rowNumber);
            case "incomes":
            case "reminders":
                return null;
            default:
                throw new InvalidOperationException($"Unhandled MFM file kind '{fileKind}'.");
        }
    }

    private static JsonObject MapFuelRow(
        string[] f,
        DateOrderDecision dates,
        ref int rowsWithCurrency,
        ref string? currency,
        int rowNumber)
    {
        // Columns: Date; Fillup volume; Odometer; Total price; Currency; Fuel;
        //          Tank status after fillup; %; Note; Vehicle name
        var date = ParseDate(f[0], dates.DayFirst);
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
        DateOrderDecision dates,
        ref int rowsWithCurrency,
        ref string? currency,
        int rowNumber)
    {
        // Columns: Date; Total price; Currency; Finance category; Odometer;
        //          Note; Vehicle name
        var date = ParseDate(f[0], dates.DayFirst);
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

        // WORK / Diagnostic / Oil / Washing are work done to the car, and
        // "Replacement parts" are parts fitted to it - the second-largest cost
        // category in the real export (RV.96), whose notes («Замена колес зима
        // -> лето», «Топливный фильтр VAG 8t0127401A») name what went on the
        // car. All five map to a ServiceRecord; the parts notes become the
        // service item's title (their value - they must never be dropped into
        // parsing part numbers, RV.96). Parking is money not tied to work on
        // the car - exactly what Expense is for. An unknown category is a
        // mapping gap: it lands on the review list rather than being silently
        // typed (hard rule 8).
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
                return ServiceRecordCandidate(date, odometerValue, money, note, vehicleName, "parts", rowNumber);
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

    /// <summary>
    /// Decides the date order the WHOLE file uses (RV.85). One export has one
    /// format, so a row only one order can read proves that order for every
    /// row - a "13/05" anywhere proves D/M, a "05/13" proves M/D - and the
    /// individually ambiguous rows follow the proof. A row neither order can
    /// read is not evidence (a corrupt "99/99" must not flip a real file's
    /// order); it stays invalid for the mapping pass. A file whose rows prove
    /// BOTH orders is inconsistent - not an ambiguity a question could answer,
    /// and an error rather than a guess (docs/API.md, docs/ERRORS.md). A file
    /// no row proves stays undecidable and keeps the dateFormat question
    /// exactly as it did before RV.85.
    /// </summary>
    private static DateOrderDecision DecideDateOrder(IReadOnlyList<string[]> rows, int columnCount)
    {
        var sawMonthFirstOnly = false; // rows only M/D can read prove M/D
        var sawDayFirstOnly = false;   // rows only D/M can read prove D/M
        var ambiguous = 0;

        foreach (var row in rows)
        {
            if (row.Length != columnCount)
            {
                continue; // a wrong-column row never reaches the date column
            }

            switch (ClassifyDate(row[0]))
            {
                case DateValidity.OnlyMonthFirst:
                    sawMonthFirstOnly = true;
                    break;
                case DateValidity.OnlyDayFirst:
                    sawDayFirstOnly = true;
                    break;
                case DateValidity.Ambiguous:
                    ambiguous++;
                    break;
                case DateValidity.Invalid:
                    break;
            }
        }

        if (sawMonthFirstOnly && sawDayFirstOnly)
        {
            throw new InconsistentDateOrderException(
                "The file mixes two date orders: some rows only read as M/D/YYYY and others only as D/M/YYYY. One export has one format, so correct the dates in the file and import it again.");
        }

        return new DateOrderDecision
        {
            // M/D is the format's convention; only a file proven day-first by
            // its own rows parses D/M.
            DayFirst = sawDayFirstOnly,
            // A file no row proves has no answer on disk - the question stays.
            Ask = !sawMonthFirstOnly && !sawDayFirstOnly,
            AmbiguousRows = ambiguous,
        };
    }

    /// <summary>
    /// Classifies one date cell by which readings are valid dates: only M/D
    /// (a component &gt; 12 in the second position proves M/D), only D/M (a
    /// component &gt; 12 in the first position proves D/M), both (individually
    /// undecidable), or neither (an invalid date, never evidence). A reading is
    /// valid only when the month is 1-12 and the day fits that month - a
    /// "99/05" is not D/M evidence, because day 99 is not a day.
    /// </summary>
    private static DateValidity ClassifyDate(string text)
    {
        var monthFirst = TryParseDate(text, dayFirst: false, out _);
        var dayFirst = TryParseDate(text, dayFirst: true, out _);
        if (monthFirst && dayFirst)
        {
            return DateValidity.Ambiguous;
        }

        if (monthFirst)
        {
            return DateValidity.OnlyMonthFirst;
        }

        if (dayFirst)
        {
            return DateValidity.OnlyDayFirst;
        }

        return DateValidity.Invalid;
    }

    /// <summary>Parses a date cell under the whole-file-decided order (RV.85); an invalid date throws the row's reason.</summary>
    private static DateTime ParseDate(string text, bool dayFirst)
    {
        if (!TryParseDate(text, dayFirst, out var date))
        {
            throw new RowParseException(ReasonInvalidDate);
        }

        return date;
    }

    /// <summary>
    /// Parses <c>a/b/YYYY</c> under one order: month-first (M/D) or day-first
    /// (D/M). A reading is valid only when the month is 1-12 and the day fits
    /// that month's length - the same strictness the old M/D-only parse
    /// applied to its single reading.
    /// </summary>
    private static bool TryParseDate(string text, bool dayFirst, out DateTime date)
    {
        date = default;
        var parts = text.Split('/');
        if (parts.Length != 3 ||
            !int.TryParse(parts[0], NumberStyles.None, CultureInfo.InvariantCulture, out var first) ||
            !int.TryParse(parts[1], NumberStyles.None, CultureInfo.InvariantCulture, out var second) ||
            !int.TryParse(parts[2], NumberStyles.None, CultureInfo.InvariantCulture, out var year))
        {
            return false;
        }

        if (year is < 1000 or > 9999)
        {
            return false;
        }

        var month = dayFirst ? second : first;
        var day = dayFirst ? first : second;
        if (month is < 1 or > 12)
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

    /// <summary>
    /// The whole-file date decision (RV.85). One export has one date order;
    /// the parser reads every row before mapping any, so a single row only one
    /// order can read settles the file. <see cref="Ask"/> is true only when no
    /// row settles it - every date has both components &lt;= 12 - and only then
    /// does the file keep the dateFormat question, because there the M/D
    /// convention is a guess the user must confirm rather than a proven order.
    /// </summary>
    private sealed class DateOrderDecision
    {
        /// <summary>true = parse dates day-first (D/M/YYYY); false = month-first (M/D/YYYY).</summary>
        public required bool DayFirst { get; init; }

        /// <summary>True only when the file's own rows cannot settle the order, so the F6 dateFormat question is still asked.</summary>
        public required bool Ask { get; init; }

        /// <summary>Rows that genuinely read either way (both components &lt;= 12) - the count the question carries.</summary>
        public required int AmbiguousRows { get; init; }
    }

    /// <summary>How one date cell reads, under the two orders the format could use (RV.85).</summary>
    private enum DateValidity
    {
        /// <summary>Neither M/D nor D/M can read the string - an invalid date, never evidence of an order.</summary>
        Invalid,

        /// <summary>Both readings are valid dates (both components &lt;= 12): individually undecidable.</summary>
        Ambiguous,

        /// <summary>Only the month-first reading (M/D/YYYY) is a valid date - the row proves the file is M/D.</summary>
        OnlyMonthFirst,

        /// <summary>Only the day-first reading (D/M/YYYY) is a valid date - the row proves the file is D/M.</summary>
        OnlyDayFirst,
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

using System.Globalization;
using System.Text;
using System.Text.Json.Nodes;

namespace Tankbook.Api.Import;

/// <summary>
/// The Drivvo parser (docs/SCHEMA.md "Import mapping", the real export at
/// Spike/ImportFixtures/drivvo/). The shape is nothing like MFM's, and the tests
/// pin the differences that break a first-attempt reader:
///   1. one file, THREE sections - each `##`-marked and each with its own header
///      line (`##Refuelling`, `##Expense`, `##Service`), so "the title line names
///      the kind" does not transfer and the parser scans for section markers;
///   2. the headers are LOCALISED (this export is Russian) and two hazards make a
///      stock CSV reader wrong (see below);
///   3. dates are `yyyy-MM-dd HH:mm:ss` - a space, not an ISO-8601 `T`;
///   4. mixed decimal conventions inside one row (a `37.52` volume beside a
///      `6,414 л/100км` consumption), and the consumption figure itself is a
///      derived number the app recomputes (hard rule 2), so it is not imported;
///   5. there is NO currency column anywhere, so money lands without a currency
///      and the wizard asks (hard rule 13), and no vehicle column - one car per
///      file, so [RV.93]'s grouping does not apply;
///   6. `"Полный бак"` is localised Да/Нет, not a boolean, and `"0.0"` odometer
///      is "not recorded", never a zero reading.
///
/// The parser is a pure function: it returns candidate proposals and commits
/// nothing (hard rule 9). A row that cannot be mapped lands in <c>Unparsed</c>
/// with a stable reason and the rest keep parsing (F6, hard rule 8). A file that
/// does not look like a Drivvo export throws <see cref="NotDrivvoExportException"/>
/// (the 422 path).
/// </summary>
public static class DrivvoParser
{
    private const string RefuellingMarker = "##Refuelling";
    private const string ExpenseMarker = "##Expense";
    private const string ServiceMarker = "##Service";

    /// <summary>The provenance every imported candidate carries (docs/SCHEMA.md import rules).</summary>
    public static readonly JsonObject ImportProvenance = new()
    {
        ["tag"] = "import",
        ["source"] = "drivvo",
    };

    /// <summary>
    /// How the CSV is read (hazard 1, measured not assumed). Feeding line 2 of the
    /// real export to <c>TextFieldParser</c> with <c>HasFieldsEnclosedInQuotes = true</c>
    /// (MfmParser's configuration) throws <c>MalformedLineException</c>: Drivvo
    /// disambiguates its second/third fuel blocks by appending a digit OUTSIDE the
    /// closing quote (<c>"Полный бак" 2</c>), which a strict reader rejects. A lenient
    /// reader (Python's csv) yields 29 fields and <c>Полный бак 2</c>. The data rows,
    /// meanwhile, need quote-aware parsing - the consumption cell is <c>"6,414 л/100км"</c>,
    /// a comma INSIDE quotes, which <c>HasFieldsEnclosedInQuotes = false</c> would split
    /// into two fields. So this reader is a small, lenient RFC-4180 splitter: quoted
    /// fields keep embedded commas and <c>""</c> escapes, and a closing quote followed by
    /// a non-delimiter appends the trailing text (the leniency that turns
    /// <c>"Полный бак" 2</c> into <c>Полный бак 2</c>). One reader serves header and data;
    /// no pre-pass, no silently swallowed malformed-line exception.
    /// </summary>
    private static string[] SplitLine(string line)
    {
        var fields = new List<string>();
        var sb = new StringBuilder();
        var inQuotes = false;
        for (var i = 0; i < line.Length; i++)
        {
            var c = line[i];
            if (inQuotes)
            {
                if (c == '"')
                {
                    if (i + 1 < line.Length && line[i + 1] == '"')
                    {
                        sb.Append('"');
                        i++;
                    }
                    else
                    {
                        inQuotes = false;
                    }
                }
                else
                {
                    sb.Append(c);
                }
            }
            else if (c == '"' && sb.Length == 0)
            {
                inQuotes = true;
            }
            else if (c == ',')
            {
                fields.Add(sb.ToString());
                sb.Clear();
            }
            else
            {
                sb.Append(c);
            }
        }

        fields.Add(sb.ToString());
        return fields.ToArray();
    }

    public static MfmParseResult Parse(Stream csv, CancellationToken cancellationToken)
    {
        var lines = ReadLines(csv);
        var sections = SplitSections(lines);
        if (!sections.ContainsKey(RefuellingMarker))
        {
            throw new NotDrivvoExportException(
                "The file has no ##Refuelling section; a Drivvo export begins with one.");
        }

        var candidates = new List<JsonObject>();
        var unparsed = new List<UnparsedRow>();
        var moneyRows = 0;
        // RV.116: how many rows carried a value in each column the format has no
        // home for. Counted per file (all sections accumulate) and returned with
        // the parse, never with the format list - only the file can know it.
        var unsupportedCounts = new Dictionary<string, int>();

        foreach (var (marker, section) in sections)
        {
            cancellationToken.ThrowIfCancellationRequested();
            switch (marker)
            {
                case RefuellingMarker:
                    MapRefuelling(section, candidates, unparsed, unsupportedCounts, ref moneyRows, cancellationToken);
                    break;
                case ExpenseMarker:
                    MapExpense(section, candidates, unparsed, unsupportedCounts, ref moneyRows, cancellationToken);
                    break;
                case ServiceMarker:
                    MapService(section, candidates, unparsed, unsupportedCounts, ref moneyRows, cancellationToken);
                    break;
            }
        }

        var ambiguities = new List<ImportAmbiguity>();
        // There is no currency column in any section: money lands with an EMPTY
        // currency, and the wizard must ask (defaulting to the destination car's
        // home currency, hard rule 13). The ambiguity's empty options are the
        // signal - there is no answer on disk to declare, so none is guessed.
        if (moneyRows > 0)
        {
            ambiguities.Add(new ImportAmbiguity("currency", [], moneyRows));
        }

        return new MfmParseResult
        {
            FileKind = "drivvo",
            Candidates = candidates,
            Unparsed = unparsed,
            Ambiguities = ambiguities,
            DataRowCount = sections.Values.Sum(s => s.Rows.Count),
            // Only the columns that carried a value are reported, in the order
            // the format declares them (RV.116). An all-empty column is omitted:
            // a notice about nothing buries the column that matters.
            Unsupported = ImportFormats.All.Single(f => f.Id == "drivvo").UnsupportedColumns
                .Where(c => unsupportedCounts.GetValueOrDefault(c) > 0)
                .Select(c => new ImportUnsupportedColumn(c, unsupportedCounts[c]))
                .ToArray(),
            // One car per file: no vehicle column, so every candidate shares one
            // unnamed group - the single-car flow, exactly as the row requires.
            VehicleGroups = MfmParser.GroupByVehicleName(candidates),
        };
    }

    private static List<string> ReadLines(Stream csv)
    {
        var lines = new List<string>();
        using var reader = new StreamReader(csv, Encoding.UTF8, detectEncodingFromByteOrderMarks: true, leaveOpen: true);
        while (reader.ReadLine() is { } line)
        {
            lines.Add(line);
        }

        return lines;
    }

    private static Dictionary<string, Section> SplitSections(List<string> lines)
    {
        var sections = new Dictionary<string, Section>();
        Section? current = null;
        foreach (var line in lines)
        {
            if (line.StartsWith("##", StringComparison.Ordinal))
            {
                current = new Section();
                sections[line.Trim()] = current;
                continue;
            }

            if (current is null || string.IsNullOrWhiteSpace(line))
            {
                continue;
            }

            var fields = SplitLine(line);
            if (current.Header is null)
            {
                current.Header = fields.Select(f => f.Trim()).ToArray();
            }
            else
            {
                current.Rows.Add(fields.Select(f => f.Trim()).ToArray());
            }
        }

        return sections;
    }

    // ---- Refuelling --------------------------------------------------------

    private static void MapRefuelling(
        Section section,
        List<JsonObject> candidates,
        List<UnparsedRow> unparsed,
        Dictionary<string, int> unsupportedCounts,
        ref int moneyRows,
        CancellationToken cancellationToken)
    {
        var header = section.Header ?? [];
        var language = DetectLanguage(header);
        CountUnsupported(language, section, unsupportedCounts);
        var index = BuildIndex(language, header, "odometer", "date", "fuel", "unitPrice", "totalCost", "volume", "fullTank", "station", "note");

        var rowNumber = 0;
        foreach (var fields in section.Rows)
        {
            cancellationToken.ThrowIfCancellationRequested();
            rowNumber++;
            try
            {
                var candidate = MapRefuellingRow(language, index, fields, rowNumber);
                if (candidate is not null)
                {
                    candidates.Add(candidate);
                    moneyRows++;
                }
            }
            catch (RowParseException ex)
            {
                unparsed.Add(new UnparsedRow(rowNumber, ex.Reason));
            }
        }
    }

    private static JsonObject MapRefuellingRow(Language language, IReadOnlyDictionary<string, int> index, string[] f, int rowNumber)
    {
        var date = ParseDate(Field(f, index, "date"));
        var volume = ParseDecimal(Field(f, index, "volume"), MfmParser.ReasonInvalidNumber);
        var unitPrice = ParseDecimal(Field(f, index, "unitPrice"), MfmParser.ReasonInvalidNumber);
        var totalCost = ParseDecimal(Field(f, index, "totalCost"), MfmParser.ReasonInvalidNumber);
        var odometer = ParseOdometer(Field(f, index, "odometer"));
        var fuelKind = MapFuelGrade(language, Field(f, index, "fuel"));
        var fullTank = Field(f, index, "fullTank");
        var station = NullIfEmpty(Field(f, index, "station"));
        var note = NullIfEmpty(Field(f, index, "note"));

        var isFull = string.Equals(fullTank, language.Yes, StringComparison.Ordinal) ? true
            : string.Equals(fullTank, language.No, StringComparison.Ordinal) ? false
            : (bool?)null;

        var money = new JsonObject
        {
            ["amount"] = totalCost.ToString(CultureInfo.InvariantCulture),
            // No currency column anywhere in the file (hazard, hard rule 3): the
            // amount rides alone and the wizard asks (an EMPTY currency, never a
            // guessed default).
            ["currency"] = "",
        };

        return new JsonObject
        {
            ["entityType"] = "fillUp",
            ["date"] = date.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", CultureInfo.InvariantCulture),
            ["odometer"] = odometer,
            ["volumeL"] = (double)volume,
            ["unitPrice"] = unitPrice.ToString(CultureInfo.InvariantCulture),
            ["money"] = money,
            ["fuelKind"] = fuelKind,
            ["isFull"] = isFull,
            ["tankLevelAfterPct"] = null,
            ["station"] = station,
            ["note"] = note,
            ["provenance"] = (JsonNode)ImportProvenance.DeepClone(),
            ["sourceRow"] = rowNumber,
        };
    }

    // ---- Expense -----------------------------------------------------------

    private static void MapExpense(
        Section section,
        List<JsonObject> candidates,
        List<UnparsedRow> unparsed,
        Dictionary<string, int> unsupportedCounts,
        ref int moneyRows,
        CancellationToken cancellationToken)
    {
        var header = section.Header ?? [];
        var language = DetectLanguage(header);
        CountUnsupported(language, section, unsupportedCounts);
        var index = BuildIndex(language, header, "odometer", "date", "totalCost", "expenseKind", "note", "title");

        var rowNumber = 0;
        foreach (var fields in section.Rows)
        {
            cancellationToken.ThrowIfCancellationRequested();
            rowNumber++;
            try
            {
                var date = ParseDate(Field(fields, index, "date"));
                var totalCost = ParseDecimal(Field(fields, index, "totalCost"), MfmParser.ReasonInvalidNumber);
                var odometer = ParseOdometer(Field(fields, index, "odometer"));
                var kind = Field(fields, index, "expenseKind");
                var title = NullIfEmpty(Field(fields, index, "title"))
                    ?? NullIfEmpty(Field(fields, index, "note"));
                var note = NullIfEmpty(Field(fields, index, "note"));

                var category = language.ExpenseKinds.TryGetValue(kind, out var mapped) ? mapped : kind;
                var money = new JsonObject
                {
                    ["amount"] = totalCost.ToString(CultureInfo.InvariantCulture),
                    ["currency"] = "",
                };

                candidates.Add(new JsonObject
                {
                    ["entityType"] = "expense",
                    ["date"] = date.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", CultureInfo.InvariantCulture),
                    ["odometer"] = odometer,
                    ["money"] = money,
                    ["category"] = new JsonObject { ["tag"] = category },
                    ["title"] = title,
                    ["note"] = note,
                    ["provenance"] = (JsonNode)ImportProvenance.DeepClone(),
                    ["sourceRow"] = rowNumber,
                });
                moneyRows++;
            }
            catch (RowParseException ex)
            {
                unparsed.Add(new UnparsedRow(rowNumber, ex.Reason));
            }
        }
    }

    // ---- Service -----------------------------------------------------------

    private static void MapService(
        Section section,
        List<JsonObject> candidates,
        List<UnparsedRow> unparsed,
        Dictionary<string, int> unsupportedCounts,
        ref int moneyRows,
        CancellationToken cancellationToken)
    {
        var header = section.Header ?? [];
        var language = DetectLanguage(header);
        CountUnsupported(language, section, unsupportedCounts);
        var index = BuildIndex(language, header, "odometer", "date", "totalCost", "serviceKind", "serviceName", "title", "note");

        var rowNumber = 0;
        foreach (var fields in section.Rows)
        {
            cancellationToken.ThrowIfCancellationRequested();
            rowNumber++;
            try
            {
                var date = ParseDate(Field(fields, index, "date"));
                var totalCost = ParseDecimal(Field(fields, index, "totalCost"), MfmParser.ReasonInvalidNumber);
                var odometer = ParseOdometer(Field(fields, index, "odometer"));
                var kind = Field(fields, index, "serviceKind");
                var title = NullIfEmpty(Field(fields, index, "serviceName"))
                    ?? NullIfEmpty(Field(fields, index, "title"))
                    ?? NullIfEmpty(Field(fields, index, "note"));

                var category = language.ServiceKinds.TryGetValue(kind, out var mapped) ? mapped : kind;
                var money = new JsonObject
                {
                    ["amount"] = totalCost.ToString(CultureInfo.InvariantCulture),
                    ["currency"] = "",
                };

                var item = new JsonObject
                {
                    ["title"] = title,
                    ["category"] = new JsonObject { ["tag"] = category },
                    ["cost"] = (JsonNode)money.DeepClone(),
                };

                candidates.Add(new JsonObject
                {
                    ["entityType"] = "serviceRecord",
                    ["date"] = date.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", CultureInfo.InvariantCulture),
                    ["odometer"] = odometer,
                    ["money"] = (JsonNode)money.DeepClone(),
                    ["items"] = new JsonArray(item),
                    ["note"] = NullIfEmpty(Field(fields, index, "note")),
                    ["provenance"] = (JsonNode)ImportProvenance.DeepClone(),
                    ["sourceRow"] = rowNumber,
                });
                moneyRows++;
            }
            catch (RowParseException ex)
            {
                unparsed.Add(new UnparsedRow(rowNumber, ex.Reason));
            }
        }
    }

    // ---- shared helpers ----------------------------------------------------

    private static string Field(string[] f, IReadOnlyDictionary<string, int> index, string key)
        => index.TryGetValue(key, out var i) && i < f.Length ? f[i] : "";

    private static string? NullIfEmpty(string text) => string.IsNullOrEmpty(text) ? null : text;

    /// <summary>
    /// Adds one to the count of every format-unsupported column that carried a
    /// value in a row of this section (RV.116). The column is located by its
    /// localised header text; only whether the cell is non-empty is observed -
    /// the value is never read, and only the column name and the count leave
    /// (hard rule 12). Repeated headers (the second/third fuel blocks share
    /// `Объем`) are not in the unsupported map, so no occurrence is ambiguous.
    /// </summary>
    private static void CountUnsupported(Language language, Section section, Dictionary<string, int> counts)
    {
        var header = section.Header ?? [];
        var byIndex = new Dictionary<int, (string Name, bool ZeroIsEmpty)>();
        for (var i = 0; i < header.Length; i++)
        {
            if (language.UnsupportedHeaders.TryGetValue(header[i], out var column))
            {
                byIndex[i] = column;
            }
        }

        if (byIndex.Count == 0)
        {
            return;
        }

        foreach (var row in section.Rows)
        {
            foreach (var (index, column) in byIndex)
            {
                if (index < row.Length && ImportCell.HasValue(row[index], column.ZeroIsEmpty))
                {
                    counts[column.Name] = counts.GetValueOrDefault(column.Name) + 1;
                }
            }
        }
    }

    private static Dictionary<string, int> BuildIndex(Language language, string[] header, params string[] keys)
    {
        var index = new Dictionary<string, int>();
        foreach (var key in keys)
        {
            if (!language.Headers.TryGetValue(key, out var text))
            {
                continue;
            }

            for (var i = 0; i < header.Length; i++)
            {
                if (header[i] == text)
                {
                    index[key] = i;
                    break;
                }
            }
        }

        return index;
    }

    private static Language DetectLanguage(string[] header)
    {
        foreach (var language in Languages)
        {
            if (header.Contains(language.Headers["date"]) && header.Contains(language.Headers["totalCost"]))
            {
                return language;
            }
        }

        throw new NotDrivvoExportException(
            "The header does not match a Drivvo export (expected a recognised language's column names).");
    }

    private static DateTime ParseDate(string text)
    {
        if (!DateTime.TryParseExact(
                text,
                "yyyy-MM-dd HH:mm:ss",
                CultureInfo.InvariantCulture,
                DateTimeStyles.AssumeUniversal | DateTimeStyles.AdjustToUniversal,
                out var date))
        {
            throw new RowParseException(MfmParser.ReasonInvalidDate);
        }

        return date;
    }

    private static string MapFuelGrade(Language language, string grade)
    {
        if (language.FuelGrades.TryGetValue(grade, out var fuelKind))
        {
            return fuelKind;
        }

        throw new RowParseException(MfmParser.ReasonUnknownFuelCode);
    }

    /// <summary>
    /// Parses a Drivvo decimal. Drivvo mixes conventions inside one row (a
    /// `37.52` volume beside a `6,414 л/100км` consumption), so both a dot and a
    /// comma read as the decimal point - Drivvo never emits a thousands
    /// separator. The consumption cell is not a field the parser reads, so its
    /// unit suffix is never parsed; it is split off by the reader (hazard 1)
    /// and ignored.
    /// </summary>
    private static decimal ParseDecimal(string text, string reason)
    {
        var normalized = text.Trim().Replace(',', '.');
        if (!decimal.TryParse(normalized, NumberStyles.Number, CultureInfo.InvariantCulture, out var value))
        {
            throw new RowParseException(reason);
        }

        return value;
    }

    /// <summary>Drivvo exports an unrecorded odometer as "0.0"/"0"; that is "not recorded", so it maps to null (never a zero reading).</summary>
    private static int? ParseOdometer(string text)
    {
        if (string.IsNullOrWhiteSpace(text))
        {
            return null;
        }

        var value = ParseDecimal(text, MfmParser.ReasonInvalidNumber);
        var rounded = (int)Math.Round(value, 0, MidpointRounding.AwayFromZero);
        return rounded > 0 ? rounded : (int?)null;
    }

    // ---- the per-language data (decision 3: adding a language is a data edit) --

    private sealed record Language(
        IReadOnlyDictionary<string, string> Headers,
        string Yes,
        string No,
        IReadOnlyDictionary<string, string> FuelGrades,
        IReadOnlyDictionary<string, string> ExpenseKinds,
        IReadOnlyDictionary<string, string> ServiceKinds,
        IReadOnlyDictionary<string, (string Name, bool ZeroIsEmpty)> UnsupportedHeaders);

    /// <summary>Measured from the committed Russian export (Spike/ImportFixtures/drivvo/).</summary>
    private static readonly Language Russian = new(
        Headers: new Dictionary<string, string>
        {
            ["odometer"] = "Одометр (км)",
            ["date"] = "Дата",
            ["fuel"] = "Топливо",
            ["unitPrice"] = "Цена / л",
            ["totalCost"] = "Общая стоимость",
            ["volume"] = "Объем",
            ["fullTank"] = "Полный бак",
            ["consumption"] = "Эффективный расход топлива",
            ["distance"] = "Расстояние",
            ["station"] = "Азс",
            ["note"] = "Примечание",
            ["expenseKind"] = "Вид расхода",
            ["serviceKind"] = "Вид сервиса",
            ["serviceName"] = "Название сервиса",
            ["title"] = "Заголовок",
        },
        Yes: "Да",
        No: "Нет",
        FuelGrades: new Dictionary<string, string>
        {
            ["Бензин АИ92"] = "petrol92",
            ["Бензин АИ95"] = "petrol95",
            ["Бензин АИ98"] = "petrol98",
            ["Бензин АИ100"] = "petrol100",
            ["Дизель"] = "diesel",
            ["Дизельное топливо"] = "diesel",
            ["ДТ"] = "diesel",
            ["Газ"] = "lpg",
            ["Метан"] = "cng",
        },
        ExpenseKinds: new Dictionary<string, string>
        {
            ["Страхование"] = "insurance",
        },
        ServiceKinds: new Dictionary<string, string>
        {
            ["Замена масла"] = "oil",
            ["Масляный фильтр"] = "filters",
            ["Воздушный фильтр"] = "filters",
            ["Топливный фильтр"] = "filters",
            ["Фильтр АКПП"] = "filters",
            ["Тормозные колодки"] = "brakes",
            ["Тормозные диски"] = "brakes",
            ["Замена тормозов"] = "brakes",
            ["Новые шины"] = "tires",
            ["Балансировка шин"] = "tires",
            ["Аккумулятор"] = "battery",
        },
        UnsupportedHeaders: new Dictionary<string, (string Name, bool ZeroIsEmpty)>
        {
            // The columns the parser has no home for, keyed by the header text
            // the user's file carries. Values are the canonical names declared by
            // ImportFormats (RV.116), with whether a zero-only cell counts as
            // absence (numeric columns) or as a value (text). Second/third fuel
            // blocks are counted by their fuel-name cell; their repeated
            // price/total/volume headers are not listed, so no occurrence is
            // ambiguous.
            ["Второе топливо"] = ("Second fuel", false),
            ["Третье топливо"] = ("Third fuel", false),
            ["Тип зарядки"] = ("Charge type", false),
            ["Начальный заряд (%)"] = ("Charge start %", true),
            ["Конечный заряд (%)"] = ("Charge end %", true),
            ["Длительность (мин)"] = ("Charge duration", true),
            ["Водитель"] = ("Driver", false),
            ["Тип расхода"] = ("Expense type", false),
            ["Метод оплаты"] = ("Payment method", false),
            ["Скидка"] = ("Discount", true),
            ["Местный расход"] = ("Local cost", true),
        });

    /// <summary>
    /// Derived from Drivvo's documented English export - NOT verified against a
    /// real English file. The RU set is measured; this set exists so a second
    /// language is a data edit (decision 3) and to prove both languages map to
    /// the same canonical fields, but the exact English strings are unverified.
    /// </summary>
    private static readonly Language English = new(
        Headers: new Dictionary<string, string>
        {
            ["odometer"] = "Odometer (km)",
            ["date"] = "Date",
            ["fuel"] = "Fuel",
            ["unitPrice"] = "Price / l",
            ["totalCost"] = "Total cost",
            ["volume"] = "Volume",
            ["fullTank"] = "Full tank",
            ["consumption"] = "Effective fuel consumption",
            ["distance"] = "Distance",
            ["station"] = "Gas station",
            ["note"] = "Note",
            ["expenseKind"] = "Expense type",
            ["serviceKind"] = "Service type",
            ["serviceName"] = "Service name",
            ["title"] = "Title",
        },
        Yes: "Yes",
        No: "No",
        FuelGrades: new Dictionary<string, string>
        {
            ["Petrol 92"] = "petrol92",
            ["Petrol 95"] = "petrol95",
            ["Petrol 98"] = "petrol98",
            ["Diesel"] = "diesel",
            ["LPG"] = "lpg",
        },
        ExpenseKinds: new Dictionary<string, string>
        {
            ["Insurance"] = "insurance",
        },
        ServiceKinds: new Dictionary<string, string>
        {
            ["Oil change"] = "oil",
            ["Oil filter"] = "filters",
            ["Air filter"] = "filters",
            ["Fuel filter"] = "filters",
            ["Brake pads"] = "brakes",
            ["Brake discs"] = "brakes",
            ["New tires"] = "tires",
            ["Battery"] = "battery",
        },
        UnsupportedHeaders: new Dictionary<string, (string Name, bool ZeroIsEmpty)>
        {
            // The English set is derived from Drivvo's documented export and is
            // UNVERIFIED against a real English file, exactly like Headers above.
            ["Second fuel"] = ("Second fuel", false),
            ["Third fuel"] = ("Third fuel", false),
            ["Charging type"] = ("Charge type", false),
            ["Start charge (%)"] = ("Charge start %", true),
            ["End charge (%)"] = ("Charge end %", true),
            ["Duration (min)"] = ("Charge duration", true),
            ["Driver"] = ("Driver", false),
            ["Expense type"] = ("Expense type", false),
            ["Payment method"] = ("Payment method", false),
            ["Discount"] = ("Discount", true),
            ["Local cost"] = ("Local cost", true),
        });

    private static readonly IReadOnlyList<Language> Languages = [Russian, English];

    private sealed class Section
    {
        public string[]? Header { get; set; }

        public List<string[]> Rows { get; } = [];
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

/// <summary>
/// The file does not look like the Drivvo format the user declared (docs/API.md:
/// 422 "this does not look like a Drivvo export"). Carries a detail the client
/// can surface verbatim.
/// </summary>
public sealed class NotDrivvoExportException : Exception
{
    public NotDrivvoExportException(string detail)
        : base(detail)
    {
        Detail = detail;
    }

    public string Detail { get; }
}

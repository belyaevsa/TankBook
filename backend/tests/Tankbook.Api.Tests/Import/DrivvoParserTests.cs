using System.Text;
using System.Text.Json.Nodes;
using Tankbook.Api.Import;

namespace Tankbook.Api.Tests.Import;

/// <summary>
/// The Drivvo parser against the committed real export (Spike/ImportFixtures/drivvo/).
/// docs/API.md "Import parsing": the parser is a pure function - candidates are
/// proposals, nothing is committed. docs/TESTING.md: assert field VALUES on a
/// named row, never just a count.
/// </summary>
public class DrivvoParserTests
{
    // ---- the three sections, measured --------------------------------------

    [Fact]
    public void RealFile_ParsesThreeSectionsIntoTheirOwnKinds()
    {
        using var stream = DrivvoFixture.Open(DrivvoFixture.ThreeSectionsCsv);
        var result = DrivvoParser.Parse(stream, CancellationToken.None);

        // The file holds 250 refuelling rows, 11 expense rows and 54 service
        // rows (the blank line between sections is a separator, not a data row).
        Assert.Equal("drivvo", result.FileKind);
        Assert.Equal(250, Count(result, "fillUp"));
        Assert.Equal(11, Count(result, "expense"));
        Assert.Equal(54, Count(result, "serviceRecord"));
        Assert.Equal(250 + 11 + 54, result.DataRowCount);
        Assert.Empty(result.Unparsed);
    }

    [Fact]
    public void RealFile_NamedRefuellingRow_MapsEveryField()
    {
        using var stream = DrivvoFixture.Open(DrivvoFixture.ThreeSectionsCsv);
        var result = DrivvoParser.Parse(stream, CancellationToken.None);

        // The named row: "491206.0","2025-08-02 06:55:11","Бензин АИ92","220",
        // "6630","30.136","Да",...  (the second fill in the file).
        var candidate = result.Candidates
            .Where(c => c["entityType"]!.GetValue<string>() == "fillUp")
            .Single(c => c["odometer"]!.GetValue<int>() == 491206);

        Assert.Equal("2025-08-02T06:55:11Z", candidate["date"]!.GetValue<string>());
        Assert.Equal(30.136, candidate["volumeL"]!.GetValue<double>(), 6);
        Assert.Equal("220", candidate["unitPrice"]!.GetValue<string>());
        Assert.Equal("6630", candidate["money"]!["amount"]!.GetValue<string>());
        Assert.Equal("petrol92", candidate["fuelKind"]!.GetValue<string>());
        Assert.True(candidate["isFull"]!.GetValue<bool>());
        Assert.Equal("import", candidate["provenance"]!["tag"]!.GetValue<string>());
        Assert.Equal("drivvo", candidate["provenance"]!["source"]!.GetValue<string>());
        // The `Азс` column (the refuelling row's 25th field) reaches the
        // candidate (RV.142): it is the row's title on the Log and was read
        // and thrown away before.
        Assert.Equal("Газпром", candidate["station"]!.GetValue<string>());
    }

    // ---- the station column (RV.142): read when present, absent when blank ----

    [Fact]
    public void BlankStationColumn_LeavesNoStationOnTheCandidate()
    {
        // The synthetic RU row with its `Азс` value cleared: a blank station
        // column must stay absent (null), never become an empty string or a
        // guessed name.
        const string row =
            "\"491206.0\",\"2025-08-02 06:55:11\",\"Бензин АИ92\",\"220\",\"6630\",\"30.136\",\"Да\",\"\",\"0\",\"0\",\"0\",\"Нет\",\"\",\"0\",\"0\",\"0\",\"Нет\",\"6,414 л/100км\",\"585.0\",\"\",\"\",\"\",\"\",\"\",\"driver-1\",\"\",\"\",\"\",\"0\"";
        using var stream = File(RussianRefuellingHeader, row);
        var candidate = Assert.Single(DrivvoParser.Parse(stream, CancellationToken.None).Candidates);

        Assert.Null(candidate["station"]);
    }

    [Fact]
    public void RealFile_NamedExpenseAndServiceRows_MapToTheirKinds()
    {
        using var stream = DrivvoFixture.Open(DrivvoFixture.ThreeSectionsCsv);
        var result = DrivvoParser.Parse(stream, CancellationToken.None);

        // A named expense: "490500.0","2025-07-06 10:53:07","6800","Техосмотр".
        var expense = result.Candidates
            .Where(c => c["entityType"]!.GetValue<string>() == "expense")
            .Single(c => c["money"]!["amount"]!.GetValue<string>() == "6800");
        Assert.Equal("2025-07-06T10:53:07Z", expense["date"]!.GetValue<string>());
        Assert.Equal(490500, expense["odometer"]!.GetValue<int>());
        // The kind is not in the canonical map, so it passes through as the tag.
        Assert.Equal("Техосмотр", expense["category"]!["tag"]!.GetValue<string>());

        // A named service: "490983.0","2025-07-19 15:46:49","19000","Замена масла".
        var service = result.Candidates
            .Where(c => c["entityType"]!.GetValue<string>() == "serviceRecord")
            .Single(c => c["money"]!["amount"]!.GetValue<string>() == "19000");
        Assert.Equal("2025-07-19T15:46:49Z", service["date"]!.GetValue<string>());
        Assert.Equal("oil", service["items"]![0]!["category"]!["tag"]!.GetValue<string>());
        Assert.Equal("19000", service["items"]![0]!["cost"]!["amount"]!.GetValue<string>());
    }

    // ---- hazard 1 (the malformed header) is exercised by every parse above --
    // ---- hazard 2: the repeated "Цена / л" must not read the third block -----

    [Fact]
    public void RepeatedPriceHeader_PrimaryBlockPriceIsRead_NotTheThirdBlock()
    {
        // The three fuel blocks each carry a "Цена / л" column. A header-keyed
        // dictionary would collapse them to the LAST occurrence and read the
        // third block's price as the fill's. The parser maps the FIRST
        // occurrence (the primary block): primary price 55, second 60, third 70.
        const string row =
            "\"491791.0\",\"2025-08-24 17:37:33\",\"Бензин АИ92\",\"55\",\"6630\",\"30.136\",\"Да\",\"\",\"60\",\"0\",\"0\",\"Нет\",\"\",\"70\",\"0\",\"0\",\"Нет\",\"6,414 л/100км\",\"585.0\",\"\",\"\",\"\",\"\",\"Газпром\",\"driver-1\",\"\",\"\",\"\",\"0\"";
        using var stream = File(RussianRefuellingHeader, row);
        var result = DrivvoParser.Parse(stream, CancellationToken.None);

        var candidate = Assert.Single(result.Candidates);
        Assert.Equal("55", candidate["unitPrice"]!.GetValue<string>());
        Assert.Equal("6630", candidate["money"]!["amount"]!.GetValue<string>());
        Assert.Equal(30.136, candidate["volumeL"]!.GetValue<double>(), 6);
    }

    // ---- the date is asserted as a VALUE, never "did not throw" (RV.103) -----

    [Fact]
    public void ParsedDate_EqualsTheExpectedInstant()
    {
        using var stream = File(RussianRefuellingHeader, RussianRow);
        var result = DrivvoParser.Parse(stream, CancellationToken.None);

        // yyyy-MM-dd HH:mm:ss (a space, not ISO-8601 'T') reads as UTC.
        Assert.Equal("2025-08-02T06:55:11Z", result.Candidates[0]["date"]!.GetValue<string>());
    }

    // ---- mixed decimals: a comma and a dot both parse; the suffix is not read

    [Fact]
    public void CommaAndDotDecimals_BothParse()
    {
        // A comma-decimal total and a dot-decimal volume in the same row, with
        // the consumption cell (also comma-decimal, with a unit suffix) beside
        // them.
        const string row =
            "\"491206.0\",\"2025-08-02 06:55:11\",\"Бензин АИ92\",\"220\",\"6,414\",\"30.136\",\"Да\",\"\",\"0\",\"0\",\"0\",\"Нет\",\"\",\"0\",\"0\",\"0\",\"Нет\",\"6,414 л/100км\",\"585.0\",\"\",\"\",\"\",\"\",\"Газпром\",\"driver-1\",\"\",\"\",\"\",\"0\"";
        using var stream = File(RussianRefuellingHeader, row);
        var result = DrivvoParser.Parse(stream, CancellationToken.None);

        var candidate = Assert.Single(result.Candidates);
        // The comma-decimal total read as 6.414, and the consumption cell (which
        // also carries a comma) stayed in its own field without shifting the
        // volume or total.
        Assert.Equal("6.414", candidate["money"]!["amount"]!.GetValue<string>());
        Assert.Equal(30.136, candidate["volumeL"]!.GetValue<double>(), 6);
    }

    // ---- "0.0" odometer maps to null, never a zero reading ------------------

    [Fact]
    public void ZeroOdometer_MapsToNull_NotZero()
    {
        using var stream = DrivvoFixture.Open(DrivvoFixture.ThreeSectionsCsv);
        var result = DrivvoParser.Parse(stream, CancellationToken.None);

        // The expense row "0.0","2025-06-08 05:35:00","19827","Страхование".
        var candidate = result.Candidates
            .Where(c => c["entityType"]!.GetValue<string>() == "expense")
            .Single(c => c["money"]!["amount"]!.GetValue<string>() == "19827");
        Assert.Null(candidate["odometer"]);

        // A non-zero odometer elsewhere still reads as a number.
        var withOdometer = result.Candidates
            .Where(c => c["entityType"]!.GetValue<string>() == "expense")
            .Single(c => c["money"]!["amount"]!.GetValue<string>() == "6800");
        Assert.Equal(490500, withOdometer["odometer"]!.GetValue<int>());
    }

    // ---- no currency column: the answer is asked, never a hardcoded default --

    [Fact]
    public void NoCurrencyColumn_CandidatesCarryEmptyCurrency_AndTheCurrencyQuestion()
    {
        using var stream = DrivvoFixture.Open(DrivvoFixture.ThreeSectionsCsv);
        var result = DrivvoParser.Parse(stream, CancellationToken.None);

        // Every money-carrying candidate's currency is empty - the amount rides
        // alone and the wizard asks (hard rule 3, hard rule 13). No candidate
        // carries a guessed default.
        var moneyCandidates = result.Candidates.Where(c => c["money"] is JsonObject).ToList();
        Assert.NotEmpty(moneyCandidates);
        Assert.All(moneyCandidates, c =>
            Assert.Equal("", c["money"]!["currency"]!.GetValue<string>()));

        // The currency question is returned with EMPTY options (there is no
        // answer on disk to declare) so the client asks rather than guesses.
        var currency = Assert.Single(result.Ambiguities, a => a.Kind == "currency");
        Assert.Empty(currency.Options);
        Assert.Equal(moneyCandidates.Count, currency.RowCount);
    }

    // ---- RU and EN headers map to the same canonical fields ------------------

    [Fact]
    public void RuAndEnHeaders_MapToTheSameCanonicalFields()
    {
        var ru = Parse(RussianRefuellingHeader, RussianRow);
        var en = Parse(EnglishRefuellingHeader, EnglishRow);

        Assert.Equal(ru["date"]!.GetValue<string>(), en["date"]!.GetValue<string>());
        Assert.Equal(ru["odometer"]!.GetValue<int>(), en["odometer"]!.GetValue<int>());
        Assert.Equal(ru["volumeL"]!.GetValue<double>(), en["volumeL"]!.GetValue<double>(), 6);
        Assert.Equal(ru["unitPrice"]!.GetValue<string>(), en["unitPrice"]!.GetValue<string>());
        Assert.Equal(ru["money"]!["amount"]!.GetValue<string>(), en["money"]!["amount"]!.GetValue<string>());
        Assert.Equal(ru["fuelKind"]!.GetValue<string>(), en["fuelKind"]!.GetValue<string>());
        Assert.Equal(ru["isFull"]!.GetValue<bool>(), en["isFull"]!.GetValue<bool>());
        // The station is free text, not a canonical value: each language row
        // reads its OWN column (`Азс`/`Gas station` -> `station`, RV.142).
        Assert.Equal("Газпром", ru["station"]!.GetValue<string>());
        Assert.Equal("Gazprom", en["station"]!.GetValue<string>());
    }

    // ---- RV.116: the unsupported columns and their per-file counts -----------

    /// <summary>
    /// The real export's driver column: 110 refuelling + 6 expense + 23 service
    /// rows carry one (139 total). The discount column is "0" on every row -
    /// absence, not a value - so it is omitted; the second/third fuel and EV
    /// columns are empty on a liquid fill and are omitted too.
    /// </summary>
    [Fact]
    public void RealFile_ReportsTheDriverColumnWithItsNonEmptyRowCount()
    {
        using var stream = DrivvoFixture.Open(DrivvoFixture.ThreeSectionsCsv);
        var result = DrivvoParser.Parse(stream, CancellationToken.None);

        var driver = Assert.Single(result.Unsupported, c => c.Column == "Driver");
        Assert.Equal(139, driver.RowCount);
        Assert.DoesNotContain(result.Unsupported, c => c.Column == "Discount");
        Assert.DoesNotContain(result.Unsupported, c => c.Column == "Second fuel");
        Assert.DoesNotContain(result.Unsupported, c => c.Column == "Charge type");
    }

    /// <summary>
    /// The count is arithmetic on a file the test controls: driver on rows 1 and
    /// 3 (2), a real discount on row 1 (1), payment method on row 2 (1). A count
    /// forced from this fixture cannot be a guess.
    /// </summary>
    [Fact]
    public void UnsupportedColumns_ReportOnlyTheRowsThatCarriedAValue()
    {
        using var file = RefuellingFile(
            RefuellingRow(driver: "driver-a", discount: "500", payment: ""),
            RefuellingRow(driver: "", discount: "0", payment: "card"),
            RefuellingRow(driver: "driver-b", discount: "0", payment: ""));

        var result = DrivvoParser.Parse(file, CancellationToken.None);

        // Declared order, and only the non-empty columns appear.
        Assert.Collection(result.Unsupported,
            c => { Assert.Equal("Driver", c.Column); Assert.Equal(2, c.RowCount); },
            c => { Assert.Equal("Payment method", c.Column); Assert.Equal(1, c.RowCount); },
            c => { Assert.Equal("Discount", c.Column); Assert.Equal(1, c.RowCount); });
    }

    /// <summary>A column empty in every row is omitted - the decision this task made.</summary>
    [Fact]
    public void UnsupportedColumns_EmptyInEveryRow_AreOmitted()
    {
        using var file = RefuellingFile(
            RefuellingRow(driver: "driver-a", discount: "0", payment: ""),
            RefuellingRow(driver: "driver-b", discount: "0", payment: ""));

        var result = DrivvoParser.Parse(file, CancellationToken.None);

        var driver = Assert.Single(result.Unsupported);
        Assert.Equal("Driver", driver.Column);
        Assert.Equal(2, driver.RowCount);
        Assert.DoesNotContain(result.Unsupported, c => c.Column == "Payment method");
        Assert.DoesNotContain(result.Unsupported, c => c.Column == "Discount");
    }

    // ---- the 422 path -------------------------------------------------------

    [Fact]
    public void AFileThatIsNotADrivvoExport_ThrowsThe422Exception()
    {
        using var stream = new MemoryStream(Encoding.UTF8.GetBytes("date,volume,price\n1,2,3\n"));
        var ex = Assert.Throws<NotDrivvoExportException>(() => DrivvoParser.Parse(stream, CancellationToken.None));
        Assert.Contains("Drivvo", ex.Detail, StringComparison.Ordinal);
    }

    // ---- helpers -----------------------------------------------------------

    private static int Count(MfmParseResult result, string entityType)
        => result.Candidates.Count(c => c["entityType"]!.GetValue<string>() == entityType);

    private static JsonObject Parse(string header, string dataRow)
    {
        using var stream = File(header, dataRow);
        return DrivvoParser.Parse(stream, CancellationToken.None).Candidates[0];
    }

    /// <summary>A synthetic Drivvo refuelling file: the ##Refuelling marker, the header, one data row.</summary>
    private static Stream File(string header, params string[] dataRows)
    {
        var sb = new StringBuilder();
        sb.AppendLine("##Refuelling");
        sb.AppendLine(header);
        foreach (var row in dataRows)
        {
            sb.AppendLine(row);
        }

        return new MemoryStream(Encoding.UTF8.GetBytes(sb.ToString()));
    }

    /// <summary>The real RU header plus the supplied refuelling rows (RV.116 tests).</summary>
    private static Stream RefuellingFile(params string[] rows)
    {
        var sb = new StringBuilder();
        sb.AppendLine("##Refuelling");
        sb.AppendLine(RussianRefuellingHeader);
        foreach (var row in rows)
        {
            sb.AppendLine(row);
        }

        return new MemoryStream(Encoding.UTF8.GetBytes(sb.ToString()));
    }

    /// <summary>
    /// One full 29-column RU refuelling row with the three unsupported cells the
    /// RV.116 tests vary. Every other unsupported cell stays empty.
    /// </summary>
    private static string RefuellingRow(string driver, string discount, string payment)
    {
        var fields = new[]
        {
            "491206.0", "2025-08-02 06:55:11", "Бензин АИ92", "220", "6630", "30.136", "Да",
            "", "0", "0", "0", "Нет", "", "0", "0", "0", "Нет",
            "6,414 л/100км", "585.0", "", "", "", "", "Газпром",
            driver, "", payment, "", discount,
        };
        return string.Join(",", fields.Select(f => $"\"{f}\""));
    }

    // The real RU header and one real RU data row.
    private const string RussianRefuellingHeader =
        "\"Одометр (км)\",\"Дата\",\"Топливо\",\"Цена / л\",\"Общая стоимость\",\"Объем\",\"Полный бак\",\"Второе топливо\",\"Цена / л\",\"Общая стоимость\",\"Объем\",\"Полный бак\" 2,\"Третье топливо\",\"Цена / л\",\"Общая стоимость\",\"Объем\",\"Полный бак\" 3,\"Эффективный расход топлива\",\"Расстояние\",\"Тип зарядки\",\"Начальный заряд (%)\",\"Конечный заряд (%)\",\"Длительность (мин)\",\"Азс\",\"Водитель\",\"Тип расхода\",\"Метод оплаты\",\"Примечание\",\"Скидка\"";

    private const string RussianRow =
        "\"491206.0\",\"2025-08-02 06:55:11\",\"Бензин АИ92\",\"220\",\"6630\",\"30.136\",\"Да\",\"\",\"0\",\"0\",\"0\",\"Нет\",\"\",\"0\",\"0\",\"0\",\"Нет\",\"6,414 л/100км\",\"585.0\",\"\",\"\",\"\",\"\",\"Газпром\",\"driver-ea23167db8ec\",\"\",\"\",\"\",\"0\"";

    // The derived EN header and row (UNVERIFIED against a real English file).
    private const string EnglishRefuellingHeader =
        "\"Odometer (km)\",\"Date\",\"Fuel\",\"Price / l\",\"Total cost\",\"Volume\",\"Full tank\",\"Second fuel\",\"Price / l\",\"Total cost\",\"Volume\",\"Full tank\" 2,\"Third fuel\",\"Price / l\",\"Total cost\",\"Volume\",\"Full tank\" 3,\"Effective fuel consumption\",\"Distance\",\"Charging type\",\"Start charge (%)\",\"End charge (%)\",\"Duration (min)\",\"Gas station\",\"Driver\",\"Expense type\",\"Payment method\",\"Note\",\"Discount\"";

    private const string EnglishRow =
        "\"491206.0\",\"2025-08-02 06:55:11\",\"Petrol 92\",\"220\",\"6630\",\"30.136\",\"Yes\",\"\",\"0\",\"0\",\"0\",\"No\",\"\",\"0\",\"0\",\"0\",\"No\",\"6,414 l/100km\",\"585.0\",\"\",\"\",\"\",\"\",\"Gazprom\",\"driver-1\",\"\",\"\",\"\",\"0\"";
}

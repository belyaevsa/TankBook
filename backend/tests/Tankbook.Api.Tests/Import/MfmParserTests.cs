using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Tankbook.Api.Import;

namespace Tankbook.Api.Tests.Import;

/// <summary>
/// The parser against the committed real export (Spike/ImportFixtures/mfm/).
/// docs/API.md "Import parsing": the parser is a pure function - candidates are
/// proposals, nothing is committed. docs/TESTING.md: assert field VALUES on a
/// named row, never just a count.
/// </summary>
public class MfmParserTests
{
    // ---- fuel.csv: 513 rows, header on line 2, ';' delimiter ---------------

    [Fact]
    public void FuelCsv_ParsesAlone_WithHeaderOnLine2AndSemicolonDelimiter()
    {
        using var stream = MfmFixture.Open(MfmFixture.FuelCsv);
        var result = MfmParser.Parse(stream, CancellationToken.None);

        // The title (line 1) is not a header and the ';' delimiter is honoured:
        // all 513 data rows land, each as one candidate.
        Assert.Equal("fuel", result.FileKind);
        Assert.Equal(513, result.DataRowCount);
        Assert.Equal(513, result.Candidates.Count);
        Assert.Empty(result.Unparsed);
    }

    [Fact]
    public void FuelCsv_NamedRow_FirstDataRowMapsEveryField()
    {
        using var stream = MfmFixture.Open(MfmFixture.FuelCsv);
        var result = MfmParser.Parse(stream, CancellationToken.None);

        // The named row: the first data row of the export
        //   8/24/2026;67;121727;125.22;USD;2;F;100;"";"Volvo"
        var candidate = result.Candidates[0];

        Assert.Equal("2026-08-24T00:00:00Z", candidate["date"]!.GetValue<string>());
        Assert.Equal(121727, candidate["odometer"]!.GetValue<int>());
        Assert.Equal(67.0, candidate["volumeL"]!.GetValue<double>(), 6);
        Assert.Equal("125.22", candidate["money"]!["amount"]!.GetValue<string>());
        Assert.Equal("USD", candidate["money"]!["currency"]!.GetValue<string>());
        Assert.Equal("diesel", candidate["fuelKind"]!.GetValue<string>());
        Assert.True(candidate["isFull"]!.GetValue<bool>());
        Assert.Equal(100.0, candidate["tankLevelAfterPct"]!.GetValue<double>(), 6);
        Assert.True(candidate["note"] is null);
        Assert.Equal("Volvo", candidate["vehicleName"]!.GetValue<string>());
        Assert.Equal("import", candidate["provenance"]!["tag"]!.GetValue<string>());
        Assert.Equal("mfm", candidate["provenance"]!["source"]!.GetValue<string>());
    }

    // ---- the odometer defect survives --------------------------------------

    [Fact]
    public void FuelCsv_OdometerDefectSurvives_NeitherDroppedNorRepaired()
    {
        using var stream = MfmFixture.Open(MfmFixture.FuelCsv);
        var result = MfmParser.Parse(stream, CancellationToken.None);

        // The fixture's most valuable row: a real typo reading odometer 9.
        //   datarow 39: 4/14/2025;68;9;97.85;USD;2;F;0;"";"Volvo"
        var defect = result.Candidates.Single(c => c["odometer"]!.GetValue<int>() == 9);
        Assert.Equal(9, defect["odometer"]!.GetValue<int>());
        Assert.Equal("2025-04-14T00:00:00Z", defect["date"]!.GetValue<string>());
        Assert.Equal(68.0, defect["volumeL"]!.GetValue<double>(), 6);
        Assert.Equal("97.85", defect["money"]!["amount"]!.GetValue<string>());
        Assert.Equal("Volvo", defect["vehicleName"]!.GetValue<string>());
        Assert.True(defect["isFull"]!.GetValue<bool>());

        // And the 11436 row is present too, unmodified.
        Assert.Contains(result.Candidates, c => c["odometer"]!.GetValue<int>() == 11436);

        // The fixture also carries a decimal odometer (datarow 116 reads 3.22),
        // which MFM exports with a fractional part and Tankbook stores as whole
        // km. It must survive as a mapped value, not vanish: rounded to 3 and
        // still glaringly off the car's timeline.
        var decimalOdometer = result.Candidates.SingleOrDefault(c => c["odometer"]!.GetValue<int>() == 3);
        Assert.NotNull(decimalOdometer);
        Assert.Equal(116, decimalOdometer!["sourceRow"]!.GetValue<int>());
    }

    // ---- date ambiguity is reported, never resolved ------------------------

    [Fact]
    public void FuelCsv_DateAmbiguityIsReported_WithTheCountOfGenuinelyAmbiguousRows()
    {
        using var stream = MfmFixture.Open(MfmFixture.FuelCsv);
        var result = MfmParser.Parse(stream, CancellationToken.None);

        var dateFormat = Assert.Single(result.Ambiguities, a => a.Kind == "dateFormat");
        Assert.Equal(["M/D/YYYY", "D/M/YYYY"], dateFormat.Options);

        // The count is recounted independently here from the raw file: a row is
        // genuinely ambiguous when its day is also <= 12, so the same string
        // would parse as D/M/YYYY.
        var rows = MfmFixture.ReadDataRows(MfmFixture.FuelCsv);
        var expectedAmbiguous = rows.Count(r => int.Parse(r[0].Split('/')[1], System.Globalization.CultureInfo.InvariantCulture) <= 12);
        Assert.Equal(expectedAmbiguous, dateFormat.RowCount);
        Assert.Equal(215, dateFormat.RowCount);
    }

    [Fact]
    public void FuelCsv_NoCandidateCarriesAGuessedDate()
    {
        using var stream = MfmFixture.Open(MfmFixture.FuelCsv);
        var result = MfmParser.Parse(stream, CancellationToken.None);

        // Every candidate's date must be the M/D/YYYY reading of its source row,
        // including the genuinely ambiguous ones - never the D/M swap. The
        // parser applied one convention and surfaced the rest in `ambiguities`.
        var rows = MfmFixture.ReadDataRows(MfmFixture.FuelCsv);
        foreach (var candidate in result.Candidates)
        {
            var sourceRow = candidate["sourceRow"]!.GetValue<int>();
            var raw = rows[sourceRow - 1][0];
            var expected = ParseMdy(raw);
            var actual = candidate["date"]!.GetValue<string>();
            Assert.Equal(expected, actual);
        }

        // The named ambiguous row that would flip: datarow 5 "8/9/2026" must
        // read August 9, 2026 (M/D), never September 8 (the D/M swap).
        var row5 = result.Candidates.Single(c => c["sourceRow"]!.GetValue<int>() == 5);
        Assert.Equal("2026-08-09T00:00:00Z", row5["date"]!.GetValue<string>());
    }

    // ---- currency is a reported default, never a fact ----------------------

    [Fact]
    public void FuelCsv_CurrencyIsReportedAsADefault_NotAssertedAsFact()
    {
        using var stream = MfmFixture.Open(MfmFixture.FuelCsv);
        var result = MfmParser.Parse(stream, CancellationToken.None);

        // The file reads USD on every row regardless of where fuel was bought,
        // so it surfaces as a once-per-file default the client can override
        // (hard rule 13, the F6 currency question) - never a fact.
        var currency = Assert.Single(result.Ambiguities, a => a.Kind == "currency");
        Assert.Equal(["USD"], currency.Options);
        Assert.Equal(513, currency.RowCount);
    }

    // ---- price per litre is derived ----------------------------------------

    [Fact]
    public void FuelCsv_UnitPriceIsDerivedFromTotalOverVolume_OnANamedRow()
    {
        using var stream = MfmFixture.Open(MfmFixture.FuelCsv);
        var result = MfmParser.Parse(stream, CancellationToken.None);

        // There is no unit-price column; the figure is derived. Row 1:
        //   125.22 USD / 67 L = 1.8689552... -> rounded to 6 dp.
        var candidate = result.Candidates[0];
        Assert.Equal("1.868955", candidate["unitPrice"]!.GetValue<string>());
    }

    // ---- costs / vehicles / incomes ----------------------------------------

    [Fact]
    public void CostsCsv_ParsesToServiceRecordAndExpenseShapes()
    {
        using var stream = MfmFixture.Open(MfmFixture.CostsCsv);
        var result = MfmParser.Parse(stream, CancellationToken.None);

        Assert.Equal("costs", result.FileKind);
        Assert.Equal(260, result.DataRowCount);
        Assert.Equal(260, result.Candidates.Count);

        // Named row 1: "Replacement parts" -> Expense(.parts).
        //   4/27/2026;133;USD;"Replacement parts";106722;"Замена колес зима -> лето";"Volvo"
        var first = result.Candidates[0];
        Assert.Equal("expense", first["entityType"]!.GetValue<string>());
        Assert.Equal("2026-04-27T00:00:00Z", first["date"]!.GetValue<string>());
        Assert.Equal(106722, first["odometer"]!.GetValue<int>());
        Assert.Equal("133", first["money"]!["amount"]!.GetValue<string>());
        Assert.Equal("parts", first["category"]!["tag"]!.GetValue<string>());
        Assert.Equal("Замена колес зима -> лето", first["title"]!.GetValue<string>());

        // A WORK row -> ServiceRecord with a single item.
        var work = result.Candidates.Single(c => c["entityType"]!.GetValue<string>() == "serviceRecord"
            && c["odometer"]?.GetValue<int>() == 98660);
        Assert.Equal("repair", work["items"]![0]!["category"]!["tag"]!.GetValue<string>());
        Assert.Equal("Changed transmission oil. Next time after 60-80k", work["items"]![0]!["title"]!.GetValue<string>());

        // Categories present in the real file all map; nothing lands unparsed.
        Assert.Empty(result.Unparsed);

        // The costs file has its own date-format ambiguity (dates are M/D/YYYY too).
        Assert.Contains(result.Ambiguities, a => a.Kind == "dateFormat" && a.RowCount > 0);
    }

    [Fact]
    public void VehiclesCsv_ParsesToVehicleShape()
    {
        using var stream = MfmFixture.Open(MfmFixture.VehiclesCsv);
        var result = MfmParser.Parse(stream, CancellationToken.None);

        Assert.Equal("vehicles", result.FileKind);
        Assert.Equal(5, result.DataRowCount);
        Assert.Equal(5, result.Candidates.Count);

        // Named row: the LADA. 00100001 = petrol bit only -> a petrol fuel kind.
        var lada = result.Candidates.Single(c => c["name"]!.GetValue<string>().StartsWith("LADA", StringComparison.Ordinal));
        Assert.Equal("vehicle", lada["entityType"]!.GetValue<string>());
        Assert.Equal("CC222CC", lada["plate"]!.GetValue<string>());
        Assert.Equal(2003, lada["year"]!.GetValue<int>());
        Assert.Equal(190700, lada["initialOdometer"]!.GetValue<int>());
        Assert.Equal(42.0, lada["tankCapacityL"]!.GetValue<double>(), 6);
        Assert.Equal("ice", lada["powertrain"]!.GetValue<string>());
        Assert.Equal(new[] { "petrol95" }, lada["fuelKinds"]!.AsArray().Select(k => k!.GetValue<string>()).ToArray());

        // A diesel car (00100003 = petrol+diesel bits): the fill-ups say diesel,
        // so the offer set is a default the user corrects - never hidden.
        var volvo = result.Candidates.Single(c => c["name"]!.GetValue<string>() == "Volvo");
        Assert.Equal(71449, volvo["initialOdometer"]!.GetValue<int>());
        Assert.Equal(2020, volvo["year"]!.GetValue<int>());
        Assert.Equal(new[] { "petrol95", "diesel" }, volvo["fuelKinds"]!.AsArray().Select(k => k!.GetValue<string>()).ToArray());

        Assert.Empty(result.Unparsed);
    }

    [Fact]
    public void IncomesCsv_IsAccepted_AndYieldsNothingRatherThanErroring()
    {
        using var stream = MfmFixture.Open(MfmFixture.IncomesCsv);
        var result = MfmParser.Parse(stream, CancellationToken.None);

        Assert.Equal("incomes", result.FileKind);
        Assert.Empty(result.Candidates);
        Assert.Empty(result.Unparsed);
        Assert.Equal(1, result.DataRowCount);
        Assert.Contains(result.Ambiguities, a => a.Kind == "outOfScope" && a.Options.Contains("income") && a.RowCount == 1);
    }

    [Fact]
    public void RemindersCsv_IsAccepted_AndYieldsNothing()
    {
        using var stream = MfmFixture.Open(MfmFixture.RemindersCsv);
        var result = MfmParser.Parse(stream, CancellationToken.None);

        Assert.Equal("reminders", result.FileKind);
        Assert.Empty(result.Candidates);
        Assert.Empty(result.Unparsed);
        Assert.Contains(result.Ambiguities, a => a.Kind == "outOfScope" && a.Options.Contains("reminder"));
    }

    // ---- corrupted rows land in unparsed; the rest still parse -------------

    [Fact]
    public void FuelCsv_ACorruptedRowLandsInUnparsed_AndTheRestStillParse()
    {
        // The committed export with ONE data row corrupted (an invalid date on
        // data row 3). This is not a synthetic CSV - it is the real file with a
        // defect injected, which is what the partial-import rule exists for.
        var lines = Encoding.UTF8.GetString(MfmFixture.ReadAllBytes(MfmFixture.FuelCsv))
            .Split('\n', StringSplitOptions.RemoveEmptyEntries);
        // Physical line 5 = data row 3.
        lines[4] = "bad-date;64;119486;110;USD;2;F;100;\"\";\"Volvo\"";

        using var stream = new MemoryStream(Encoding.UTF8.GetBytes(string.Join('\n', lines)));
        var result = MfmParser.Parse(stream, CancellationToken.None);

        // Half one: the bad row is reported with a reason, never swallowed.
        var bad = Assert.Single(result.Unparsed);
        Assert.Equal(3, bad.Row);
        Assert.Equal(MfmParser.ReasonInvalidDate, bad.Reason);

        // Half two: the other 512 rows still parse - an implementation that
        // fails the whole file on one bad row fails this assertion.
        Assert.Equal(512, result.Candidates.Count);
        Assert.Equal(513, result.DataRowCount);

        // And the odometer defect row is still there, undamaged by the edit.
        Assert.Contains(result.Candidates, c => c["odometer"]!.GetValue<int>() == 9);
    }

    [Fact]
    public void AFileThatIsNotAnMfmExport_ThrowsThe422Exception()
    {
        using var stream = new MemoryStream(Encoding.UTF8.GetBytes("date,volume,price\n1,2,3\n"));
        var ex = Assert.Throws<NotMfmExportException>(() => MfmParser.Parse(stream, CancellationToken.None));
        Assert.Contains("My Fuel Manager", ex.Detail, StringComparison.Ordinal);
    }

    [Fact]
    public void AnMfmTitleWithAWrongHeader_ThrowsThe422Exception()
    {
        using var stream = new MemoryStream(Encoding.UTF8.GetBytes(
            "My Fuel Manager - Fuel\nWrong;Header;Here\n1;2;3\n"));
        Assert.Throws<NotMfmExportException>(() => MfmParser.Parse(stream, CancellationToken.None));
    }

    // ---- helpers -----------------------------------------------------------

    private static string ParseMdy(string text)
    {
        var parts = text.Split('/');
        var year = int.Parse(parts[2], System.Globalization.CultureInfo.InvariantCulture);
        var month = int.Parse(parts[0], System.Globalization.CultureInfo.InvariantCulture);
        var day = int.Parse(parts[1], System.Globalization.CultureInfo.InvariantCulture);
        return new DateTime(year, month, day, 0, 0, 0, DateTimeKind.Utc)
            .ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", System.Globalization.CultureInfo.InvariantCulture);
    }
}

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

    // ---- the date order is decided from the WHOLE file (RV.85) ------------

    [Fact]
    public void FuelCsv_ProvesMdy_SoTheFileDoesNotAsk()
    {
        using var stream = MfmFixture.Open(MfmFixture.FuelCsv);
        var result = MfmParser.Parse(stream, CancellationToken.None);

        // The real export is month-first: rows carry days past the 12th
        // (8/24/2026, 6/26/2026), which only M/D can read - so the file proves
        // M/D and the dateFormat question is gone from the wire. It used to ask
        // whenever ANY row had a day <= 12 - here 215 of 513 individually
        // ambiguous rows, answered by the file itself.
        Assert.DoesNotContain(result.Ambiguities, a => a.Kind == "dateFormat");

        // And the resolution reaches the individually ambiguous rows: the named
        // row 8/9/2026 (day 9, would read either way) still reads August 9 -
        // M/D, the order the file proved - never September 8 (the D/M swap).
        var row = result.Candidates.Single(c => c["sourceRow"]!.GetValue<int>() == 5);
        Assert.Equal("2026-08-09T00:00:00Z", row["date"]!.GetValue<string>());
    }

    [Fact]
    public void FuelCsv_ProvingMdy_AppliesTheProvenOrderToEveryRow()
    {
        using var stream = MfmFixture.Open(MfmFixture.FuelCsv);
        var result = MfmParser.Parse(stream, CancellationToken.None);

        // Not just "no question": every candidate must carry the M/D reading of
        // its source row, including the individually ambiguous ones. A parser
        // that dropped the question and guessed the OTHER order would pass a
        // no-question assertion alone - the dates are the half that matters.
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

    // ---- a file a single row proves resolves, and does not ask ------------

    [Fact]
    public void OneDmyOnlyRowAmongAmbiguousOnes_ResolvesEveryRowAsDmy_AndDoesNotAsk()
    {
        // The mirror of the measured defect: a genuinely D/M file. One row only
        // D/M can read (13/05/2024) settles the order for the other twenty,
        // whose dates would read either way. The proof row sits LAST, so a
        // parser that decided from the first row alone would miss it - the
        // whole-file decision is what resolves this file. Before RV.85 the
        // 13/05 row was INVALID under the parser's M/D convention (landed
        // unparsed) and the twenty ambiguous ones raised a question the file
        // already answered.
        var dates = Enumerable.Repeat("02/03/2024", 20).Append("13/05/2024");

        using var stream = new MemoryStream(Encoding.UTF8.GetBytes(FuelCsv(dates)));
        var result = MfmParser.Parse(stream, CancellationToken.None);

        // No dateFormat ambiguity: the file proved D/M.
        Assert.DoesNotContain(result.Ambiguities, a => a.Kind == "dateFormat");
        Assert.Empty(result.Unparsed);

        // The proof is applied to EVERY row, and the dates prove it: the
        // decidable row (sourceRow 21) reads 13 May 2024, and each ambiguous
        // row reads day-first too (02/03 -> 2 March 2024), never the M/D
        // "3 February".
        Assert.Equal(21, result.Candidates.Count);
        var proof = result.Candidates.Single(c => c["sourceRow"]!.GetValue<int>() == 21);
        Assert.Equal("2024-05-13T00:00:00Z", proof["date"]!.GetValue<string>());
        foreach (var candidate in result.Candidates.Where(c => c["sourceRow"]!.GetValue<int>() < 21))
        {
            var sourceRow = candidate["sourceRow"]!.GetValue<int>();
            Assert.True(candidate["date"]!.GetValue<string>() == "2024-03-02T00:00:00Z",
                $"data row {sourceRow} must carry the D/M reading of 02/03/2024");
        }
    }

    [Fact]
    public void OneMdyOnlyRowAmongAmbiguousOnes_ResolvesEveryRowAsMdy_AndDoesNotAsk()
    {
        // The measured owner's export in miniature: a month-first file whose
        // proof row (05/13/2024, only M/D can read it) settles the twenty
        // ambiguous rows - proof row LAST again, so only a whole-file decision
        // catches it. No question, and every date keeps the M/D reading.
        var dates = Enumerable.Repeat("02/03/2024", 20).Append("05/13/2024");

        using var stream = new MemoryStream(Encoding.UTF8.GetBytes(FuelCsv(dates)));
        var result = MfmParser.Parse(stream, CancellationToken.None);

        Assert.DoesNotContain(result.Ambiguities, a => a.Kind == "dateFormat");
        Assert.Empty(result.Unparsed);
        Assert.Equal(21, result.Candidates.Count);

        var proof = result.Candidates.Single(c => c["sourceRow"]!.GetValue<int>() == 21);
        Assert.Equal("2024-05-13T00:00:00Z", proof["date"]!.GetValue<string>());
        foreach (var candidate in result.Candidates.Where(c => c["sourceRow"]!.GetValue<int>() < 21))
        {
            var sourceRow = candidate["sourceRow"]!.GetValue<int>();
            Assert.True(candidate["date"]!.GetValue<string>() == "2024-02-03T00:00:00Z",
                $"data row {sourceRow} must carry the M/D reading of 02/03/2024");
        }
    }

    [Fact]
    public void ARowOnlyDayFirstCanRead_ProvesDmy_ForTheWholeFile()
    {
        // The single-row proof at its smallest: one 13/05 row and nothing else
        // proves the file D/M - there is no question to ask and the one row the
        // old parser could not read at all now maps.
        using var stream = new MemoryStream(Encoding.UTF8.GetBytes(FuelCsv(["13/05/2024"])));
        var result = MfmParser.Parse(stream, CancellationToken.None);

        Assert.DoesNotContain(result.Ambiguities, a => a.Kind == "dateFormat");
        var candidate = Assert.Single(result.Candidates);
        Assert.Equal("2024-05-13T00:00:00Z", candidate["date"]!.GetValue<string>());
        Assert.Empty(result.Unparsed);
    }

    // ---- a file proving both orders is inconsistent, not ambiguous --------

    [Fact]
    public void AFileProvingBothOrders_IsInconsistent_NotAQuestion()
    {
        // One row only D/M can read (13/05) and one only M/D can read (05/13)
        // cannot both be right: one export has one format. This is not the
        // dateFormat ambiguity (no single answer exists for the user to pick),
        // so the parser refuses the file rather than asking a question no
        // answer fits - the whole-file 422, never a dateFormat row.
        using var stream = new MemoryStream(Encoding.UTF8.GetBytes(
            FuelCsv(["13/05/2024", "05/13/2024"])));

        var ex = Assert.Throws<InconsistentDateOrderException>(
            () => MfmParser.Parse(stream, CancellationToken.None));
        Assert.Contains("date order", ex.Detail, StringComparison.OrdinalIgnoreCase);
    }

    // ---- a file nothing settles keeps today's question --------------------

    [Fact]
    public void ANothingDisambiguatesFile_KeepsTheDateFormatQuestion()
    {
        // Every date has both components <= 12, so no row proves which order
        // the file uses and there is no answer on disk to read. The parser
        // keeps exactly the pre-RV.85 behaviour for this file: it parses under
        // the format's M/D convention, reports the ambiguity and lets the user
        // decide - it never guesses silently. (The product owner's "drop it"
        // reading - land these rows unresolved in the review list instead - was
        // NOT confirmed before this build, so it was not implemented.)
        var dates = Enumerable.Repeat("02/03/2024", 3);

        using var stream = new MemoryStream(Encoding.UTF8.GetBytes(FuelCsv(dates)));
        var result = MfmParser.Parse(stream, CancellationToken.None);

        var dateFormat = Assert.Single(result.Ambiguities, a => a.Kind == "dateFormat");
        Assert.Equal(["M/D/YYYY", "D/M/YYYY"], dateFormat.Options);
        Assert.Equal(3, dateFormat.RowCount);

        // And the candidates still carry the M/D reading the question can flip
        // (02/03/2024 -> 3 February 2024), so the client's answer path has a
        // real job to do for this file.
        Assert.Equal(3, result.Candidates.Count);
        Assert.All(result.Candidates, c =>
            Assert.Equal("2024-02-03T00:00:00Z", c["date"]!.GetValue<string>()));
    }

    [Fact]
    public void ACorruptDateRow_IsNoEvidence_AndCannotFlipAResolvedFile()
    {
        // A garbage date ("99/05/2024" - neither order can read day 99) must
        // not count as evidence for either order. In an M/D-proven file it
        // lands in `unparsed` and the file still resolves M/D without asking -
        // a parser that took "first component > 12 proves D/M" at face value
        // would read the corrupt row as a D/M proof and mis-date the whole file.
        var dates = new List<string> { "08/24/2026", "99/05/2024", "06/14/2026" };

        using var stream = new MemoryStream(Encoding.UTF8.GetBytes(FuelCsv(dates)));
        var result = MfmParser.Parse(stream, CancellationToken.None);

        Assert.DoesNotContain(result.Ambiguities, a => a.Kind == "dateFormat");
        Assert.Equal(2, result.Candidates.Count);
        var bad = Assert.Single(result.Unparsed);
        Assert.Equal(2, bad.Row);
        Assert.Equal(MfmParser.ReasonInvalidDate, bad.Reason);

        Assert.Equal("2026-08-24T00:00:00Z",
            result.Candidates.Single(c => c["sourceRow"]!.GetValue<int>() == 1)["date"]!.GetValue<string>());
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

    // ---- RV.86: candidates are grouped by their vehicle name -----------------

    [Fact]
    public void FuelCsv_CandidatesAreGroupedByVehicleName()
    {
        using var stream = MfmFixture.Open(MfmFixture.FuelCsv);
        var result = MfmParser.Parse(stream, CancellationToken.None);

        // The real export holds five cars; the parse must expose them as five
        // ordered groups, each naming the source car and listing the 1-based
        // data rows that belong to it (RV.86 - the device asks the user which
        // cars to bring in rather than silently merging them).
        Assert.Equal(5, result.VehicleGroups.Count);

        var expected = new (string Name, int Count)[]
        {
            ("Volvo", 67),
            ("AUDI A4 Avant 2.0 TDI Komfort - 105.00kW [2009]", 389),
            ("AUDI A6 Avant 2.5 TDI [2002]", 31),
            ("LADA 2110 1.5 16V Komfort [2004]", 8),
            ("NISSAN X-Trail 2.5 Columbia Elegance A/T [2006]", 18),
        };

        for (var i = 0; i < expected.Length; i++)
        {
            var group = result.VehicleGroups[i];
            Assert.Equal(expected[i].Name, group.Name);
            Assert.Equal(expected[i].Count, group.SourceRows.Count);
            foreach (var row in group.SourceRows)
            {
                Assert.Equal(expected[i].Name,
                    result.Candidates.Single(c => c["sourceRow"]!.GetValue<int>() == row)["vehicleName"]!.GetValue<string>());
            }
        }

        // Membership is exhaustive and disjoint: every candidate is in exactly
        // one group, and the row counts sum to the candidate count.
        var allRows = result.VehicleGroups.SelectMany(g => g.SourceRows).ToArray();
        Assert.Equal(result.Candidates.Count, allRows.Length);
        Assert.Equal(allRows.Length, allRows.Distinct().Count());
    }

    [Fact]
    public void SingleNameFile_ReturnsOneGroup()
    {
        // A file whose rows all carry one vehicle name yields exactly one group
        // - the case that must keep today's single-car flow unchanged.
        var csv = """
        My Fuel Manager - Fuel
        Date;Fillup volume;Odometer;Total price;Currency;Fuel;Tank status after fillup;%;Note;Vehicle name
        4/1/2026;50;100000;80;USD;1;F;100;"";"Volvo"
        4/10/2026;45;100400;72;USD;1;F;100;"";"Volvo"
        """;
        using var stream = new MemoryStream(Encoding.UTF8.GetBytes(csv));
        var result = MfmParser.Parse(stream, CancellationToken.None);

        var group = Assert.Single(result.VehicleGroups);
        Assert.Equal("Volvo", group.Name);
        Assert.Equal(new[] { 1, 2 }, group.SourceRows);
        Assert.Equal(2, result.Candidates.Count);
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

        // Named row 1: "Replacement parts" -> ServiceRecord(.parts) (RV.96),
        // with the note surviving as the single item's title.
        //   4/27/2026;133;USD;"Replacement parts";106722;"Замена колес зима -> лето";"Volvo"
        var first = result.Candidates[0];
        Assert.Equal("serviceRecord", first["entityType"]!.GetValue<string>());
        Assert.Equal("2026-04-27T00:00:00Z", first["date"]!.GetValue<string>());
        Assert.Equal(106722, first["odometer"]!.GetValue<int>());
        Assert.Equal("133", first["money"]!["amount"]!.GetValue<string>());
        Assert.Equal("USD", first["money"]!["currency"]!.GetValue<string>());
        Assert.Equal("parts", first["items"]![0]!["category"]!["tag"]!.GetValue<string>());
        Assert.Equal("Замена колес зима -> лето", first["items"]![0]!["title"]!.GetValue<string>());
        Assert.Equal("133", first["items"]![0]!["cost"]!["amount"]!.GetValue<string>());
        Assert.Equal("USD", first["items"]![0]!["cost"]!["currency"]!.GetValue<string>());

        // A WORK row -> ServiceRecord with a single item.
        var work = result.Candidates.Single(c => c["entityType"]!.GetValue<string>() == "serviceRecord"
            && c["odometer"]?.GetValue<int>() == 98660);
        Assert.Equal("repair", work["items"]![0]!["category"]!["tag"]!.GetValue<string>());
        Assert.Equal("Changed transmission oil. Next time after 60-80k", work["items"]![0]!["title"]!.GetValue<string>());

        // Categories present in the real file all map; nothing lands unparsed.
        Assert.Empty(result.Unparsed);

        // The costs file's dates are M/D/YYYY too, and it proves M/D the same
        // way fuel.csv does (rows with days past the 12th) - so RV.85 resolves
        // it and no dateFormat question is asked.
        Assert.DoesNotContain(result.Ambiguities, a => a.Kind == "dateFormat");
    }

    [Fact]
    public void CostsCsv_ReplacementPartsRows_AreServiceRecordsWithParts_NoteAndMoneySurvive()
    {
        using var stream = MfmFixture.Open(MfmFixture.CostsCsv);
        var result = MfmParser.Parse(stream, CancellationToken.None);

        // Four named "Replacement parts" rows of the real file (RV.96), chosen
        // for how little their notes share - suspension parts, AdBlue, a sensor,
        // a filter. A mapper that sniffed the note or handled only part-shaped
        // rows would miss at least one of them, so each is asserted for what it
        // BECAME: a service record whose single item carries the parts category.
        //   Запчасти к подвестке..., 350 евро: 5/4/2022;28000;...;412600
        //   AdBlue 5 литров (еще 4 нужно):     3/27/2025;13.5;...;90691
        //   Датчик воздуха. Взял бу...:        7/11/2023;62.5;...;422178
        //   Фильтр топливный vag 8t0127401a:   10/16/2021;1786;...;0 (odometer 0 -> null)
        var named = new[]
        {
            ("Запчасти к подвестке (смотри фотографию), 350 евро, forss", "28000", 412600),
            ("AdBlue 5 литров (еще 4 нужно)", "13.5", 90691),
            ("Датчик воздуха. Взял бу. 03g 906 4611", "62.5", 422178),
            ("Фильтр топливный vag 8t0127401a", "1786", (int?)null),
        };
        foreach (var (note, amount, odometer) in named)
        {
            var candidate = Assert.Single(result.Candidates, c => FirstItemTitle(c) == note);
            Assert.Equal("serviceRecord", candidate["entityType"]!.GetValue<string>());
            Assert.Equal("parts", candidate["items"]![0]!["category"]!["tag"]!.GetValue<string>());
            // The note IS the value of these rows: it survives as the item title.
            Assert.Equal(note, candidate["items"]![0]!["title"]!.GetValue<string>());
            // The money is unchanged by the remap - same amount and currency on
            // the record AND on the item (the only two places it is carried).
            Assert.Equal(amount, candidate["money"]!["amount"]!.GetValue<string>());
            Assert.Equal("USD", candidate["money"]!["currency"]!.GetValue<string>());
            Assert.Equal(amount, candidate["items"]![0]!["cost"]!["amount"]!.GetValue<string>());
            Assert.Equal("USD", candidate["items"]![0]!["cost"]!["currency"]!.GetValue<string>());
            if (odometer is int expected)
            {
                Assert.Equal(expected, candidate["odometer"]!.GetValue<int>());
            }
            else
            {
                Assert.Null(candidate["odometer"]);
            }
        }
    }

    [Fact]
    public void CostsCsv_ParkingFiledFuelFilter_StaysParking_NotRetypedByContent()
    {
        using var stream = MfmFixture.Open(MfmFixture.CostsCsv);
        var result = MfmParser.Parse(stream, CancellationToken.None);

        // The owner's own mis-filed row (hard rule 13's proof that no mapping
        // table is right about every row): a fuel filter filed under "Parking".
        //   9/17/2020;1459;USD;"Parking";380016;"Топливный фильтр VAG 8t0127401A";"AUDI A4 ..."
        // The note says "filter", so a content-sniffing mapper would file it as
        // a service part; the claim is that it lands exactly as filed - a
        // parking expense whose note survives for the USER to correct.
        var candidate = Assert.Single(result.Candidates,
            c => c["title"]?.GetValue<string>() == "Топливный фильтр VAG 8t0127401A");
        Assert.Equal("expense", candidate["entityType"]!.GetValue<string>());
        Assert.Equal("parking", candidate["category"]!["tag"]!.GetValue<string>());
        Assert.Equal("Топливный фильтр VAG 8t0127401A", candidate["title"]!.GetValue<string>());
        Assert.Equal("1459", candidate["money"]!["amount"]!.GetValue<string>());
        Assert.Equal("USD", candidate["money"]!["currency"]!.GetValue<string>());
    }

    [Fact]
    public void CostsCsv_AnUnknownFinanceCategory_LandsUnparsed_AndTheRestStillMap()
    {
        // A finance category the mapping does not know is a mapping gap, not a
        // guess: the row lands in `unparsed` with the stable reason and the rest
        // of the file keeps parsing (hard rule 8). The replacement-parts row
        // beside it proves the file still maps after the gap.
        var csv = """
        My Fuel Manager - COSTS
        Date;Total price;Currency;Finance category;Odometer;Note;Vehicle name
        4/27/2026;133;USD;"Replacement parts";106722;"Замена колес зима -> лето";"Volvo"
        5/1/2026;50;USD;"Insurance";100000;"Roadside cover";"Volvo"
        """;
        using var stream = new MemoryStream(Encoding.UTF8.GetBytes(csv));
        var result = MfmParser.Parse(stream, CancellationToken.None);

        var good = Assert.Single(result.Candidates);
        Assert.Equal("serviceRecord", good["entityType"]!.GetValue<string>());
        Assert.Equal("parts", good["items"]![0]!["category"]!["tag"]!.GetValue<string>());

        var bad = Assert.Single(result.Unparsed);
        Assert.Equal(2, bad.Row);
        Assert.Equal(MfmParser.ReasonUnknownFinanceCategory, bad.Reason);
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

    /// <summary>
    /// RV.116: vehicles.csv has columns the parser does not map. Vehicle price is
    /// non-zero on two of five rows, Initial tank status on all five, Color on
    /// all five; LPG tank volume and Initial LPG tank status are "0" everywhere
    /// and are omitted.
    /// </summary>
    [Fact]
    public void VehiclesCsv_ReportsTheUnsupportedColumnsWithTheirCounts()
    {
        using var stream = MfmFixture.Open(MfmFixture.VehiclesCsv);
        var result = MfmParser.Parse(stream, CancellationToken.None);

        Assert.Collection(result.Unsupported,
            c => { Assert.Equal("Vehicle price", c.Column); Assert.Equal(2, c.RowCount); },
            c => { Assert.Equal("Initial tank status", c.Column); Assert.Equal(5, c.RowCount); },
            c => { Assert.Equal("Color", c.Column); Assert.Equal(5, c.RowCount); });
        Assert.DoesNotContain(result.Unsupported, c => c.Column == "LPG tank volume");
        Assert.DoesNotContain(result.Unsupported, c => c.Column == "Initial LPG tank status");
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

    /// The first service item's title, or null when the candidate is not a
    /// service record (an expense has no `items`). Null-safe: the predicate
    /// walks the whole candidate list, so a non-service candidate must read
    /// "not matched" rather than throw.
    private static string? FirstItemTitle(JsonObject candidate) =>
        (candidate["items"] as JsonArray)?[0]?["title"]?.GetValue<string>();

    /// <summary>A synthetic fuel export over the given date cells (RV.85: the whole-file
    /// date-order tests need files whose dates are chosen, not a real export's).</summary>
    private static string FuelCsv(IEnumerable<string> dates)
    {
        var rows = dates.Select((date, i) =>
            $"{date};{45 + i};{100000 + i * 100};{80 + i};USD;1;F;100;\"\";\"Volvo\"");
        var sb = new StringBuilder();
        sb.AppendLine("My Fuel Manager - Fuel");
        sb.AppendLine("Date;Fillup volume;Odometer;Total price;Currency;Fuel;Tank status after fillup;%;Note;Vehicle name");
        foreach (var row in rows)
        {
            sb.AppendLine(row);
        }

        return sb.ToString();
    }

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

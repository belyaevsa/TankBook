using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text;
using System.Text.Json;
using Dapper;
using Npgsql;

namespace Tankbook.Admin.Tests;

/// <summary>
/// Debug cases read by id (hard rule 9's debug-cases amendment): by the owner's passkey
/// session or by the owner's read key; the read key opens the case routes and nothing
/// else; there is no list; every look writes its access row under who looked.
/// </summary>
[Collection(AdminCollection.Name)]
public sealed class CaseReadTests(AdminDatabase database) : IAsyncLifetime
{
    private readonly AdminFactory _factory = new(database);
    private const string CaseId = "K7Q2M-9XDRA";
    private static readonly Guid Device = Guid.Parse("11111111-2222-3333-4444-555555555555");

    public async Task InitializeAsync()
    {
        await using var c = new NpgsqlConnection(database.Superuser);
        await c.ExecuteAsync("TRUNCATE admin.access_log");
        await c.ExecuteAsync("DELETE FROM debug_cases");
        var parts = new[]
        {
            new { name = "log.txt", contentType = "text/plain", bytes = 11L, key = $"{Device:N}/cases/{CaseId}/log.txt" },
            new { name = "scan-1-photo.jpg", contentType = "image/jpeg", bytes = 4L, key = $"{Device:N}/cases/{CaseId}/scan-1-photo.jpg" },
        };
        await c.ExecuteAsync(
            "INSERT INTO debug_cases (id, device_id, app, parts, total_bytes) VALUES (@id, @device, '1.0.0+1784', CAST(@parts AS jsonb), 15)",
            new { id = CaseId, device = Device, parts = JsonSerializer.Serialize(parts) });
        _factory.Blobs[$"{Device:N}/cases/{CaseId}/log.txt"] = Encoding.UTF8.GetBytes("line one\nx");
        _factory.Blobs[$"{Device:N}/cases/{CaseId}/scan-1-photo.jpg"] = [0xFF, 0xD8, 0xFF, 0xD9];
    }

    public async Task DisposeAsync() => await _factory.DisposeAsync();

    private HttpClient Owner()
    {
        var client = _factory.CreateClient();
        client.DefaultRequestHeaders.Add(AdminFactory.TestHeader, "test-iphone");
        return client;
    }

    private HttpClient WithKey(string key)
    {
        var client = _factory.CreateClient();
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", key);
        return client;
    }

    private async Task<List<(string Actor, string Kind, string Target)>> AccessRowsAsync()
    {
        await using var c = new NpgsqlConnection(database.Superuser);
        return (await c.QueryAsync<(string, string, string)>(
            "SELECT actor, kind, target_id FROM admin.access_log ORDER BY id")).ToList();
    }

    [Fact]
    public async Task TheOwnerReadsACaseAndItsParts()
    {
        var client = Owner();
        var body = await client.GetFromJsonAsync<JsonElement>($"/api/cases/{CaseId}");
        Assert.Equal(CaseId, body.GetProperty("id").GetString());
        Assert.Equal(2, body.GetProperty("parts").GetArrayLength());
        Assert.False(body.GetRawText().Contains("key", StringComparison.OrdinalIgnoreCase), "storage keys never leave the viewer");
        Assert.Equal("line one\nx", await client.GetStringAsync($"/api/cases/{CaseId}/parts/log.txt"));
        Assert.Equal([("test-iphone", "case", CaseId), ("test-iphone", "case-part", CaseId)], await AccessRowsAsync());
    }

    [Fact]
    public async Task TheReadKeyReadsACase_AndItsAccessRowNamesTheKey()
    {
        var client = WithKey(AdminFactory.ReadKey);
        using var response = await client.GetAsync($"/api/cases/{CaseId.ToLowerInvariant()}");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var photo = await client.GetByteArrayAsync($"/api/cases/{CaseId}/parts/scan-1-photo.jpg");
        Assert.Equal([0xFF, 0xD8, 0xFF, 0xD9], photo);
        var rows = await AccessRowsAsync();
        Assert.Equal(2, rows.Count);
        Assert.All(rows, row => Assert.StartsWith("read-key:", row.Actor, StringComparison.Ordinal));
    }

    [Theory]
    [InlineData("/api/me")]
    [InlineData("/api/accounts/00000000-0000-0000-0000-000000000001/attachments")]
    [InlineData("/api/accounts/00000000-0000-0000-0000-000000000001/llm-calls")]
    [InlineData("/api/llm-calls/00000000-0000-0000-0000-000000000001")]
    [InlineData("/api/access-log")]
    public async Task TheReadKeyOpensNothingButCases(string path)
    {
        using var response = await WithKey(AdminFactory.ReadKey).GetAsync(path);
        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task AWrongKeyReadsNothing_AndLeavesNoAccessRow()
    {
        using var response = await WithKey("not-the-key").GetAsync($"/api/cases/{CaseId}");
        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
        Assert.Empty(await AccessRowsAsync());
    }

    [Fact]
    public async Task ThereIsNoListOfCases()
    {
        using var response = await Owner().GetAsync("/api/cases");
        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }

    [Fact]
    public async Task AnUnknownCaseIsNotFound_AndTheLookIsStillLogged()
    {
        using var response = await Owner().GetAsync("/api/cases/ZZZZZ-ZZZZZ");
        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
        Assert.Equal([("test-iphone", "case", "ZZZZZ-ZZZZZ")], await AccessRowsAsync());
    }
}

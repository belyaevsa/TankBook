using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Dapper;
using Npgsql;
using Tankbook.Admin.Auth;
using Tankbook.Admin.Data;

namespace Tankbook.Admin.Tests;

/// <summary>
/// The ledger (AD.5) and attachment (AD.6) pages: what they return, that a purged image
/// reads as not-found rather than an error, that one account's attachment cannot be
/// reached through another's id, and that every look writes its access row.
/// </summary>
[Collection(AdminCollection.Name)]
public sealed class ContentTests(AdminDatabase database) : IAsyncLifetime
{
    private readonly AdminFactory _factory = new(database);

    public async Task InitializeAsync()
    {
        await using var c = new NpgsqlConnection(database.Superuser);
        await c.ExecuteAsync("TRUNCATE admin.access_log");
    }

    public async Task DisposeAsync() => await _factory.DisposeAsync();

    private HttpClient Owner()
    {
        var client = _factory.CreateClient();
        client.DefaultRequestHeaders.Add(AdminFactory.TestHeader, "test-iphone");
        return client;
    }

    private async Task<Guid> AccountAsync(NpgsqlConnection c)
    {
        var id = Guid.NewGuid();
        await c.ExecuteAsync("INSERT INTO accounts (id, apple_sub, email) VALUES (@id, @sub, 'o@example.com')",
            new { id, sub = "apple-" + id });
        return id;
    }

    private async Task<List<string>> AccessKindsAsync()
    {
        await using var c = new NpgsqlConnection(database.Superuser);
        return (await c.QueryAsync<string>("SELECT kind FROM admin.access_log ORDER BY id")).ToList();
    }

    [Fact]
    public async Task AnLlmCallReadsWholeWithItsPromptImage()
    {
        await using var c = new NpgsqlConnection(database.Superuser);
        var account = await AccountAsync(c);
        var call = Guid.NewGuid();
        var sha = new string('a', 64);
        await c.ExecuteAsync(
            "INSERT INTO llm_calls (id, account_id, kind, model_id, vendor, outcome, category, prompt_tokens, completion_tokens, cost, currency, prompt_sha256, response_body, duration_ms) " +
            "VALUES (@call, @account, 'extract', 'model-x', 'vendor-y', 'ok', 'success', 1200, 80, 0.0021, 'USD', @sha, '{\"total\":30.02}', 950)",
            new { call, account, sha });
        _factory.Blobs[BlobKeys.LlmPrompt(account, sha)] = [0xFF, 0xD8, 0xFF];
        var client = Owner();

        var list = await client.GetFromJsonAsync<List<JsonElement>>($"/api/accounts/{account}/llm-calls");
        Assert.Single(list!);
        Assert.Equal(1, list![0].GetProperty("pages").GetInt32());
        Assert.False(list[0].TryGetProperty("responseBody", out _)); // the list carries no bodies

        var whole = await client.GetFromJsonAsync<JsonElement>($"/api/llm-calls/{call}");
        Assert.Equal("{\"total\":30.02}", whole.GetProperty("responseBody").GetString());
        Assert.False(whole.GetProperty("promptPurged").GetBoolean());

        var image = await client.GetAsync($"/api/llm-calls/{call}/pages/0");
        Assert.Equal(HttpStatusCode.OK, image.StatusCode);
        Assert.Equal("image/jpeg", image.Content.Headers.ContentType?.MediaType);
        Assert.Equal(HttpStatusCode.NotFound, (await client.GetAsync($"/api/llm-calls/{call}/pages/1")).StatusCode);

        var hit = await client.GetFromJsonAsync<JsonElement>($"/api/lookup?q={call}");
        Assert.Equal("llm-call", hit.GetProperty("kind").GetString());

        Assert.Equal(["llm-calls", "llm-call", "llm-prompt-image", "llm-prompt-image", "lookup"], await AccessKindsAsync());
    }

    // Oracle: SECURITY.md - the ledger's retention applies; a purged rendition (the bytes
    // gone from the bucket, or prompt_sha256 cleared) is a 404, never a 500.
    [Fact]
    public async Task APurgedPromptImageIsNotFound()
    {
        await using var c = new NpgsqlConnection(database.Superuser);
        var account = await AccountAsync(c);
        var call = Guid.NewGuid();
        await c.ExecuteAsync(
            "INSERT INTO llm_calls (id, account_id, kind, model_id, vendor, outcome, category, prompt_sha256) " +
            "VALUES (@call, @account, 'extract', 'm', 'v', 'ok', 'success', @sha)",
            new { call, account, sha = new string('b', 64) });
        Assert.Equal(HttpStatusCode.NotFound, (await Owner().GetAsync($"/api/llm-calls/{call}/pages/0")).StatusCode);
    }

    [Fact]
    public async Task AnAccountsAttachmentsReadWithTheirFiles()
    {
        await using var c = new NpgsqlConnection(database.Superuser);
        var account = await AccountAsync(c);
        var other = await AccountAsync(c);
        var attachment = Guid.NewGuid();
        var sha = new string('c', 64);
        var payload = JsonSerializer.Serialize(new
        {
            id = attachment,
            kind = "photo",
            createdAt = "2026-09-25T10:12:00Z",
            updatedAt = "2026-09-25T10:12:00Z",
            file = new { sha256 = sha, relativePath = "p.jpg" },
            ocrText = "KOKKU 30,02",
            thumbnailBase64 = "AAAA",
            extractionMeta = new { pipeline = "on-device" },
        });
        await c.ExecuteAsync(
            "INSERT INTO records (account_id, id, entity_type, scn, payload, client_updated_at) VALUES (@account, @attachment, 'attachment', 1, @payload::jsonb, now())",
            new { account, attachment, payload });
        await c.ExecuteAsync("INSERT INTO blobs (account_id, sha256, size_bytes, storage_ref) VALUES (@account, @sha, 3, @storageRef)",
            new { account, sha, storageRef = $"{account:N}/{sha}" });
        _factory.Blobs[$"{account:N}/{sha}"] = [1, 2, 3];
        var client = Owner();

        var list = await client.GetFromJsonAsync<List<JsonElement>>($"/api/accounts/{account}/attachments");
        Assert.Single(list!);
        Assert.Equal(3, list![0].GetProperty("sizeBytes").GetInt64());
        Assert.True(list[0].GetProperty("hasOcrText").GetBoolean());

        var one = await client.GetFromJsonAsync<JsonElement>($"/api/accounts/{account}/attachments/{attachment}");
        Assert.Equal("KOKKU 30,02", one.GetProperty("ocrText").GetString());
        Assert.Equal("on-device", one.GetProperty("extractionMeta").GetProperty("pipeline").GetString());

        var file = await client.GetAsync($"/api/accounts/{account}/attachments/{attachment}/file");
        Assert.Equal(HttpStatusCode.OK, file.StatusCode);
        Assert.Equal([1, 2, 3], await file.Content.ReadAsByteArrayAsync());

        // Oracle: SECURITY.md - by account id only; another account's id reaches nothing.
        Assert.Equal(HttpStatusCode.NotFound,
            (await client.GetAsync($"/api/accounts/{other}/attachments/{attachment}/file")).StatusCode);

        Assert.Equal(["attachments", "attachment", "attachment-file", "attachment-file"], await AccessKindsAsync());
    }

    [Theory]
    [InlineData("/api/accounts/00000000-0000-0000-0000-000000000001/llm-calls")]
    [InlineData("/api/llm-calls/00000000-0000-0000-0000-000000000001")]
    [InlineData("/api/llm-calls/00000000-0000-0000-0000-000000000001/pages/0")]
    [InlineData("/api/accounts/00000000-0000-0000-0000-000000000001/attachments")]
    [InlineData("/api/accounts/00000000-0000-0000-0000-000000000001/attachments/00000000-0000-0000-0000-000000000002/file")]
    public async Task TheContentPagesAre401WithoutASession(string path)
    {
        Assert.Equal(HttpStatusCode.Unauthorized, (await _factory.CreateClient().GetAsync(path)).StatusCode);
    }
}

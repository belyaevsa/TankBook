using System.Net;
using System.Net.Http.Json;
using Dapper;
using Npgsql;
using Tankbook.Admin.Auth;

namespace Tankbook.Admin.Tests;

[Collection(AdminCollection.Name)]
public sealed class AdminServiceTests(AdminDatabase database) : IAsyncLifetime
{
    private readonly AdminFactory _factory = new(database);

    public async Task InitializeAsync()
    {
        await using var c = new NpgsqlConnection(database.Superuser);
        await c.ExecuteAsync(
            "TRUNCATE admin.access_log, admin.passkeys, admin.bootstrap_tokens; " +
            "INSERT INTO admin.bootstrap_tokens (token_hash) VALUES (@hash)",
            new { hash = BootstrapTokens.Hash(AdminFactory.BootstrapToken) });
    }

    public async Task DisposeAsync() => await _factory.DisposeAsync();

    private HttpClient Owner()
    {
        var client = _factory.CreateClient();
        client.DefaultRequestHeaders.Add(AdminFactory.TestHeader, "test-iphone");
        return client;
    }

    private async Task<Guid> InsertAccountAsync()
    {
        var id = Guid.NewGuid();
        await using var c = new NpgsqlConnection(database.Superuser);
        await c.ExecuteAsync("INSERT INTO accounts (id, apple_sub, email) VALUES (@id, @sub, 'owner@example.com')",
            new { id, sub = "apple-" + id });
        return id;
    }

    private async Task<List<(string Kind, string? TargetId, int Status, string Actor)>> AccessRowsAsync()
    {
        await using var c = new NpgsqlConnection(database.Superuser);
        return (await c.QueryAsync<(string, string?, int, string)>(
            "SELECT kind, target_id, status, actor FROM admin.access_log ORDER BY id")).ToList();
    }

    // Oracle: docs/SECURITY.md -> "The admin viewer" - nothing answers without a session
    // except the sign-in ceremony itself. Exactly 401: a 404 would also withhold content and
    // would hide a route that is simply missing.
    [Theory]
    [InlineData("/api/accounts/00000000-0000-0000-0000-000000000001")]
    [InlineData("/api/lookup?q=00000000-0000-0000-0000-000000000001")]
    [InlineData("/api/access-log")]
    [InlineData("/api/me")]
    public async Task ContentEndpointsAre401WithoutASession(string path)
    {
        var response = await _factory.CreateClient().GetAsync(path);
        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    // Oracle: SECURITY.md - the bootstrap token registers the first passkey and nothing once
    // a passkey exists, whatever the configuration still holds.
    [Fact]
    public async Task TheBootstrapTokenWorksOnlyWhileNoPasskeyExists()
    {
        var client = _factory.CreateClient();
        var first = await client.PostAsJsonAsync("/auth/register/options",
            new { bootstrapToken = AdminFactory.BootstrapToken, label = "iPhone" });
        Assert.Equal(HttpStatusCode.OK, first.StatusCode);

        await using (var c = new NpgsqlConnection(database.Superuser))
        {
            await c.ExecuteAsync(
                "INSERT INTO admin.passkeys (id, credential_id, public_key, user_handle, label) VALUES (@id, @cred, @key, @handle, 'iPhone')",
                new { id = Guid.NewGuid(), cred = new byte[] { 1, 2, 3 }, key = new byte[] { 4 }, handle = new byte[] { 5 } });
        }
        var second = await client.PostAsJsonAsync("/auth/register/options",
            new { bootstrapToken = AdminFactory.BootstrapToken, label = "iPhone" });
        Assert.Equal(HttpStatusCode.Forbidden, second.StatusCode);
    }

    // Oracle: SECURITY.md - a consumed token never works again.
    [Fact]
    public async Task AConsumedBootstrapTokenIsRefused()
    {
        await using (var c = new NpgsqlConnection(database.Superuser))
        {
            await c.ExecuteAsync("UPDATE admin.bootstrap_tokens SET consumed_at = now()");
        }
        var response = await _factory.CreateClient().PostAsJsonAsync("/auth/register/options",
            new { bootstrapToken = AdminFactory.BootstrapToken, label = "iPhone" });
        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
    }

    [Fact]
    public async Task RegistrationWithoutATokenOrSessionIsRefused()
    {
        var response = await _factory.CreateClient().PostAsJsonAsync("/auth/register/options", new { label = "iPhone" });
        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
    }

    // Oracle: SECURITY.md - every view writes an access row, including a look that found
    // nothing. The actor is the passkey's label, never an email.
    [Fact]
    public async Task AnAccountViewWritesItsAccessRowFoundOrNot()
    {
        var id = await InsertAccountAsync();
        var client = Owner();

        var found = await client.GetAsync($"/api/accounts/{id}");
        Assert.Equal(HttpStatusCode.OK, found.StatusCode);
        var account = await found.Content.ReadFromJsonAsync<Dictionary<string, object>>();
        Assert.Equal("apple", account!["provider"].ToString());

        var missing = Guid.NewGuid();
        var notFound = await client.GetAsync($"/api/accounts/{missing}");
        Assert.Equal(HttpStatusCode.NotFound, notFound.StatusCode);

        var rows = await AccessRowsAsync();
        Assert.Equal(2, rows.Count);
        Assert.Equal(("account", id.ToString(), 200, "test-iphone"), rows[0]);
        Assert.Equal(("account", missing.ToString(), 404, "test-iphone"), rows[1]);
    }

    [Fact]
    public async Task AnUnauthenticatedRequestWritesNoAccessRow()
    {
        await _factory.CreateClient().GetAsync($"/api/accounts/{Guid.NewGuid()}");
        Assert.Empty(await AccessRowsAsync());
    }

    // Oracle: SECURITY.md - lookup by an exact id only; a prefix is a search.
    [Fact]
    public async Task LookupIsExact()
    {
        var id = await InsertAccountAsync();
        var client = Owner();
        Assert.Equal(HttpStatusCode.OK, (await client.GetAsync($"/api/lookup?q={id}")).StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, (await client.GetAsync($"/api/lookup?q={id.ToString()[..8]}")).StatusCode);
        Assert.Equal(["lookup", "lookup"], (await AccessRowsAsync()).Select(r => r.Kind));
    }

    [Fact]
    public async Task TheAccessLogReadsBackNewestFirst()
    {
        var client = Owner();
        await client.GetAsync($"/api/accounts/{Guid.NewGuid()}");
        await client.GetAsync($"/api/lookup?q=x");
        var entries = await client.GetFromJsonAsync<List<Dictionary<string, object>>>("/api/access-log");
        Assert.Equal(["lookup", "account"], entries!.Select(e => e["kind"].ToString()));
    }

    [Fact]
    public async Task AnUnknownApiRouteIsNotFoundNotTheApp()
    {
        var response = await Owner().GetAsync("/api/no-such-route");
        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }

    [Fact]
    public async Task ResponsesCarryTheSecurityHeaders()
    {
        var response = await _factory.CreateClient().GetAsync("/health");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Contains("default-src 'self'", response.Headers.GetValues("Content-Security-Policy").Single());
        Assert.Equal("DENY", response.Headers.GetValues("X-Frame-Options").Single());
    }

    // Oracle: SECURITY.md - the viewer reads the API's tables through a role that cannot
    // write. Connected as that role, never as the superuser.
    [Fact]
    public async Task TheReadOnlyRoleCannotWrite()
    {
        await using var ro = new NpgsqlConnection(database.ApiRead);
        await ro.OpenAsync();
        Assert.True(await ro.ExecuteScalarAsync<long>("SELECT count(*) FROM accounts") >= 0);
        var denied = await Assert.ThrowsAsync<PostgresException>(() => ro.ExecuteAsync(
            "INSERT INTO accounts (id, email) VALUES (@id, 'x@example.com')", new { id = Guid.NewGuid() }));
        Assert.Equal(PostgresErrorCodes.InsufficientPrivilege, denied.SqlState);
        var secret = await Assert.ThrowsAsync<PostgresException>(() => ro.ExecuteScalarAsync<long>(
            "SELECT count(*) FROM refresh_tokens"));
        Assert.Equal(PostgresErrorCodes.InsufficientPrivilege, secret.SqlState);
    }

    [Fact]
    public async Task TheWriteRoleCannotReachTheApiTables()
    {
        await using var rw = new NpgsqlConnection(database.AdminWrite);
        await rw.OpenAsync();
        var denied = await Assert.ThrowsAsync<PostgresException>(() => rw.ExecuteScalarAsync<long>("SELECT count(*) FROM accounts"));
        Assert.Equal(PostgresErrorCodes.InsufficientPrivilege, denied.SqlState);
    }
}

using Npgsql;

namespace Tankbook.Admin.Data;

/// <summary>
/// The viewer's two database connections, kept apart by type so a query over user data
/// cannot be written through the connection that can write (docs/SECURITY.md -> "The admin
/// viewer"): <see cref="ApiRead"/> is the read-only role over the API's tables,
/// <see cref="AdminWrite"/> the role that owns schema <c>admin</c> and nothing else.
/// </summary>
public sealed class Db(IConfiguration configuration)
{
    private readonly string _apiRead = configuration.GetConnectionString("ApiRead") ?? "";
    private readonly string _adminWrite = configuration.GetConnectionString("AdminWrite") ?? "";

    public NpgsqlConnection ApiRead() => new(Require(_apiRead, "ApiRead"));

    public NpgsqlConnection AdminWrite() => new(Require(_adminWrite, "AdminWrite"));

    private static string Require(string value, string name) =>
        string.IsNullOrWhiteSpace(value)
            ? throw new InvalidOperationException($"ConnectionStrings:{name} is not configured")
            : value;
}

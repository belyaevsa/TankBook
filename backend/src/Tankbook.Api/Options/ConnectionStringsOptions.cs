namespace Tankbook.Api.Options;

/// <summary>
/// Bound from the "ConnectionStrings" configuration section; the Postgres
/// entry holds the Npgsql connection string. Overridable via the
/// ConnectionStrings__Postgres environment variable.
/// </summary>
public sealed class ConnectionStringsOptions
{
    public const string SectionName = "ConnectionStrings";

    public string? Postgres { get; set; }
}

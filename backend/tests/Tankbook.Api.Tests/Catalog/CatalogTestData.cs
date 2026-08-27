using System.Text.Json;

namespace Tankbook.Api.Tests.Catalog;

/// <summary>
/// Shared fixtures for the catalog tests: a dev admin token (mirroring
/// appsettings.Development.json) and a builder for schema-valid packs.
/// </summary>
internal static class CatalogTestData
{
    public const string AdminToken = "test-catalog-admin-token";

    private static readonly JsonSerializerOptions WireJson = new(JsonSerializerDefaults.Web);

    /// <summary>One catalog entry in the wire shape (docs/API.md "Vehicle catalog").</summary>
    public sealed record Entry(
        Guid Id,
        string Make,
        string Model,
        string? Generation = null,
        int[]? Years = null,
        string Powertrain = "ice",
        string[]? FuelKinds = null,
        decimal? TankCapacityL = null,
        decimal? BatteryCapacityKwh = null)
    {
        public string[] EffectiveFuelKinds => FuelKinds ?? ["petrol95"];
    }

    /// <summary>A complete publish pack in the wire shape, schema-valid by default.</summary>
    public static string Pack(int version, params Entry[] entries)
    {
        var envelope = new
        {
            packVersion = version,
            entries = entries.Select(e => new
            {
                e.Id,
                e.Make,
                e.Model,
                e.Generation,
                e.Years,
                e.Powertrain,
                fuelKinds = e.EffectiveFuelKinds,
                e.TankCapacityL,
                e.BatteryCapacityKwh,
            }),
        };
        return JsonSerializer.Serialize(envelope, WireJson);
    }
}

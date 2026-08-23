using System.Globalization;
using System.Text;
using Tankbook.Api.Config;

namespace Tankbook.Api.Tests.Config;

/// <summary>
/// Shared fixtures for the remote-config tests: a deterministic dev signing key
/// (the same base64 seed that sits in appsettings.Development.json) and a
/// builder for schema-valid baseline documents.
/// </summary>
internal static class ConfigTestData
{
    /// <summary>Dev-only Ed25519 seed, mirroring appsettings.Development.json.</summary>
    public const string SeedBase64 = "IpsG7l75fgQtx1iYnwLA7ekrhHbkB8dy3sMjbo4OUKM=";

    public static readonly ConfigSigner Signer = new(SeedBase64);

    public static string Iso(DateTimeOffset value)
        => value.ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss.fff'Z'", CultureInfo.InvariantCulture);

    /// <summary>
    /// A schema-valid baseline document. Optional knobs keep it useful for both
    /// positive and negative tests (maintenance markup, apiBaseUrl, version).
    /// </summary>
    public static string Document(
        int version = 1,
        DateTimeOffset? issuedAt = null,
        DateTimeOffset? notAfter = null,
        string? maintenanceText = null,
        string? apiBaseUrl = null)
    {
        var builder = new StringBuilder();
        builder.Append("{\"version\":").Append(version.ToString(CultureInfo.InvariantCulture))
            .Append(",\"issuedAt\":\"").Append(Iso(issuedAt ?? DateTimeOffset.UtcNow.AddDays(-1))).Append('"')
            .Append(",\"notAfter\":\"").Append(Iso(notAfter ?? DateTimeOffset.UtcNow.AddDays(89))).Append('"');
        if (apiBaseUrl is not null)
        {
            builder.Append(",\"apiBaseUrl\":").Append(JsonEscaped(apiBaseUrl));
        }

        builder.Append(",\"tier2OnDeviceLLM\":true")
            .Append(",\"tier3CloudFallback\":true")
            .Append(",\"llmQuota\":{\"onDeviceLLM\":200,\"cloudFallback\":50}")
            .Append(",\"ocrConfidenceThreshold\":0.75")
            .Append(",\"minSchemaVersion\":1")
            .Append(",\"referencePacks\":{\"rates\":1,\"catalog\":1}")
            .Append(",\"rolloutSalt\":\"test-rollout-salt\"");
        if (maintenanceText is not null)
        {
            builder.Append(",\"maintenance\":{\"text\":")
                .Append(JsonEscaped(maintenanceText))
                .Append(",\"severity\":\"info\",\"until\":\"")
                .Append(Iso(DateTimeOffset.UtcNow.AddDays(2))).Append("\"}");
        }

        builder.Append('}');
        return builder.ToString();
    }

    private static string JsonEscaped(string value)
        => System.Text.Json.JsonSerializer.Serialize(value);
}

using System.Data;
using System.Globalization;
using Dapper;
using Microsoft.Extensions.Logging;
using Tankbook.Api.Logging;

namespace Tankbook.Api.Config;

/// <summary>
/// Completes the signature of the baseline config document seeded by migration
/// 003 (docs/CONFIG.md). Migration 003 cannot produce an Ed25519 signature - SQL
/// cannot compute one and the signing key is configuration, not schema - so the
/// row is seeded with an empty signature placeholder and this step signs it at
/// startup. Idempotent: a row that already carries a signature that verifies is
/// left untouched, so every restart is a no-op. When the table is unexpectedly
/// empty, a fresh baseline is built and published instead.
/// </summary>
public static class ConfigBaselineSeeder
{
    private const string BaselineRolloutSalt = "tankbook-baseline-rollout-salt";
    private static readonly TimeSpan BaselineValidityWindow = TimeSpan.FromDays(90);

    /// <summary>Runs after migrations apply; safe to call on every startup.</summary>
    public static async Task SeedAsync(
        IDbConnection connection,
        ConfigSigner signer,
        ConfigSchemaValidator validator,
        ILogger logger,
        CancellationToken cancellationToken)
    {
        if (!signer.IsConfigured)
        {
            logger.LogWarning(
                "Config:SigningKey is not configured; the config document cannot be signed. " +
                "Set it from the secret store before serving config to devices.");
            return;
        }

        var top = await GetTopAsync(connection, cancellationToken);

        if (top is null)
        {
            var baseline = BuildBaselineDocument(DateTimeOffset.UtcNow);
            var errors = validator.Validate(baseline);
            if (errors.Count > 0)
            {
                logger.LogError("The built-in baseline config document failed schema validation; not publishing. {Errors}", string.Join(" | ", errors));
                return;
            }

            var signature = signer.Sign(ConfigCanonicalizer.Canonicalize(baseline));
            await connection.ExecuteAsync(
                """
                INSERT INTO config_documents (version, document, signature, issued_at, not_after)
                VALUES (1, @Document::jsonb, @Signature, @IssuedAt, @NotAfter)
                ON CONFLICT (version) DO NOTHING
                """,
                new
                {
                    Document = baseline,
                    Signature = signature,
                    IssuedAt = DateTimeOffset.UtcNow,
                    NotAfter = DateTimeOffset.UtcNow.Add(BaselineValidityWindow),
                });
            TankbookLog.ConfigSeed(logger, 1, "inserted");
            return;
        }

        // The document is already correctly signed: nothing to do.
        var canonical = ConfigCanonicalizer.Canonicalize(top.Value.Document);
        if (signer.Verify(canonical, top.Value.Signature))
        {
            return;
        }

        // Never propagate a document that violates the schema, even signed.
        var validationErrors = validator.Validate(top.Value.Document);
        if (validationErrors.Count > 0)
        {
            logger.LogError(
                "Config document version {Version} fails schema validation; leaving it unsigned. " +
                "The server will serve it and clients will reject it (falling back to bundled defaults). {Errors}",
                top.Value.Version, string.Join(" | ", validationErrors));
            return;
        }

        var newSignature = signer.Sign(canonical);
        await connection.ExecuteAsync(
            "UPDATE config_documents SET signature = @Signature WHERE version = @Version",
            new { Version = top.Value.Version, Signature = newSignature });
        TankbookLog.ConfigSeed(logger, top.Value.Version, "resigned");
    }

    private static async Task<(int Version, string Document, string Signature)?> GetTopAsync(
        IDbConnection connection,
        CancellationToken cancellationToken)
    {
        try
        {
            return await connection.QuerySingleOrDefaultAsync<(int Version, string Document, string Signature)>(new CommandDefinition(
                """
                SELECT version       AS Version,
                       document::text AS Document,
                       signature      AS Signature
                FROM config_documents
                ORDER BY version DESC
                LIMIT 1
                """,
                cancellationToken: cancellationToken));
        }
        catch (Npgsql.PostgresException ex) when (ex.SqlState == "42P01")
        {
            // The config_documents table does not exist yet. The caller retries
            // with backoff (migrations may still be applying), so this is
            // recoverable rather than fatal.
            return null;
        }
    }

    private static string BuildBaselineDocument(DateTimeOffset now)
    {
        var isoNow = Iso(now);
        var isoNotAfter = Iso(now.Add(BaselineValidityWindow));
        return
            "{\"version\":1," +
            $"\"issuedAt\":\"{isoNow}\"," +
            $"\"notAfter\":\"{isoNotAfter}\"," +
            "\"tier2OnDeviceLLM\":true," +
            "\"tier3CloudFallback\":true," +
            "\"llmQuota\":{\"onDeviceLLM\":200,\"cloudFallback\":50}," +
            "\"ocrConfidenceThreshold\":0.75," +
            "\"minSchemaVersion\":1," +
            "\"referencePacks\":{\"rates\":1,\"catalog\":1}," +
            $"\"rolloutSalt\":\"{BaselineRolloutSalt}\"" +
            "}";
    }

    private static string Iso(DateTimeOffset value)
        => value.ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss.fff'Z'", CultureInfo.InvariantCulture);
}

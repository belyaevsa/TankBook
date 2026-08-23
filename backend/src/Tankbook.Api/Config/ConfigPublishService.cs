using System.Globalization;
using System.Text.Json;
using Microsoft.Extensions.Logging;
using Tankbook.Api.Logging;

namespace Tankbook.Api.Config;

/// <summary>
/// The internal publish path for config documents (docs/CONFIG.md). Not an HTTP
/// endpoint - publishing is a server operator action. Per docs/CONFIG.md:
/// validate against the JSON Schema first (a malformed document must never
/// reach a device), then enforce version monotonicity (rollback protection),
/// then sign the canonical serialization, then insert. Any refusal is a typed
/// <see cref="ConfigPublishError"/>, never an exception string.
/// </summary>
public sealed class ConfigPublishService
{
    private readonly ConfigRepository _repository;
    private readonly ConfigSchemaValidator _validator;
    private readonly ConfigSigner _signer;
    private readonly ILogger<ConfigPublishService> _logger;

    public ConfigPublishService(
        ConfigRepository repository,
        ConfigSchemaValidator validator,
        ConfigSigner signer,
        ILogger<ConfigPublishService> logger)
    {
        _repository = repository;
        _validator = validator;
        _signer = signer;
        _logger = logger;
    }

    /// <summary>
    /// Validates, checks monotonicity, signs and publishes a config document.
    /// </summary>
    /// <param name="documentJson">The complete config document as JSON text.</param>
    public async Task<ConfigPublishResult> PublishAsync(string documentJson, CancellationToken cancellationToken)
    {
        if (!_signer.IsConfigured)
        {
            return new ConfigPublishResult(
                new ConfigPublishError(ConfigPublishErrorKind.SigningKeyNotConfigured,
                    "Config:SigningKey is not configured; a document cannot be signed."));
        }

        if (!TryReadEnvelope(documentJson, out var version, out var issuedAt, out var notAfter))
        {
            return new ConfigPublishResult(
                new ConfigPublishError(ConfigPublishErrorKind.InvalidDocument,
                    "The document is not parseable JSON, not an object, or lacks version/issuedAt/notAfter."));
        }

        var errors = _validator.Validate(documentJson);
        if (errors.Count > 0)
        {
            TankbookLog.ConfigPublish(_logger, version, "rejected", "schema_validation_failed");
            return new ConfigPublishResult(
                new ConfigPublishError(ConfigPublishErrorKind.SchemaValidationFailed,
                    string.Join(" | ", errors)));
        }

        // Rollback protection (docs/CONFIG.md rule 5): a document must always be
        // newer than the one currently published. <= not <, because re-publishing
        // the same version is equally a rollback.
        var highest = await _repository.GetHighestVersionAsync(cancellationToken);
        if (version <= highest)
        {
            TankbookLog.ConfigPublish(_logger, version, "rejected", "version_not_monotonic");
            return new ConfigPublishResult(
                new ConfigPublishError(ConfigPublishErrorKind.VersionNotMonotonic,
                    $"Document version {version} is not higher than the current highest version {highest}."));
        }

        // The signature covers the canonical serialization (deterministic key
        // ordering, see ConfigCanonicalizer) so the client reproduces the same
        // bytes. Sign the exact text that will be served.
        var canonical = ConfigCanonicalizer.Canonicalize(documentJson);
        var signature = _signer.Sign(canonical);

        var row = new ConfigDocumentRow(
            version,
            documentJson,
            signature,
            issuedAt,
            notAfter,
            DateTimeOffset.UtcNow);

        await _repository.InsertAsync(row, cancellationToken);

        TankbookLog.ConfigPublish(_logger, version, "published");
        return new ConfigPublishResult(ConfigPublishError.None, version);
    }

    private static bool TryReadEnvelope(
        string documentJson,
        out int version,
        out DateTimeOffset issuedAt,
        out DateTimeOffset notAfter)
    {
        version = 0;
        issuedAt = default;
        notAfter = default;

        try
        {
            using var document = JsonDocument.Parse(documentJson);
            if (document.RootElement.ValueKind != JsonValueKind.Object)
            {
                return false;
            }

            var root = document.RootElement;
            if (!root.TryGetProperty("version", out var versionElement) || !versionElement.TryGetInt32(out version))
            {
                return false;
            }

            if (!root.TryGetProperty("issuedAt", out var issuedElement) ||
                !DateTimeOffset.TryParse(issuedElement.GetString(), CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal, out issuedAt))
            {
                return false;
            }

            if (!root.TryGetProperty("notAfter", out var notAfterElement) ||
                !DateTimeOffset.TryParse(notAfterElement.GetString(), CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal, out notAfter))
            {
                return false;
            }

            return true;
        }
        catch (JsonException)
        {
            return false;
        }
    }
}

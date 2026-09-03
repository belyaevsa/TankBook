using Microsoft.Extensions.Options;
using Tankbook.Api.Logging;

namespace Tankbook.Api.Llm;

/// <summary>
/// The model resolved for one extract: which model to call, who its vendor is,
/// what it costs per token, and whether thinking is supported. The prices are
/// the dictionary snapshot the call ledger copies onto the call row (migration
/// 015) so a later price change cannot rewrite what an earlier call cost
/// (hard rule 3's rate-snapshot logic). <see cref="IsFallback"/> is true when
/// the resolution fell back to the compiled default because no setting row
/// named a known model.
/// </summary>
public sealed record LlmModelChoice(
    string ModelId,
    string Vendor,
    decimal InputPricePerToken,
    decimal OutputPricePerToken,
    string Currency,
    bool SupportsThinking,
    bool IsFallback);

/// <summary>
/// Resolves which model serves a given kind, per migration 014 (docs/API.md
/// "LLM gateway"). The resolution is a chain, and every step that cannot be
/// honoured degrades rather than throws - a missing or unknown setting must
/// never 500, because one bad DB row would otherwise take cloud extraction down
/// for everyone:
///
/// 1. Read llm_settings for the kind. A row names a model id.
/// 2. Read that model's current dictionary entry. Found -> use it.
/// 3. Unknown model id, or no setting row -> fall back to the compiled
///    <c>LlmGatewayOptions.ModelId</c>, and read its dictionary entry too. Each
///    fallback is logged at Warning so the operator sees the drift.
/// 4. Even the compiled default may be absent from the dictionary (a model
///    nobody has priced yet). Then the call still proceeds with the compiled
///    model id, no vendor, zero prices - extraction works, cost is recorded as
///    zero, and the Warning says why.
///
/// CACHE POLICY (decided 2026-09-03): read-per-request, no server-side cache.
/// The whole point of moving the model choice into data is to change it by a
/// direct DB write without a deploy or a restart, and a cache would cost exactly
/// that (a restart to change a model). The dictionary also carries
/// effective_from, so a scheduled price change must take effect at its date,
/// which a cache would also delay. The cost of the choice is two indexed
/// single-row reads per extract - negligible next to a paid model call that
/// takes seconds, and the extract route is rate-limited (30/min/device) anyway.
/// </summary>
public sealed class LlmModelResolver
{
    private readonly LlmModelRepository _repository;
    private readonly LlmGatewayOptions _options;
    private readonly ILogger<LlmModelResolver> _logger;
    private readonly TimeProvider _time;

    public LlmModelResolver(
        LlmModelRepository repository,
        IOptions<LlmGatewayOptions> options,
        ILogger<LlmModelResolver> logger,
        TimeProvider time)
    {
        _repository = repository;
        _options = options.Value;
        _logger = logger;
        _time = time;
    }

    public async Task<LlmModelChoice> ResolveAsync(string kind, CancellationToken cancellationToken)
    {
        var today = DateOnly.FromDateTime(_time.GetUtcNow().UtcDateTime);

        var settingModelId = await _repository.GetSettingForKindAsync(kind, cancellationToken);
        if (settingModelId is not null)
        {
            var settingEntry = await _repository.GetCurrentModelAsync(settingModelId, today, cancellationToken);
            if (settingEntry is not null)
            {
                return FromRow(settingEntry, IsFallback: false);
            }

            // The setting row names a model the dictionary does not know. Do not
            // fail the call: fall back to the compiled default, and say so.
            TankbookLog.LlmModelFallback(_logger, kind, settingModelId, _options.ModelId ?? string.Empty, "unknown_model");
        }
        else
        {
            // No per-kind override at all - the compiled default is the model.
            TankbookLog.LlmModelFallback(_logger, kind, string.Empty, _options.ModelId ?? string.Empty, "no_setting");
        }

        var defaultModelId = _options.ModelId;
        if (string.IsNullOrWhiteSpace(defaultModelId))
        {
            // Not even a compiled default is configured; the provider will
            // refuse the call, but resolution itself must not throw.
            return new LlmModelChoice(string.Empty, string.Empty, 0m, 0m, "USD", SupportsThinking: false, IsFallback: true);
        }

        var defaultEntry = await _repository.GetCurrentModelAsync(defaultModelId, today, cancellationToken);
        if (defaultEntry is not null)
        {
            return FromRow(defaultEntry, IsFallback: true);
        }

        // The compiled default has no dictionary entry: extraction still works,
        // cost is unknown (zero), and the warning names the gap.
        TankbookLog.LlmModelFallback(_logger, kind, defaultModelId, defaultModelId, "unpriced");
        return new LlmModelChoice(defaultModelId, string.Empty, 0m, 0m, "USD", SupportsThinking: false, IsFallback: true);
    }

    private static LlmModelChoice FromRow(LlmModelRow row, bool IsFallback)
        => new(
            row.ModelId,
            row.Vendor,
            row.InputPricePerToken,
            row.OutputPricePerToken,
            row.Currency,
            row.SupportsThinking,
            IsFallback);
}

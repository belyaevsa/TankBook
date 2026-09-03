using Tankbook.Api.Llm;

namespace Tankbook.Api.Tests.Llm;

/// <summary>
/// A scripted <see cref="ILlmProvider"/> double (docs/TESTING.md "mock the
/// boundary"): the endpoint talks to the model only through this interface, so
/// the L2 suite never makes a paid call. It records every invocation (count,
/// the bytes it was handed and the resolved model choice) so tests can assert
/// that an oversize image was rejected <em>before</em> the provider was ever
/// called, and that a provider failure was not metered. The handler is
/// reassignable per test.
/// </summary>
public sealed class RecordingLlmProvider : ILlmProvider
{
    private Func<string, byte[], ExtractHints, LlmModelChoice, LlmExtraction> _handler;

    public RecordingLlmProvider()
    {
        _handler = static (_, _, _, _) => new LlmExtraction(
            new Dictionary<string, LlmField>(StringComparer.Ordinal), "test-model", 0, 0);
    }

    public int CallCount { get; private set; }

    public IReadOnlyList<byte[]> Calls { get; private set; } = [];

    public IReadOnlyList<LlmModelChoice> ModelChoices { get; private set; } = [];

    public void SetHandler(Func<string, byte[], ExtractHints, LlmModelChoice, LlmExtraction> handler) => _handler = handler;

    public void SetFailure() => _handler = static (_, _, _, _) => throw new InvalidOperationException("provider down");

    public Task<LlmExtraction> ExtractAsync(
        string kind,
        byte[] imageBytes,
        ExtractHints hints,
        LlmModelChoice model,
        CancellationToken cancellationToken)
    {
        CallCount++;
        Calls = Calls.Append(imageBytes).ToList();
        ModelChoices = ModelChoices.Append(model).ToList();
        return Task.FromResult(_handler(kind, imageBytes, hints, model));
    }
}

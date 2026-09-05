namespace Tankbook.Api.Http;

/// <summary>
/// Builds the RFC 7807 problem+json error bodies every endpoint returns
/// (docs/API.md -> "Error envelope"). The `code` extension member is REQUIRED -
/// the parameter has no default so a call site that forgets it does not compile.
/// A code that is only sometimes present is worse than none, because the client
/// cannot rely on it (PR.9). The `traceId` extension member is added later by
/// the pipeline's CustomizeProblemDetails hook (Program.cs), so both members
/// ride every error body.
/// </summary>
public static class ProblemResponses
{
    public static IResult Problem(int status, string code, string title, string detail)
        => Results.Problem(
            statusCode: status,
            title: title,
            detail: detail,
            extensions: new Dictionary<string, object?>
            {
                [ErrorEnvelopeCodeKey] = code,
            });

    /// <summary>The problem+json member name (docs/API.md -> "Error envelope").</summary>
    public const string ErrorEnvelopeCodeKey = "code";
}

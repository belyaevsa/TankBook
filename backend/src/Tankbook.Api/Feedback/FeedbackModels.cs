namespace Tankbook.Api.Feedback;

/// <summary>
/// The POST /feedback body (docs/API.md -> Feedback). The wire sends the
/// category as the raw string; the endpoint validates it is one of the three
/// contract values. `deviceModel` rides only with the user's toggle; `replyTo`
/// is an optional contact address. `text` is bounded by the endpoint's body
/// cap (BodySizeLimits.FeedbackBytes) - the composer caps it at 4,000
/// characters, and the client's model type documents the same contract.
/// </summary>
public sealed record FeedbackRequest(
    string? Category,
    string? Text,
    string? AppVersion,
    string? DeviceModel,
    string? ReplyTo);

/// <summary>The three categories the documented contract accepts.</summary>
public static class FeedbackCategories
{
    public const string Feature = "feature";
    public const string Problem = "problem";
    public const string Other = "other";

    public static bool IsValid(string? value)
        => value is Feature or Problem or Other;
}

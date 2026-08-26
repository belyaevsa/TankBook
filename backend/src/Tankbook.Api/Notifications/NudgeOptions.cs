namespace Tankbook.Api.Notifications;

/// <summary>
/// Server-side sync-nudge behavior (docs/NOTIFICATIONS.md "Scenario catalog":
/// the sync nudge is "throttled server-side (max ~1/15 min per device)"). Bound
/// from the "Nudges" section; environment form Nudges__ThrottleWindowMinutes.
/// </summary>
public sealed class NudgeOptions
{
    public const string SectionName = "Nudges";

    /// <summary>Minimum quiet interval between two nudges to the same device. A burst of pushes collapses to one nudge per sibling device inside this window.</summary>
    public int ThrottleWindowMinutes { get; set; } = 15;

    public TimeSpan ThrottleWindow => TimeSpan.FromMinutes(ThrottleWindowMinutes);
}

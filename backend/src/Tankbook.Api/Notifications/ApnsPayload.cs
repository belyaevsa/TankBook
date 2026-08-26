using System.Text.Json;

namespace Tankbook.Api.Notifications;

/// <summary>
/// Builds the silent-push bodies the sync nudge sends (docs/NOTIFICATIONS.md:
/// "content-available, no alert, no sound, no text - the payload says only
/// 'pull'"). This is the one place a payload is composed, so the v1 hard rule -
/// no user-visible remote push, ever - lives here as a single, testable method:
/// nothing this class emits carries an alert, a sound, or a badge. The optional
/// config hint (docs/CONFIG.md "Push nudge") rides the same body as an
/// application key, not inside aps.
/// </summary>
public static class ApnsPayload
{
    /// <summary>
    /// The silent-push JSON body. <c>config: true</c> marks a config nudge; a
    /// plain sync nudge omits it entirely. The aps object contains exactly
    /// content-available and nothing else.
    /// </summary>
    public static string Silent(bool config)
    {
        using var stream = new MemoryStream();
        using (var writer = new Utf8JsonWriter(stream))
        {
            writer.WriteStartObject();
            writer.WritePropertyName("aps");
            writer.WriteStartObject();
            writer.WriteNumber("content-available", 1);
            writer.WriteEndObject();
            if (config)
            {
                writer.WriteBoolean("config", true);
            }

            writer.WriteEndObject();
        }

        return System.Text.Encoding.UTF8.GetString(stream.ToArray());
    }
}

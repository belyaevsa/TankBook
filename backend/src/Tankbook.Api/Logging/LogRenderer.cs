using System.Globalization;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace Tankbook.Api.Logging;

/// <summary>
/// Builds the final redacted log line from a raw log entry. This is where the
/// docs/LOGGING.md §2 common fields, §3 per-operation shape, and the redactor
/// meet: every named property is classified, the message is rendered from
/// redacted values only, and the correlation fields (traceId, accountHash,
/// deviceId, appVersion, platform) ride on every line.
/// </summary>
public sealed class LogRenderer
{
    private static readonly JsonSerializerOptions JsonOptions = new() { WriteIndented = false };

    private static readonly Regex TemplateToken =
        new(@"\{(@|\$)?([A-Za-z0-9_\.]+)(,([^}:]+))?\}", RegexOptions.Compiled);

    private readonly TankbookRedactor _redactor;
    private readonly string _appVersion;
    private readonly bool _json;

    public LogRenderer(TankbookRedactor redactor, string appVersion, bool json)
    {
        _redactor = redactor;
        _appVersion = appVersion;
        _json = json;
    }

    public string Render(
        LogLevel level,
        EventId eventId,
        object? state,
        Exception? exception,
        IReadOnlyList<KeyValuePair<string, object?>> scopeProperties)
    {
        var stateProperties = ExtractState(state, out var template);

        var eventName = ResolveEventName(eventId, stateProperties);

        var ordered = new List<KeyValuePair<string, object?>>();

        // Correlation fields: scope properties first (the middleware pushes
        // TraceId/AccountHash/DeviceId), state properties may override.
        var correlation = new Dictionary<string, object?>(StringComparer.OrdinalIgnoreCase);
        foreach (var (name, value) in scopeProperties)
        {
            if (IsCorrelationField(name))
            {
                correlation[name] = value;
            }
        }

        // Redact the named state properties. ErrorCode is reserved for the
        // error section below; Endpoint/EntityId/PayloadSize/JsonPointer are the
        // safe reproduction context and flow through as ordinary fields.
        var redactedFields = new List<RedactedField>();
        var errorCodeValue = (object?)null;
        foreach (var (name, value) in stateProperties)
        {
            if (IsCorrelationField(name))
            {
                correlation[name] = value;
                continue;
            }

            if (name.Equals("Event", StringComparison.OrdinalIgnoreCase))
            {
                continue;
            }

            if (name.Equals("ErrorCode", StringComparison.OrdinalIgnoreCase))
            {
                errorCodeValue = value;
                continue;
            }

            var redacted = _redactor.RedactProperty(name, value);
            if (redacted is not null)
            {
                redactedFields.Add(redacted);
            }
        }

        ordered.Add(new KeyValuePair<string, object?>("timestamp", UtcTimestamp()));
        ordered.Add(new KeyValuePair<string, object?>("level", level.ToString()));
        ordered.Add(new KeyValuePair<string, object?>("event", eventName));
        ordered.Add(new KeyValuePair<string, object?>("traceId", correlation.GetValueOrDefault("TraceId")));
        ordered.Add(new KeyValuePair<string, object?>("accountHash", correlation.GetValueOrDefault("AccountHash")));
        ordered.Add(new KeyValuePair<string, object?>("deviceId", correlation.GetValueOrDefault("DeviceId")));
        ordered.Add(new KeyValuePair<string, object?>("appVersion", _appVersion));
        ordered.Add(new KeyValuePair<string, object?>("platform", "server"));
        ordered.Add(new KeyValuePair<string, object?>("schemaVersion", correlation.GetValueOrDefault("SchemaVersion")));
        ordered.Add(new KeyValuePair<string, object?>("message", RenderMessage(template, eventName, redactedFields)));

        foreach (var field in redactedFields)
        {
            ordered.Add(new KeyValuePair<string, object?>(field.Name, field.Value));
        }

        // Error context (docs/LOGGING.md §3 Errors).
        if (exception is not null || errorCodeValue is not null)
        {
            ordered.Add(new KeyValuePair<string, object?>("errorCode", errorCodeValue ?? "internal_error"));
            ordered.Add(new KeyValuePair<string, object?>("exceptionType", exception?.GetType().Name));
            ordered.Add(new KeyValuePair<string, object?>("exceptionMessage", exception?.Message));
            ordered.Add(new KeyValuePair<string, object?>("stackTrace", exception?.ToString()));
        }

        return _json ? RenderJson(ordered) : RenderText(ordered);
    }

    private static IReadOnlyList<KeyValuePair<string, object?>> ExtractState(object? state, out string? template)
    {
        template = null;
        var result = new List<KeyValuePair<string, object?>>();

        if (state is string message)
        {
            template = message;
            return result;
        }

        if (state is not IEnumerable<KeyValuePair<string, object?>> pairs)
        {
            // Unknown state shape: keep it opaque (it cannot carry names to
            // classify) and never render its ToString into the message.
            return result;
        }

        foreach (var (name, value) in pairs)
        {
            if (name == "{OriginalFormat}")
            {
                template = value as string;
            }
            else
            {
                result.Add(new KeyValuePair<string, object?>(name, value));
            }
        }

        return result;
    }

    private static string ResolveEventName(EventId eventId, IReadOnlyList<KeyValuePair<string, object?>> stateProperties)
    {
        foreach (var (name, value) in stateProperties)
        {
            if (name.Equals("Event", StringComparison.OrdinalIgnoreCase) &&
                value is string named && !string.IsNullOrWhiteSpace(named))
            {
                return named;
            }
        }

        return string.IsNullOrWhiteSpace(eventId.Name) ? "log" : eventId.Name;
    }

    private static bool IsCorrelationField(string name) =>
        name.Equals("TraceId", StringComparison.OrdinalIgnoreCase) ||
        name.Equals("AccountHash", StringComparison.OrdinalIgnoreCase) ||
        name.Equals("DeviceId", StringComparison.OrdinalIgnoreCase) ||
        name.Equals("SchemaVersion", StringComparison.OrdinalIgnoreCase);

    private static string RenderMessage(string? template, string eventName, IReadOnlyList<RedactedField> fields)
    {
        if (template is null)
        {
            return eventName;
        }

        var byName = fields.ToDictionary(f => f.Name, f => f.Value, StringComparer.OrdinalIgnoreCase);
        return TemplateToken.Replace(template, match =>
        {
            var name = match.Groups[2].Value;
            if (byName.TryGetValue(name, out var value))
            {
                return FormatValue(value);
            }

            return match.Value;
        });
    }

    private static string FormatValue(object? value)
    {
        return value switch
        {
            null => "null",
            string s => s,
            IFormattable f => f.ToString(null, CultureInfo.InvariantCulture),
            _ => JsonSerializer.Serialize(value, JsonOptions),
        };
    }

    private static string RenderJson(IReadOnlyList<KeyValuePair<string, object?>> fields)
    {
        var buffer = new StringBuilder();
        using var writer = new Utf8JsonWriter(new StringBuilderStream(buffer));
        writer.WriteStartObject();
        foreach (var (name, value) in fields)
        {
            WriteField(writer, name, value);
        }
        writer.WriteEndObject();
        writer.Flush();
        return buffer.ToString();
    }

    private static string RenderText(IReadOnlyList<KeyValuePair<string, object?>> fields)
    {
        var buffer = new StringBuilder();
        foreach (var (name, value) in fields)
        {
            if (name == "message")
            {
                continue;
            }

            if (buffer.Length > 0)
            {
                buffer.Append(' ');
            }

            buffer.Append(name).Append('=').Append(FormatValue(value));
        }

        var message = fields.FirstOrDefault(f => f.Key == "message").Value as string;
        return $"{fields.First(f => f.Key == "level").Value}: {message} [{buffer}]";
    }

    private static void WriteField(Utf8JsonWriter writer, string name, object? value)
    {
        switch (value)
        {
            case null:
                writer.WriteNull(name);
                break;
            case string s:
                writer.WriteString(name, s);
                break;
            case bool b:
                writer.WriteBoolean(name, b);
                break;
            case byte or sbyte or short or ushort or int or uint or long or ulong:
                writer.WriteNumber(name, Convert.ToInt64(value, CultureInfo.InvariantCulture));
                break;
            case float f:
                writer.WriteNumber(name, f);
                break;
            case double d:
                writer.WriteNumber(name, d);
                break;
            case decimal m:
                writer.WriteNumber(name, m);
                break;
            case Guid g:
                writer.WriteString(name, g.ToString());
                break;
            case DateTime dt:
                writer.WriteString(name, dt.ToUniversalTime().ToString("O", CultureInfo.InvariantCulture));
                break;
            case DateTimeOffset dto:
                writer.WriteString(name, dto.ToUniversalTime().ToString("O", CultureInfo.InvariantCulture));
                break;
            case TimeSpan ts:
                writer.WriteNumber(name, ts.TotalMilliseconds);
                break;
            case IDictionary<string, object?> map:
                writer.WriteStartObject(name);
                foreach (var (key, entryValue) in map)
                {
                    WriteField(writer, key, entryValue);
                }
                writer.WriteEndObject();
                break;
            case IEnumerable<object?> list:
                writer.WriteStartArray(name);
                foreach (var item in list)
                {
                    WriteValue(writer, item);
                }
                writer.WriteEndArray();
                break;
            default:
                writer.WriteString(name, Convert.ToString(value, CultureInfo.InvariantCulture));
                break;
        }
    }

    private static void WriteValue(Utf8JsonWriter writer, object? value)
    {
        switch (value)
        {
            case null:
                writer.WriteNullValue();
                break;
            case string s:
                writer.WriteStringValue(s);
                break;
            case bool b:
                writer.WriteBooleanValue(b);
                break;
            case byte or sbyte or short or ushort or int or uint or long or ulong:
                writer.WriteNumberValue(Convert.ToInt64(value, CultureInfo.InvariantCulture));
                break;
            case float f:
                writer.WriteNumberValue(f);
                break;
            case double d:
                writer.WriteNumberValue(d);
                break;
            case decimal m:
                writer.WriteNumberValue(m);
                break;
            case IDictionary<string, object?> map:
                writer.WriteStartObject();
                foreach (var (key, entryValue) in map)
                {
                    WriteField(writer, key, entryValue);
                }
                writer.WriteEndObject();
                break;
            case IEnumerable<object?> list:
                writer.WriteStartArray();
                foreach (var item in list)
                {
                    WriteValue(writer, item);
                }
                writer.WriteEndArray();
                break;
            default:
                writer.WriteStringValue(Convert.ToString(value, CultureInfo.InvariantCulture));
                break;
        }
    }

    private static string UtcTimestamp() =>
        DateTime.UtcNow.ToString("yyyy-MM-ddTHH:mm:ss.fffZ", CultureInfo.InvariantCulture);

    /// <summary>A writable TextWriter over a StringBuilder for Utf8JsonWriter.</summary>
    private sealed class StringBuilderStream : Stream
    {
        private readonly StringBuilder _builder;
        private readonly UTF8Encoding _encoding = new(false);

        public StringBuilderStream(StringBuilder builder) => _builder = builder;

        public override bool CanRead => false;
        public override bool CanSeek => false;
        public override bool CanWrite => true;
        public override long Length => throw new NotSupportedException();
        public override long Position
        {
            get => throw new NotSupportedException();
            set => throw new NotSupportedException();
        }

        public override void Flush() { }

        public override int Read(byte[] buffer, int offset, int count) => throw new NotSupportedException();

        public override long Seek(long offset, SeekOrigin origin) => throw new NotSupportedException();

        public override void SetLength(long value) => throw new NotSupportedException();

        public override void Write(byte[] buffer, int offset, int count)
        {
            _builder.Append(_encoding.GetString(buffer, offset, count));
        }
    }
}

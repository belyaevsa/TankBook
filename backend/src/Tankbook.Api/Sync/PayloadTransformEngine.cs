using System.Text.Json;
using System.Text.Json.Nodes;

namespace Tankbook.Api.Sync;

/// <summary>
/// Applies declarative, ordered payload migrations (docs/SYNC.md "Migrating
/// payloads"): pure JSON surgery with no domain knowledge and no C# type per
/// entity. Operations are <c>rename</c>, <c>addDefault</c>, <c>wrap</c> and
/// <c>removeDeprecated</c>. Each operation is naturally idempotent (a second
/// application is a no-op), and an unknown operation is refused rather than
/// silently skipped so a broken transform cannot corrupt data quietly.
///
/// Transform JSON shape (an ordered array of operation objects):
/// <code>
/// [
///   { "op": "rename",          "at": "/",      "from": "oldName", "to": "newName" },
///   { "op": "addDefault",      "at": "/",      "name": "field",   "value": { ... } },
///   { "op": "wrap",            "at": "/",      "name": "field",   "into": "wrapper", "as": "inner" },
///   { "op": "removeDeprecated", "at": "/field" }
/// ]
/// </code>
/// <c>at</c> is a JSON pointer to the containing object ("/" or "" = the root);
/// it may also be written as a JSON object <c>{ "ops": [ ... ] }</c>.
/// </summary>
public sealed class PayloadTransformEngine
{
    private static readonly HashSet<string> KnownOperations =
        new(StringComparer.Ordinal) { "rename", "addDefault", "wrap", "removeDeprecated" };

    /// <summary>Applies a transform (as JSON text) to a payload (as JSON text).</summary>
    public string Apply(string payloadJson, string transformJson)
    {
        JsonNode? payloadNode = JsonNode.Parse(payloadJson);
        if (payloadNode is not JsonObject payload)
        {
            throw new ArgumentException("Payload must be a JSON object.", nameof(payloadJson));
        }

        var operations = ParseOperations(transformJson);
        foreach (var operation in operations)
        {
            ApplyOperation(payload, operation);
        }

        return payload.ToJsonString();
    }

    private static IReadOnlyList<JsonObject> ParseOperations(string transformJson)
    {
        var transform = JsonNode.Parse(transformJson) ?? throw new ArgumentException("Transform must not be null.", nameof(transformJson));

        var list = transform switch
        {
            JsonArray array => array,
            JsonObject wrapper when wrapper["ops"] is JsonArray ops => ops,
            _ => throw new ArgumentException("Transform must be a JSON array of operations or an object with an \"ops\" array.", nameof(transformJson)),
        };

        var operations = new List<JsonObject>(list.Count);
        foreach (var item in list)
        {
            if (item is not JsonObject operation)
            {
                throw new InvalidOperationException("Every transform operation must be a JSON object.");
            }

            var name = operation["op"]?.GetValue<string>();
            if (string.IsNullOrEmpty(name) || !KnownOperations.Contains(name))
            {
                throw new InvalidOperationException(
                    $"Unknown transform operation '{(name is null ? string.Empty : name)}'. Known operations: rename, addDefault, wrap, removeDeprecated.");
            }

            operations.Add(operation);
        }

        return operations;
    }

    private static void ApplyOperation(JsonObject root, JsonObject operation)
    {
        var name = operation["op"]!.GetValue<string>();
        switch (name)
        {
            case "rename":
                ApplyRename(root, operation);
                break;
            case "addDefault":
                ApplyAddDefault(root, operation);
                break;
            case "wrap":
                ApplyWrap(root, operation);
                break;
            case "removeDeprecated":
                ApplyRemoveDeprecated(root, operation);
                break;
            default:
                throw new InvalidOperationException($"Unknown transform operation '{name}'.");
        }
    }

    private static void ApplyRename(JsonObject root, JsonObject operation)
    {
        var from = RequiredString(operation, "from");
        var to = RequiredString(operation, "to");
        var parent = ResolveParent(root, operation, "at");

        if (parent is null || !parent.Remove(from, out var value) || value is null)
        {
            return; // nothing to rename - already applied (idempotent)
        }

        parent[to] = value;
    }

    private static void ApplyAddDefault(JsonObject root, JsonObject operation)
    {
        var name = RequiredString(operation, "name");
        var value = operation["value"] ?? throw new InvalidOperationException("addDefault requires a \"value\".");
        var parent = ResolveParent(root, operation, "at");

        if (parent is null || parent.ContainsKey(name))
        {
            return; // already present - idempotent
        }

        parent[name] = value.DeepClone();
    }

    private static void ApplyWrap(JsonObject root, JsonObject operation)
    {
        var name = RequiredString(operation, "name");
        var into = RequiredString(operation, "into");
        var asName = operation["as"]?.GetValue<string>() ?? name;
        var parent = ResolveParent(root, operation, "at");

        if (parent is null || !parent.Remove(name, out var value) || value is null)
        {
            return; // nothing to wrap - already applied (idempotent)
        }

        if (!parent.TryGetPropertyValue(into, out var wrapperNode) || wrapperNode is null)
        {
            var wrapper = new JsonObject();
            parent[into] = wrapper;
            wrapper[asName] = value;
        }
        else if (wrapperNode is JsonObject wrapper)
        {
            wrapper[asName] = value;
        }
        // wrapper exists but is not an object: leave the payload untouched.
    }

    private static void ApplyRemoveDeprecated(JsonObject root, JsonObject operation)
    {
        var name = RequiredString(operation, "name");
        var parent = ResolveParent(root, operation, "at");

        parent?.Remove(name); // absent is fine - idempotent
    }

    /// <summary>Resolves the containing object for an "at" pointer, or null when absent.</summary>
    private static JsonObject? ResolveParent(JsonObject root, JsonObject operation, string key)
    {
        var at = operation[key]?.GetValue<string>();
        if (string.IsNullOrEmpty(at) || at == "/")
        {
            return root;
        }

        JsonNode? current = root;
        foreach (var rawSegment in at.Split('/'))
        {
            if (rawSegment.Length == 0)
            {
                continue; // leading slash
            }

            var segment = UnescapePointerSegment(rawSegment);
            if (current is not JsonObject obj || !obj.TryGetPropertyValue(segment, out var next) || next is null)
            {
                return null;
            }

            current = next;
        }

        return current as JsonObject;
    }

    private static string RequiredString(JsonObject operation, string property)
    {
        if (operation[property] is not JsonValue value || !value.TryGetValue<string>(out var result) || string.IsNullOrEmpty(result))
        {
            throw new InvalidOperationException($"Transform operation '{operation["op"]?.GetValue<string>()}' requires a non-empty \"{property}\".");
        }

        return result;
    }

    private static string UnescapePointerSegment(string segment)
        => segment.Replace("~1", "/", StringComparison.Ordinal)
                  .Replace("~0", "~", StringComparison.Ordinal);
}

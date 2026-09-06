using System.Collections;
using System.Reflection;

namespace Tankbook.Api.Logging;

/// <summary>
/// The enforcement point for docs/LOGGING.md §1, not a convention: every value
/// that reaches the logging pipeline is classified here before it can be
/// written. Never values are dropped, Sensitive values are masked (email becomes
/// a salted emailHash - distinct from the accountHash correlation field, RV.63),
/// Safe values pass through. Because classification happens in the pipeline, a
/// careless call site that logs a whole entity or a named field cannot leak a
/// Sensitive or Never value.
/// </summary>
public sealed class TankbookRedactor
{
    /// <summary>Sentinel that replaces a masked Sensitive value in the output.</summary>
    public const string Masked = "***";

    private readonly string _hashSalt;
    private readonly bool _maskSensitive;

    public TankbookRedactor(string hashSalt, bool maskSensitive = true)
    {
        _hashSalt = hashSalt;
        _maskSensitive = maskSensitive;
    }

    /// <summary>
    /// Classifies one named property: null means drop the field entirely;
    /// otherwise the returned field carries the (possibly renamed / masked)
    /// value to write. Email is masked under the distinct key emailHash, never
    /// accountHash: the redactor has no account context here - it sees an email
    /// value, not an account id - so its hash cannot be the account identifier,
    /// and labelling it as one would silently break log correlation (RV.63).
    /// The account-id hash appears only where the account is actually resolved
    /// (AccountHash.ForAccount, the bearer scope and the auth/account events).
    /// </summary>
    public RedactedField? RedactProperty(string fieldName, object? value)
    {
        if (SensitiveFieldCatalog.IsNever(fieldName))
        {
            return null;
        }

        if (SensitiveFieldCatalog.IsEmail(fieldName))
        {
            var hashed = value is null
                ? null
                : AccountHash.ForEmail(Convert.ToString(value, System.Globalization.CultureInfo.InvariantCulture)!, _hashSalt);
            return new RedactedField("emailHash", hashed);
        }

        var sensitive = SensitiveFieldCatalog.IsSensitive(fieldName) ||
                        SensitiveFieldCatalog.IsSensitiveValue(fieldName, value);
        if (sensitive && _maskSensitive)
        {
            return new RedactedField(fieldName, Masked);
        }

        return new RedactedField(fieldName, RedactValue(value));
    }

    /// <summary>
    /// Deep-redacts a value that has no field-name context at this level:
    /// dictionaries, objects and collections are walked and each member is
    /// classified by its own name.
    /// </summary>
    public object? RedactValue(object? value)
    {
        switch (value)
        {
            case null:
                return null;
            case byte[]:
            case Stream:
                // Blob bytes and streams are Never class whatever they are named.
                return null;
            case string or bool or byte or sbyte or short or ushort or int or uint or long or ulong
                or float or double or decimal or char or Guid or DateTime or DateTimeOffset or TimeSpan or DateOnly:
                return value;
            // RV.90: reflection types are rendered by NAME, never walked.
            // `Type.StructLayoutAttribute` returns an attribute that points
            // back at a type, so reflecting over one `Type` value sends the
            // walker around the runtime's own type graph until the stack is
            // gone - measured as a test-host "Stack overflow" crash on a real
            // POST /v1/import/parse, with the captured path reading
            // `RuntimeType -> StructLayoutAttribute -> RuntimeType -> ...`.
            // A name is also all a log line could honestly want from one.
            case Type type:
                return type.Name;
            case MemberInfo member:
                return member.Name;
            case Assembly assembly:
                return assembly.GetName().Name;
            case Attribute attribute:
                return attribute.GetType().Name;
            case IDictionary<string, object?> map:
                {
                    var result = new Dictionary<string, object?>(StringComparer.OrdinalIgnoreCase);
                    foreach (var (key, entryValue) in map)
                    {
                        var redacted = RedactProperty(key, entryValue);
                        if (redacted is not null)
                        {
                            result[redacted.Name] = redacted.Value;
                        }
                    }
                    return result;
                }
            case IDictionary nonGeneric:
                {
                    var result = new Dictionary<string, object?>(StringComparer.OrdinalIgnoreCase);
                    foreach (DictionaryEntry entry in nonGeneric)
                    {
                        var key = Convert.ToString(entry.Key, System.Globalization.CultureInfo.InvariantCulture);
                        if (key is null)
                        {
                            continue;
                        }

                        var redacted = RedactProperty(key, entry.Value);
                        if (redacted is not null)
                        {
                            result[redacted.Name] = redacted.Value;
                        }
                    }
                    return result;
                }
            case IEnumerable sequence:
                {
                    var result = new List<object?>();
                    foreach (var item in sequence)
                    {
                        result.Add(RedactValue(item));
                    }
                    return result;
                }
            default:
                return RedactObject(value);
        }
    }

    /// <summary>
    /// RV.90: how deep the walker may follow an object graph before it stops
    /// and says so. A cap is the guard that cannot be out-thought: naming the
    /// one cyclic type that caused the crash (`Type`, above) fixes the case we
    /// measured, and this fixes the case we have not - a log line must never be
    /// able to take the process down, whatever graph a caller hands it. 40 is
    /// far past any real log payload; the deepest shape in the app is a parsed
    /// import candidate at single digits.
    /// </summary>
    private const int MaxDepth = 40;

    /// <summary>Marks where a graph was cut, so a reader is never told a
    /// truncated object ended naturally.</summary>
    public const string Truncated = "<truncated: too deep>";

    [ThreadStatic] private static int _depth;

    private object? RedactObject(object value)
    {
        if (_depth >= MaxDepth)
        {
            return Truncated;
        }

        _depth++;
        try
        {
            var result = new Dictionary<string, object?>(StringComparer.OrdinalIgnoreCase);

            foreach (var property in value.GetType().GetProperties(System.Reflection.BindingFlags.Public | System.Reflection.BindingFlags.Instance))
            {
                if (property.GetIndexParameters().Length > 0)
                {
                    continue;
                }

                object? propertyValue;
                try
                {
                    propertyValue = property.GetValue(value);
                }
                catch
                {
                    continue;
                }

                var redacted = RedactProperty(property.Name, propertyValue);
                if (redacted is not null)
                {
                    result[redacted.Name] = redacted.Value;
                }
            }

            return result;
        }
        finally
        {
            _depth--;
        }
    }
}

/// <summary>Result of classifying one property: the name to write and the value, or null to drop.</summary>
public sealed record RedactedField(string Name, object? Value);

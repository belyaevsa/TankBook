using System.Collections;

namespace Tankbook.Api.Logging;

/// <summary>
/// The enforcement point for docs/LOGGING.md §1, not a convention: every value
/// that reaches the logging pipeline is classified here before it can be
/// written. Never values are dropped, Sensitive values are masked (email becomes
/// a salted accountHash), Safe values pass through. Because classification
/// happens in the pipeline, a careless call site that logs a whole entity or a
/// named field cannot leak a Sensitive or Never value.
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
    /// value to write. Email is renamed to accountHash so the correlation hash
    /// replaces the address instead of riding under the same key.
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
                : AccountHash.Compute(Convert.ToString(value, System.Globalization.CultureInfo.InvariantCulture)!, _hashSalt);
            return new RedactedField("accountHash", hashed);
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

    private object? RedactObject(object value)
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
}

/// <summary>Result of classifying one property: the name to write and the value, or null to drop.</summary>
public sealed record RedactedField(string Name, object? Value);

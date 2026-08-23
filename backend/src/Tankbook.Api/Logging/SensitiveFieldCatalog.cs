namespace Tankbook.Api.Logging;

/// <summary>
/// The canonical field-name sets behind docs/LOGGING.md §1. Every property that
/// reaches the logging pipeline is classified here by its field name, so a
/// careless call site cannot bypass the rules by forgetting to redact. Field
/// names follow docs/SCHEMA.md's canonical spelling, matched case-insensitively.
/// </summary>
public static class SensitiveFieldCatalog
{
    /// <summary>
    /// Never class: never logged at any level, in any build. These properties
    /// are dropped from the output entirely, not masked.
    /// </summary>
    public static readonly IReadOnlySet<string> Never = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
    {
        // Payload bodies (docs/SYNC.md records.payload) - the server never
        // interprets them, and never logs them.
        "payload",
        // Credentials and tokens.
        "token", "accesstoken", "refreshtoken", "idtoken", "apnstoken", "fcmtoken",
        "pushtoken", "apikey", "password", "passphrase", "clientsecret",
        "secret", "secretkey", "accesskey",
        // Image and OCR content (docs/LOGGING.md Never: blob bytes, images, OCR text).
        "image", "images", "photo", "photos", "imagebytes", "imagebase64",
        "bytes", "ocrtext", "ocrraw", "blobdata",
        // Signed URLs - blob.get logs presignTtlSec, never the URL.
        "presignedurl", "signedurl", "uploadurl", "downloadurl",
        "url", "uri", "href", "base64",
    };

    /// <summary>
    /// Sensitive class: never logged in production. These properties are masked
    /// (replaced by a sentinel) unless RedactSensitiveValues is explicitly off.
    /// </summary>
    public static readonly IReadOnlySet<string> Sensitive = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
    {
        // Station and vendor names, free-text names and titles (Vehicle.name,
        // ServiceItem.title, ChargeSession.provider).
        "stationname", "station", "vendorname", "vendor", "name", "title",
        "notes", "note", "memo", "comment", "description",
        // Plate.
        "plate", "licenceplate", "registrationplate", "registration",
        // Monetary amounts (Money.amount, homeAmount, unitPrice, ServiceItem.cost).
        "amount", "homeamount", "money", "cost", "price", "unitprice",
        "priceperkwh", "priceperliter", "rate", "total", "grandtotal",
        // Volumes and capacities.
        "volumel", "volume", "litres", "liters", "energykwh",
        "tankcapacityl", "batterycapacitykwh",
        // Odometer.
        "odometer",
        // Coordinates.
        "coordinates", "lat", "lng", "lon", "latitude", "longitude", "latlng",
        "address", "locality",
        // Filenames and storage keys (attachment ids are UUIDs and stay Safe).
        "filename", "storageref",
        // Contact and identity (email becomes a salted accountHash instead).
        "email", "emailaddress", "mail", "phone", "phonenumber",
        "cardnumber", "accountnumber", "iban", "bic",
        // Fuel marketing tier is station-issued free text ("V-Power").
        "fuelgrade",
    };

    /// <summary>
    /// Field names that are sometimes a Safe enum token and sometimes user
    /// content. The value decides: a known enum token passes through, anything
    /// else is Sensitive. (ChargeSession.provider is a vendor name, but
    /// auth.session.provider is "apple"/"google".)
    /// </summary>
    public static readonly IReadOnlyDictionary<string, IReadOnlySet<string>> EnumTokensByField =
        new Dictionary<string, IReadOnlySet<string>>(StringComparer.OrdinalIgnoreCase)
        {
            ["provider"] = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { "apple", "google" },
        };

    public static bool IsNever(string fieldName) => Never.Contains(fieldName);

    public static bool IsSensitive(string fieldName) => Sensitive.Contains(fieldName);

    public static bool IsEmail(string fieldName) =>
        fieldName.Equals("email", StringComparison.OrdinalIgnoreCase) ||
        fieldName.Equals("emailaddress", StringComparison.OrdinalIgnoreCase) ||
        fieldName.Equals("mail", StringComparison.OrdinalIgnoreCase);

    /// <summary>
    /// True when the field name is ambiguous (sometimes Safe enum, sometimes
    /// content) and this value is not one of its known tokens.
    /// </summary>
    public static bool IsSensitiveValue(string fieldName, object? value)
    {
        if (!EnumTokensByField.TryGetValue(fieldName, out var tokens))
        {
            return false;
        }

        if (value is null)
        {
            return false;
        }

        return !tokens.Contains(Convert.ToString(value, System.Globalization.CultureInfo.InvariantCulture) ?? "");
    }
}

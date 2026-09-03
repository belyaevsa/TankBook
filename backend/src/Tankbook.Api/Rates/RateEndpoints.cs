using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Microsoft.Extensions.Options;

namespace Tankbook.Api.Rates;

/// <summary>
/// GET /v1/rates and GET /v1/rates/pack (docs/API.md reference data). Both are
/// PUBLIC - no auth, no account - because guests and signed-out users need rates
/// too. A past date's quotes are immutable (the ECB/CIS feed for yesterday never
/// changes), so they carry <c>Cache-Control: immutable</c>; today's row can still
/// change (a late publish or a correction), so it is served revalidatable. ETag
/// mirrors GET /config. A date with no data answers an empty quote set - never a
/// neighbouring date's value: carry-forward is a stored row with its own date,
/// not a read-time guess (docs/SCHEMA.md).
/// </summary>
public static class RateEndpoints
{
    public const string ImmutableCacheControl = "public, max-age=31536000, immutable";
    public const string ProvisionalCacheControl = "max-age=300, must-revalidate";

    // Camel-case property names, matching the rest of the wire surface
    // (docs/API.md examples use accessToken / nextSince / etc.).
    private static readonly JsonSerializerOptions WireJson = new(JsonSerializerDefaults.Web);

    public static async Task<IResult> GetRates(
        string? date,
        string? @base,
        RateRepository repository,
        TimeProvider time,
        HttpContext httpContext,
        CancellationToken cancellationToken)
    {
        if (!TryParseDate(date, out var day))
        {
            return InvalidRequest("The 'date' query parameter must be an ISO-8601 date (yyyy-MM-dd).");
        }

        if (!IsValidCurrency(@base))
        {
            return InvalidRequest("The 'base' query parameter must be a three-letter ISO 4217 currency code.");
        }

        var rows = await repository.GetForDateAsync(day, @base!, cancellationToken);
        var body = JsonSerializer.Serialize(new RatesDateResponse(
            day,
            @base!,
            rows.Select(r => new RateQuoteResponse(r.Quote, r.Rate, r.Source)).ToList()),
            WireJson);

        return Serve(httpContext, body, immutable: day < Today(time));
    }

    public static async Task<IResult> GetRatesPack(
        string? from,
        string? to,
        string? @base,
        RateRepository repository,
        RateBackfillService backfill,
        TimeProvider time,
        IOptions<RateOptions> options,
        HttpContext httpContext,
        CancellationToken cancellationToken)
    {
        if (!TryParseDate(from, out var fromDay) || !TryParseDate(to, out var toDay))
        {
            return InvalidRequest("The 'from' and 'to' query parameters must be ISO-8601 dates (yyyy-MM-dd).");
        }

        if (!IsValidCurrency(@base))
        {
            return InvalidRequest("The 'base' query parameter must be a three-letter ISO 4217 currency code.");
        }

        if (fromDay > toDay)
        {
            return InvalidRequest("The 'from' date must not be after the 'to' date.");
        }

        var maxDays = options.Value.MaxPackDays;
        if (toDay.DayNumber - fromDay.DayNumber + 1 > maxDays)
        {
            return InvalidRequest($"The requested range exceeds the maximum of {maxDays} days.");
        }

        var rows = await repository.GetRangeAsync(fromDay, toDay, @base!, cancellationToken);
        var body = JsonSerializer.Serialize(new RatesPackResponse(
            fromDay,
            toDay,
            @base!,
            rows.Select(r => new RatePackItem(r.Date, r.Quote, r.Rate, r.Source)).ToList()),
            WireJson);

        // The request is the trigger (docs/SCHEMA.md "Exchange rates"): queue any
        // date in this range that has no rate yet, so the background backfill
        // fetches it. The response returns what exists NOW - it never waits on the
        // fetch, which could be hundreds of upstream requests. A device still
        // missing a rate re-asks on its next foreground refresh and picks it up.
        await backfill.RecordRequestAsync(fromDay, toDay, @base!, cancellationToken);

        // A range fully in the past can never change; a range reaching today is provisional.
        httpContext.Response.Headers.CacheControl = toDay < Today(time) ? ImmutableCacheControl : ProvisionalCacheControl;
        return Results.Text(body, "application/json");
    }

    /// <summary>Serializes the date response, sets the cache policy for the day's age, and answers 304 on a matching ETag.</summary>
    private static IResult Serve(HttpContext httpContext, string body, bool immutable)
    {
        var etag = ComputeEtag(body);
        httpContext.Response.Headers.CacheControl = immutable ? ImmutableCacheControl : ProvisionalCacheControl;

        if (IfNoneMatchMatches(httpContext.Request, etag))
        {
            httpContext.Response.Headers.ETag = etag;
            return Results.StatusCode(StatusCodes.Status304NotModified);
        }

        httpContext.Response.Headers.ETag = etag;
        return Results.Text(body, "application/json");
    }

    private static IResult InvalidRequest(string detail)
        => Results.Problem(statusCode: StatusCodes.Status400BadRequest, title: "Invalid rates request.", detail: detail);

    private static DateOnly Today(TimeProvider time) => DateOnly.FromDateTime(time.GetUtcNow().UtcDateTime);

    private static bool IsValidCurrency(string? code)
        => code is { Length: 3 } && code.All(c => c is >= 'A' and <= 'Z');

    private static bool TryParseDate(string? value, out DateOnly date)
    {
        date = default;
        return value is not null && DateOnly.TryParseExact(value, "yyyy-MM-dd", out date);
    }

    internal static string ComputeEtag(string body)
    {
        using var sha = SHA256.Create();
        return $"\"{Convert.ToHexString(sha.ComputeHash(Encoding.UTF8.GetBytes(body))).ToLowerInvariant()}\"";
    }

    private static bool IfNoneMatchMatches(HttpRequest request, string etag)
    {
        var header = request.Headers.IfNoneMatch.ToString();
        if (string.IsNullOrWhiteSpace(header))
        {
            return false;
        }

        if (header == "*")
        {
            return true;
        }

        foreach (var candidate in header.Split(','))
        {
            var normalized = candidate.Trim();
            if (normalized.StartsWith("W/", StringComparison.Ordinal))
            {
                normalized = normalized[2..].Trim();
            }

            if (normalized == etag)
            {
                return true;
            }
        }

        return false;
    }

    private sealed record RateQuoteResponse(string Quote, decimal Rate, string Source);

    private sealed record RatesDateResponse(DateOnly Date, string Base, IReadOnlyList<RateQuoteResponse> Quotes);

    private sealed record RatesPackResponse(DateOnly From, DateOnly To, string Base, IReadOnlyList<RatePackItem> Rates);

    private sealed record RatePackItem(DateOnly Date, string Quote, decimal Rate, string Source);
}

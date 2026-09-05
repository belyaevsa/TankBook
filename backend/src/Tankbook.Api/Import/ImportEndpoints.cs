using System.Text;
using System.Text.Json;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Options;
using Tankbook.Api.Auth;
using Tankbook.Api.Http;
using Tankbook.Api.Logging;

namespace Tankbook.Api.Import;

/// <summary>
/// The import HTTP surface (docs/API.md "Import parsing"): GET /v1/import/formats
/// (public, ETag'd), POST /v1/import/parse (multipart, bearer optional - import
/// must work signed out), and GET/DELETE /v1/import/{importId} (public, bearer
/// optional; account-owned parses answer 404 to everyone but their owner).
/// The user declares the format; the server never sniffs it (docs/ERRORS.md
/// -> Import wizard).
/// </summary>
public static class ImportEndpoints
{
    private static readonly JsonSerializerOptions WireJson = new(JsonSerializerDefaults.Web);

    public const string CacheControl = "public, max-age=300, must-revalidate";

    /// <summary>GET /v1/import/formats - the supported-source list, server-driven and public (docs/API.md).</summary>
    public static IResult Formats(HttpContext httpContext)
    {
        var body = JsonSerializer.Serialize(
            ImportFormats.All.Select(f => new FormatResponse(f.Id, f.DisplayName, f.FileKinds, f.HelpUrl, f.AddedInPackVersion)),
            WireJson);

        httpContext.Response.Headers.CacheControl = CacheControl;
        var etag = EtagHelpers.ComputeEtag(body);
        httpContext.Response.Headers.ETag = etag;

        if (EtagHelpers.IfNoneMatchMatches(httpContext.Request, etag))
        {
            return Results.StatusCode(StatusCodes.Status304NotModified);
        }

        return Results.Text(body, "application/json");
    }

    /// <summary>
    /// POST /v1/import/parse - hard rule 9's named exception. Multipart upload of
    /// a third-party export; the format is declared by the user, never sniffed.
    /// Commits nothing; returns candidate proposals the device reviews and writes
    /// (hard rules 9 and 13). 413 oversize, 415 unknown format, 422 the file does
    /// not look like the declared format.
    /// </summary>
    public static async Task<IResult> Parse(
        [FromForm] string? format,
        IFormFile? file,
        ImportService imports,
        HttpContext httpContext,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(format) || !ImportFormats.TryGet(format, out _))
        {
            return Problem(
                StatusCodes.Status415UnsupportedMediaType,
                TankbookErrorCodes.ImportFormatUnsupported,
                "Unsupported format.",
                "Choose the app this file came from; the file's format is not offered.");
        }

        if (file is null || file.Length == 0)
        {
            return Problem(
                StatusCodes.Status400BadRequest,
                TankbookErrorCodes.PayloadInvalid,
                "Missing file.",
                "Attach the export file to upload.");
        }

        // Import must work signed out (docs/API.md): the bearer is optional. With
        // an account the parse is stored under the account; otherwise under the
        // device identity.
        var identity = AuthContext.From(httpContext);
        var accountId = identity?.AccountId;
        Guid? deviceId = identity?.DeviceId;
        if (deviceId is null)
        {
            var headerDevice = httpContext.Request.Headers["X-Device-Id"].FirstOrDefault();
            if (headerDevice is null || !Guid.TryParse(headerDevice, out var parsedDevice))
            {
                return Problem(
                StatusCodes.Status400BadRequest,
                TankbookErrorCodes.PayloadInvalid,
                "Missing device identity.",
                "A device id (X-Device-Id) is required when signed out so the stored file can be purged.");
            }

            deviceId = parsedDevice;
        }

        try
        {
            await using var stream = file.OpenReadStream();
            var response = await imports.ParseAsync(
                format,
                file.ContentType,
                stream,
                accountId,
                deviceId.Value,
                cancellationToken);

            return Results.Json(response, WireJson, statusCode: StatusCodes.Status200OK);
        }
        catch (ImportFileTooLargeException ex)
        {
            return Problem(
                StatusCodes.Status413PayloadTooLarge,
                TankbookErrorCodes.PayloadTooLarge,
                "File too large.",
                $"An import file may be at most {ex.MaxBytes} bytes.");
        }
        catch (NotMfmExportException ex)
        {
            return Problem(
                StatusCodes.Status422UnprocessableEntity,
                TankbookErrorCodes.ImportMismatch,
                "This does not look like a My Fuel Manager export.",
                ex.Detail);
        }
    }

    /// <summary>GET /v1/import/{importId} - re-reads a stored parse so a review can be resumed.</summary>
    public static async Task<IResult> Get(
        Guid importId,
        ImportService imports,
        HttpContext httpContext,
        CancellationToken cancellationToken)
    {
        var identity = AuthContext.From(httpContext);
        var response = await imports.GetAsync(importId, identity?.AccountId, cancellationToken);
        return response is null
            ? ProblemResponses.Problem(
                StatusCodes.Status404NotFound,
                TankbookErrorCodes.ImportNotFound,
                "Import not found.",
                "No stored parse has this id.")
            : Results.Json(response, WireJson);
    }

    /// <summary>DELETE /v1/import/{importId} - drops the stored file and its parse early. Idempotent (204 whether or not it existed).</summary>
    public static async Task<IResult> Delete(
        Guid importId,
        ImportService imports,
        HttpContext httpContext,
        CancellationToken cancellationToken)
    {
        var identity = AuthContext.From(httpContext);
        await imports.DeleteAsync(importId, identity?.AccountId, cancellationToken);
        return Results.NoContent();
    }

    private static IResult Problem(int status, string code, string title, string detail)
        => ProblemResponses.Problem(status, code, title, detail);

    private sealed record FormatResponse(string Id, string DisplayName, string[] FileKinds, string? HelpUrl, int AddedInPackVersion);
}

using System.Text.Json;
using Tankbook.Api.Auth;
using Tankbook.Api.Http;
using Tankbook.Api.Logging;

namespace Tankbook.Api.Cases;

/// <summary>
/// POST /v1/cases (docs/API.md "Debug cases"): a multipart upload of the parts
/// the user chose to send, public with the bearer optional - a user with no
/// account can send one too, stored under their device identity. 201 carries
/// the case id the phone shows; nothing else about a case is readable through
/// this API (hard rule 9: the admin viewer is the one reader).
/// </summary>
public static class CaseEndpoints
{
    private static readonly JsonSerializerOptions WireJson = new(JsonSerializerDefaults.Web);

    public sealed record CaseResponse(string CaseId, DateTimeOffset ExpiresAt);

    public static async Task<IResult> Submit(CaseService cases, HttpContext httpContext,
                                             CancellationToken cancellationToken)
    {
        var identity = AuthContext.From(httpContext);
        Guid? deviceId = identity?.DeviceId;
        if (deviceId is null)
        {
            var header = httpContext.Request.Headers["X-Device-Id"].FirstOrDefault();
            if (header is null || !Guid.TryParse(header, out var parsed))
            {
                return ProblemResponses.Problem(StatusCodes.Status400BadRequest, TankbookErrorCodes.PayloadInvalid,
                    "Missing device identity.",
                    "A device id (X-Device-Id) is required when signed out so the case can be purged.");
            }

            deviceId = parsed;
        }

        if (!httpContext.Request.HasFormContentType)
        {
            return ProblemResponses.Problem(StatusCodes.Status415UnsupportedMediaType, TankbookErrorCodes.PayloadInvalid,
                "Expected a multipart upload.", "Send the case as multipart/form-data, one file per part.");
        }

        var form = await httpContext.Request.ReadFormAsync(cancellationToken);
        var uploads = new List<CaseUpload>(form.Files.Count);
        foreach (var file in form.Files)
        {
            if (file.Length > CaseOptions.MaxPartBytes)
            {
                return ProblemResponses.Problem(StatusCodes.Status413PayloadTooLarge, TankbookErrorCodes.PayloadTooLarge,
                    "A part is too large.", $"A part is at most {CaseOptions.MaxPartBytes} bytes.");
            }

            using var stream = new MemoryStream((int)file.Length);
            await file.CopyToAsync(stream, cancellationToken);
            uploads.Add(new CaseUpload(file.Name, file.ContentType ?? string.Empty, stream.ToArray()));
        }

        try
        {
            var app = httpContext.Request.Headers["X-Tankbook-App"].FirstOrDefault();
            var row = await cases.AcceptAsync(uploads, identity?.AccountId, deviceId.Value, app, cancellationToken);
            return Results.Json(new CaseResponse(row.Id, cases.ExpiresAt(row)), WireJson,
                                statusCode: StatusCodes.Status201Created);
        }
        catch (CaseRejectedException ex)
        {
            return ProblemResponses.Problem(ex.Status, ex.Code, "The case was refused.", ex.Message);
        }
    }
}

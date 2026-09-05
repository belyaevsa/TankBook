using Tankbook.Api.Auth;
using Tankbook.Api.Http;
using Tankbook.Api.Logging;

namespace Tankbook.Api.Blobs;

/// <summary>
/// The blob HTTP surface (docs/API.md "Attachments"). Thin wire handlers:
/// auth + input-shape checks (400/415), then the service, mapped to 200 / 302 /
/// 404 / 409 / 410 / 413 / 429 / 204. Never returns 403 for a foreign blob -
/// cross-account access is indistinguishable from absence (404), so no
/// information leaks and no presigned URL is ever minted for another account's
/// object.
/// </summary>
public static class BlobEndpoints
{
    public static async Task<IResult> Begin(
        HttpContext httpContext,
        BlobService blobs,
        BlobBeginRequest request,
        CancellationToken cancellationToken)
    {
        var identity = AuthContext.From(httpContext);
        if (identity is null)
        {
            return Problem(
                StatusCodes.Status401Unauthorized,
                TankbookErrorCodes.TokenInvalid,
                "Authentication required.",
                "A valid bearer token is required.");
        }

        if (!BlobContentTypes.IsValidSha256(request.Sha256))
        {
            return Problem(
                StatusCodes.Status400BadRequest,
                TankbookErrorCodes.PayloadInvalid,
                "Invalid sha256.",
                "sha256 must be a 64-character lowercase hex digest.");
        }

        if (request.Size is not { } size || size < 0)
        {
            return Problem(
                StatusCodes.Status400BadRequest,
                TankbookErrorCodes.PayloadInvalid,
                "Missing size.",
                "size is required and must be >= 0.");
        }

        if (!BlobContentTypes.TryClassify(request.ContentType, out var kind, out var contentType))
        {
            return Problem(
                StatusCodes.Status415UnsupportedMediaType,
                TankbookErrorCodes.PayloadInvalid,
                "Unsupported content type.",
                "contentType must be one of image/jpeg, image/png, image/heic, application/pdf.");
        }

        var outcome = await blobs.BeginAsync(identity.Value.AccountId, identity.Value.DeviceId, request.Sha256!, size, kind, contentType, cancellationToken);
        return outcome.Status switch
        {
            BeginStatus.Exists => Results.Ok(outcome.Response),
            BeginStatus.Upload => Results.Ok(outcome.Response),
            BeginStatus.TooLarge => Problem(
                StatusCodes.Status413PayloadTooLarge,
                TankbookErrorCodes.PayloadTooLarge,
                "Payload too large.",
                kind == BlobKind.Pdf
                    ? "A PDF attachment may be at most 10 MB."
                    : "An image attachment may be at most 25 MB."),
            BeginStatus.QuotaExceeded => Problem(
                StatusCodes.Status429TooManyRequests,
                TankbookErrorCodes.BlobQuotaExceeded,
                "Storage quota exceeded.",
                "This account's attachment storage is full; delete attachments or export to free space."),
            BeginStatus.DeviceRevoked => Revoked(),
            _ => throw new InvalidOperationException($"Unknown begin status {outcome.Status}."),
        };
    }

    public static async Task<IResult> Commit(
        HttpContext httpContext,
        BlobService blobs,
        BlobCommitRequest request,
        CancellationToken cancellationToken)
    {
        var identity = AuthContext.From(httpContext);
        if (identity is null)
        {
            return Problem(
                StatusCodes.Status401Unauthorized,
                TankbookErrorCodes.TokenInvalid,
                "Authentication required.",
                "A valid bearer token is required.");
        }

        if (!BlobContentTypes.IsValidSha256(request.Sha256))
        {
            return Problem(
                StatusCodes.Status400BadRequest,
                TankbookErrorCodes.PayloadInvalid,
                "Invalid sha256.",
                "sha256 must be a 64-character lowercase hex digest.");
        }

        var outcome = await blobs.CommitAsync(identity.Value.AccountId, identity.Value.DeviceId, request.Sha256!, cancellationToken);
        return outcome.Status switch
        {
            CommitStatus.Committed => Results.NoContent(),
            CommitStatus.NotBegun => Problem(
                StatusCodes.Status409Conflict,
                TankbookErrorCodes.BlobConflict,
                "Upload not begun.",
                "No begin was recorded for this blob; call POST /blobs/begin first."),
            CommitStatus.NotUploaded => Problem(
                StatusCodes.Status409Conflict,
                TankbookErrorCodes.BlobConflict,
                "Upload not found.",
                "The object is not in storage; PUT the bytes to the presigned URL before committing."),
            CommitStatus.SizeMismatch => Problem(
                StatusCodes.Status409Conflict,
                TankbookErrorCodes.BlobConflict,
                "Size mismatch.",
                "The stored object's size differs from the size declared at begin; re-begin and re-upload."),
            CommitStatus.DeviceRevoked => Revoked(),
            _ => throw new InvalidOperationException($"Unknown commit status {outcome.Status}."),
        };
    }

    public static async Task<IResult> Get(
        HttpContext httpContext,
        BlobService blobs,
        string sha256,
        CancellationToken cancellationToken)
    {
        var identity = AuthContext.From(httpContext);
        if (identity is null)
        {
            return Problem(
                StatusCodes.Status401Unauthorized,
                TankbookErrorCodes.TokenInvalid,
                "Authentication required.",
                "A valid bearer token is required.");
        }

        if (!BlobContentTypes.IsValidSha256(sha256))
        {
            return Problem(
                StatusCodes.Status400BadRequest,
                TankbookErrorCodes.PayloadInvalid,
                "Invalid sha256.",
                "sha256 must be a 64-character lowercase hex digest.");
        }

        var outcome = await blobs.GetAsync(identity.Value.AccountId, identity.Value.DeviceId, sha256, cancellationToken);
        return outcome.Status switch
        {
            GetStatus.Redirect => Results.Redirect(outcome.Url!, permanent: false, preserveMethod: false),
            GetStatus.NotFound => Problem(
                StatusCodes.Status404NotFound,
                TankbookErrorCodes.BlobNotFound,
                "Blob not found.",
                "No attachment with this sha256 exists for this account."),
            GetStatus.DeviceRevoked => Revoked(),
            _ => throw new InvalidOperationException($"Unknown get status {outcome.Status}."),
        };
    }

    private static IResult Revoked()
        => Problem(
            StatusCodes.Status410Gone,
            TankbookErrorCodes.DeviceRevoked,
            "Device revoked or account deleted.",
            "This device has been revoked or the account was deleted. Re-onboard or detach; local data stays local.");

    private static IResult Problem(int status, string code, string title, string detail)
        => ProblemResponses.Problem(status, code, title, detail);
}

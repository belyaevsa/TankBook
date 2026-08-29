using Microsoft.Extensions.Options;
using Tankbook.Api.Blobs;
using Tankbook.Api.Options;

namespace Tankbook.Api.Tests.Blobs;

/// <summary>
/// Pins the REAL presign, not the recording double (PR.18, docs/PRACTICES.md S10).
///
/// Why this file exists: <c>Presign_UploadBindsDeclaredContentTypeAndLength</c>
/// asserts against <see cref="RecordingBlobStorage"/>, so it proves the service
/// hands the declared type and length across the interface - real, but it leaves
/// <see cref="S3BlobStorage"/> unpinned. Deleting the Content-Length line from
/// the production presign left all 16 blob tests green, which is how the gap
/// below was found.
///
/// MEASURED, and the reason the length is not asserted here: the SDK emits a
/// SigV2 presigned URL (AWSAccessKeyId/Expires/Signature). SigV2's StringToSign
/// covers Content-Type but NOT Content-Length, so the declared length is signed
/// into nothing. Setting AmazonS3Config.SignatureVersion = "4" does not change
/// it. The declared length is therefore advisory at the URL, and the real
/// enforcement is BlobService's commit-time check (storedSize != pending.SizeBytes
/// rejects) plus the hourly orphan sweep. Filed as a follow-up; the residual risk
/// is bounded (an uncommitted object occupies storage until the sweep).
///
/// The clock is FIXED on purpose. Expires is a unix second baked into the
/// signature, so two calls in different seconds differ for that reason alone - a
/// time-dependent version of this file reported the length as bound when it is
/// not.
/// </summary>
public class S3PresignConstraintTests
{
    private sealed class FixedTime(DateTimeOffset now) : TimeProvider
    {
        public override DateTimeOffset GetUtcNow() => now;
    }

    private static S3BlobStorage MakeStorage() =>
        new(Microsoft.Extensions.Options.Options.Create(new S3Options
        {
            Endpoint = "http://s3.invalid:9000",
            Bucket = "tankbook-test",
            AccessKey = "test-access-key",
            SecretKey = "test-secret-key",
            UseSsl = false,
        }), new FixedTime(new DateTimeOffset(2026, 8, 29, 12, 0, 0, TimeSpan.Zero)));

    private static string? Signature(string url)
    {
        var q = System.Web.HttpUtility.ParseQueryString(new Uri(url).Query);
        return q["X-Amz-Signature"] ?? q["Signature"];
    }

    /// <summary>
    /// The declared content type IS signed into the URL, so a bearer cannot
    /// upload a different type. With the clock fixed, the signature can only
    /// differ because the content type did.
    /// </summary>
    [Fact]
    public void DeclaredContentTypeIsSignedIntoTheUploadUrl()
    {
        var storage = MakeStorage();
        var lifetime = TimeSpan.FromMinutes(15);

        var pdf = storage.CreateUploadUrl("blobs/abc", "application/pdf", 100L, lifetime).Url;
        var jpeg = storage.CreateUploadUrl("blobs/abc", "image/jpeg", 100L, lifetime).Url;

        Assert.NotNull(Signature(pdf));
        Assert.NotEqual(Signature(pdf), Signature(jpeg));
    }

    /// <summary>
    /// Guards the finding above so it cannot rot silently: while the presign is
    /// SigV2 the length does not reach the signature. If this ever starts
    /// FAILING, the SDK or the config changed and the length now binds - delete
    /// this test, assert the length instead, and update the follow-up row.
    /// </summary>
    [Fact]
    public void DeclaredLengthIsNotYetSignedIntoTheUploadUrl_KnownGap()
    {
        var storage = MakeStorage();
        var lifetime = TimeSpan.FromMinutes(15);

        var small = storage.CreateUploadUrl("blobs/abc", "application/pdf", 100L, lifetime).Url;
        var large = storage.CreateUploadUrl("blobs/abc", "application/pdf", 999_999L, lifetime).Url;

        Assert.Equal(Signature(small), Signature(large));
    }
}

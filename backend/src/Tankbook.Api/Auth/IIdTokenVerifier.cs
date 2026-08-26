namespace Tankbook.Api.Auth;

/// <summary>Why an identity token was rejected (docs/LOGGING.md auth.session.failureReason).</summary>
public enum IdTokenOutcome
{
    Valid,
    UnsupportedProvider,
    Malformed,
    UnknownKey,
    InvalidSignature,
    Expired,
    ClockSkew,
    MissingEmail,
    EmailNotVerified,
}

/// <summary>
/// The verified identity from a Sign in with Apple / Google idToken. Subject and
/// email are set only when <see cref="Outcome"/> is <see cref="IdTokenOutcome.Valid"/>.
/// </summary>
public sealed record IdTokenVerificationResult(IdTokenOutcome Outcome, string? Subject = null, string? Email = null)
{
    public bool IsValid => Outcome == IdTokenOutcome.Valid;

    public static IdTokenVerificationResult Ok(string subject, string email)
        => new(IdTokenOutcome.Valid, subject, email);

    public static IdTokenVerificationResult Failed(IdTokenOutcome outcome) => new(outcome);
}

/// <summary>
/// The idToken verification seam (docs/SECURITY.md "Verification is server-side
/// against fetched JWKS with caching"). The production implementation fetches
/// and caches Apple/Google JWKS and verifies RS256 signatures; L2 tests inject a
/// test-signer verifier so they can mint tokens with no network.
/// </summary>
public interface IIdTokenVerifier
{
    Task<IdTokenVerificationResult> VerifyAsync(string provider, string idToken, CancellationToken cancellationToken);
}

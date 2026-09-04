using Microsoft.Extensions.Options;
using Tankbook.Api.Logging;

namespace Tankbook.Api.Auth;

/// <summary>The outcome of a session exchange (docs/API.md POST /auth/session).</summary>
public sealed record SessionExchangeResult(
    bool Success,
    string? AccessToken,
    string? RefreshToken,
    Guid? AccountId,
    Guid? DeviceId,
    string? Email,
    string? FailureReason,
    string? AccountHash)
{
    public static SessionExchangeResult Failed(string failureReason)
        => new(false, null, null, null, null, null, failureReason, null);
}

/// <summary>The outcome of a refresh rotation (docs/API.md POST /auth/refresh).</summary>
public sealed record RefreshResult(
    bool Success,
    string? AccessToken,
    string? RefreshToken,
    string? FailureReason)
{
    public static RefreshResult Ok(string accessToken, string refreshToken)
        => new(true, accessToken, refreshToken, null);

    public static RefreshResult Failed(string failureReason)
        => new(false, null, null, failureReason);
}

/// <summary>
/// Orchestrates session exchange, refresh rotation, and sign-out. It logs the
/// auth.session / auth.refresh events (docs/LOGGING.md §3) with ids, outcomes
/// and the salted accountHash - never a token, idToken, or email (hard rule 12).
/// </summary>
public sealed class AuthService
{
    private readonly IIdTokenVerifier _verifier;
    private readonly JwtAccessTokenIssuer _issuer;
    private readonly AuthRepository _repository;
    private readonly AuthOptions _options;
    private readonly LoggingOptions _loggingOptions;
    private readonly ILogger<AuthService> _logger;
    private readonly TimeProvider _time;

    public AuthService(
        IIdTokenVerifier verifier,
        JwtAccessTokenIssuer issuer,
        AuthRepository repository,
        IOptions<AuthOptions> options,
        LoggingOptions loggingOptions,
        ILogger<AuthService> logger,
        TimeProvider time)
    {
        _verifier = verifier;
        _issuer = issuer;
        _repository = repository;
        _options = options.Value;
        _loggingOptions = loggingOptions;
        _logger = logger;
        _time = time;
    }

    public AuthService(
        IIdTokenVerifier verifier,
        JwtAccessTokenIssuer issuer,
        AuthRepository repository,
        IOptions<AuthOptions> options,
        LoggingOptions loggingOptions,
        ILogger<AuthService> logger)
        : this(verifier, issuer, repository, options, loggingOptions, logger, TimeProvider.System)
    {
    }

    /// <summary>
    /// Exchanges a verified identity token for a session: find-or-create the
    /// account, reuse-or-create the device row, and issue the token pair plus
    /// deviceId. Sign-in IS registration - there is no separate account
    /// endpoint. The response carries the account's stored email so the client
    /// can always name the account (docs/API.md -> Auth, RV.39).
    /// </summary>
    public async Task<SessionExchangeResult> ExchangeAsync(
        string provider,
        string idToken,
        string deviceName,
        string devicePlatform,
        Guid? deviceId,
        CancellationToken cancellationToken)
    {
        var verification = await _verifier.VerifyAsync(provider, idToken, cancellationToken);
        if (!verification.IsValid)
        {
            var reason = FailureReason(verification.Outcome);
            TankbookLog.AuthSession(_logger, provider, "rejected", reason);
            return SessionExchangeResult.Failed(reason);
        }

        var subject = verification.Subject!;
        var email = verification.Email!;

        var (accountId, created, accountEmail) = await _repository.FindOrCreateAccountAsync(provider, subject, email, cancellationToken);
        var resolvedDeviceId = await _repository.FindOrCreateDeviceAsync(accountId, deviceId, deviceName, devicePlatform, cancellationToken);

        var accessToken = _issuer.Issue(accountId, resolvedDeviceId);
        var refreshToken = RefreshTokenHasher.Generate(_options.RefreshTokenBytes);
        var now = _time.GetUtcNow();
        await _repository.InsertRefreshTokenAsync(
            Guid.NewGuid(),
            accountId,
            resolvedDeviceId,
            RefreshTokenHasher.Hash(refreshToken),
            Guid.NewGuid(),
            now,
            now.AddDays(_options.RefreshTokenLifetimeDays),
            cancellationToken);

        var accountHash = AccountHash.Compute(email, _loggingOptions.HashSalt);
        TankbookLog.AuthSession(_logger, provider, created ? "created" : "matched", accountHash: accountHash);

        return new SessionExchangeResult(true, accessToken, refreshToken, accountId, resolvedDeviceId, accountEmail, null, accountHash);
    }

    /// <summary>
    /// Rotates a refresh token: issues a new pair, invalidates the presented
    /// token, and on reuse of an already-rotated token revokes the entire chain
    /// and rejects (docs/API.md).
    /// </summary>
    public async Task<RefreshResult> RefreshAsync(string refreshToken, CancellationToken cancellationToken)
    {
        var newRefreshToken = RefreshTokenHasher.Generate(_options.RefreshTokenBytes);
        var now = _time.GetUtcNow();
        var result = await _repository.RotateAsync(
            RefreshTokenHasher.Hash(refreshToken),
            Guid.NewGuid(),
            RefreshTokenHasher.Hash(newRefreshToken),
            now,
            now.AddDays(_options.RefreshTokenLifetimeDays),
            cancellationToken);

        switch (result.Outcome)
        {
            case RefreshRotationOutcome.Rotated:
                {
                    var accessToken = _issuer.Issue(result.AccountId!.Value, result.DeviceId!.Value);
                    TankbookLog.AuthRefresh(
                        _logger,
                        "rotated",
                        result.ChainId?.ToString(),
                        reuseDetected: false,
                        deviceId: result.DeviceId?.ToString());
                    return RefreshResult.Ok(accessToken, newRefreshToken);
                }

            case RefreshRotationOutcome.ReuseDetected:
                TankbookLog.AuthRefresh(
                    _logger,
                    "rejected",
                    result.ChainId?.ToString(),
                    reuseDetected: true,
                    deviceId: result.DeviceId?.ToString());
                return RefreshResult.Failed("reuse_detected");

            case RefreshRotationOutcome.Expired:
                TankbookLog.AuthRefresh(
                    _logger,
                    "expired",
                    result.ChainId?.ToString(),
                    deviceId: result.DeviceId?.ToString());
                return RefreshResult.Failed("expired");

            default:
                TankbookLog.AuthRefresh(_logger, "rejected");
                return RefreshResult.Failed("invalid_refresh_token");
        }
    }

    /// <summary>Revokes this device's refresh chains. Local data stays local.</summary>
    public Task SignOutAsync(Guid deviceId, CancellationToken cancellationToken)
        => _repository.RevokeDeviceAsync(deviceId, cancellationToken);

    private static string FailureReason(IdTokenOutcome outcome) => outcome switch
    {
        IdTokenOutcome.Malformed => "malformed",
        IdTokenOutcome.UnknownKey => "invalid_signature",
        IdTokenOutcome.InvalidSignature => "invalid_signature",
        IdTokenOutcome.Expired => "expired",
        IdTokenOutcome.ClockSkew => "clock_skew",
        IdTokenOutcome.MissingEmail => "missing_email",
        IdTokenOutcome.EmailNotVerified => "email_not_verified",
        IdTokenOutcome.UnsupportedProvider => "unsupported_provider",
        _ => "invalid_token",
    };
}

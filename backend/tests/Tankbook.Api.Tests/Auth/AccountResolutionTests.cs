using Tankbook.Api.Auth;

namespace Tankbook.Api.Tests.Auth;

/// <summary>
/// RV.286: the auth.session Outcome for each account resolution. This is the
/// non-Postgres half of the reactivation tests - the L2 tests in
/// <c>AccountEndpointTests</c> prove the database reactivates a tombstoned
/// account, and this proves the reactivation is logged under its own value so a
/// production log answers "did a grace sign-in happen?" in one grep.
/// </summary>
public class AccountResolutionTests
{
    [Theory]
    [InlineData(AccountResolution.Created, "created")]
    [InlineData(AccountResolution.Matched, "matched")]
    [InlineData(AccountResolution.Reactivated, "reactivated")]
    public void OutcomeName_MapsEveryResolution(AccountResolution outcome, string expected)
        => Assert.Equal(expected, AuthService.OutcomeName(outcome));
}

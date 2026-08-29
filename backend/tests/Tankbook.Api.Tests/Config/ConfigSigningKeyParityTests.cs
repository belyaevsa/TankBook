using System.Text.RegularExpressions;
using Tankbook.Api.Config;

namespace Tankbook.Api.Tests.Config;

/// <summary>
/// PR.3a: the client bundles the dev signing key's public half in
/// <c>ios/Sources/TankbookCore/Config/ConfigSigningKey.swift</c> (the DEBUG arm
/// of <see cref="ConfigSigningKey"/>). This test reads that literal straight
/// from the Swift source and asserts it equals the dev signer's public key, so
/// a hand-copied 44-character string that drifts from the real signer fails
/// here instead of failing every signature check on every device in the field
/// (docs/CONFIG.md -> "Defence in depth": the key is injected, never fetched).
/// </summary>
public class ConfigSigningKeyParityTests
{
    [Fact]
    public void BundledPublicKey_MatchesTheDevSignersPublicKey()
    {
        var bundled = ReadBundledPublicKeyFromSwiftSource();

        Assert.False(string.IsNullOrEmpty(bundled),
            "ConfigSigningKey.swift must carry a non-empty DEBUG key literal");
        Assert.Equal(ConfigTestData.Signer.PublicKeyBase64, bundled);
    }

    /// <summary>
    /// Reads the base64 literal out of the DEBUG arm of the Swift source, so the
    /// two can never drift apart without this test failing. The repo layout is
    /// fixed, so the path from the repository root is deterministic.
    /// </summary>
    private static string ReadBundledPublicKeyFromSwiftSource()
    {
        var path = Path.Combine(
            DocPaths.RepositoryRoot,
            "ios", "Sources", "TankbookCore", "Config", "ConfigSigningKey.swift");
        var source = File.ReadAllText(path);

        const string debugMarker = "#if DEBUG";
        const string elseMarker = "#else";
        var debugStart = source.IndexOf(debugMarker, StringComparison.Ordinal);
        var elseStart = source.IndexOf(elseMarker, debugStart, StringComparison.Ordinal);
        Assert.True(debugStart >= 0 && elseStart > debugStart,
            "ConfigSigningKey.swift must carry a #if DEBUG ... #else ... #endif split");

        var debugArm = source.Substring(debugStart, elseStart - debugStart);
        var match = Regex.Match(debugArm, "return \"([A-Za-z0-9+/=]+)\"");
        Assert.True(match.Success, "the DEBUG arm of ConfigSigningKey.swift must return a base64 key literal");
        return match.Groups[1].Value;
    }
}

using System.Text;
using Tankbook.Api.Config;

namespace Tankbook.Api.Tests.Config;

/// <summary>
/// Canonicalization is the load-bearing detail of the whole remote-config
/// signing story (docs/CONFIG.md signed payload): client and server must agree
/// byte-for-byte on the bytes the Ed25519 signature covers, or every document is
/// rejected. These are pure unit tests - no host, no database.
/// </summary>
public class ConfigCanonicalizerTests
{
    [Fact]
    public void Canonicalize_SameDocument_DifferentKeyOrder_SameBytes()
    {
        // Same content, different member order at two nesting levels.
        const string docA = """{"b":2,"a":1,"nested":{"z":1,"y":[3,2,1],"x":"str"}}""";
        const string docB = """{"nested":{"x":"str","y":[3,2,1],"z":1},"a":1,"b":2}""";

        var canonicalA = ConfigCanonicalizer.Canonicalize(docA);
        var canonicalB = ConfigCanonicalizer.Canonicalize(docB);

        Assert.Equal(canonicalA, canonicalB);
    }

    [Fact]
    public void Canonicalize_OutputsSortedCompactJson_WithNoWhitespace()
    {
        const string docA = """{"b":2,"a":1,"nested":{"z":1,"y":[3,2,1],"x":"str"}}""";

        var canonical = Encoding.UTF8.GetString(ConfigCanonicalizer.Canonicalize(docA));

        // Keys sorted lexicographically at every level, compact, no spaces.
        Assert.Equal("""{"a":1,"b":2,"nested":{"x":"str","y":[3,2,1],"z":1}}""", canonical);
    }

    [Fact]
    public void Canonicalize_PreservesNumberTokensVerbatim()
    {
        // 1e3 must stay 1e3 and 0.75 must stay 0.75: canonicalization never
        // re-serializes through a parsed float (that is where implementations
        // silently diverge and signatures break).
        var canonical = Encoding.UTF8.GetString(ConfigCanonicalizer.Canonicalize(
            """{"v":1,"threshold":1e3,"z":0.75}"""));

        Assert.Contains("1e3", canonical);
        Assert.Contains("0.75", canonical);
    }

    [Fact]
    public void Canonicalize_PreservesArrayOrder()
    {
        var canonical = Encoding.UTF8.GetString(ConfigCanonicalizer.Canonicalize("""{"a":[3,1,2]}"""));

        Assert.Contains("[3,1,2]", canonical);
    }

    [Fact]
    public void Signature_SameDocumentDifferentKeyOrder_IsIdentical()
    {
        const string docA = """{"b":2,"a":1}""";
        const string docB = """{"a":1,"b":2}""";

        var sigA = ConfigTestData.Signer.Sign(ConfigCanonicalizer.Canonicalize(docA));
        var sigB = ConfigTestData.Signer.Sign(ConfigCanonicalizer.Canonicalize(docB));

        Assert.Equal(sigA, sigB);
    }

    [Fact]
    public void Signature_TamperedDocument_FailsVerificationWithThePublishedPublicKey()
    {
        var document = ConfigTestData.Document();
        var canonical = ConfigCanonicalizer.Canonicalize(document);
        var signature = ConfigTestData.Signer.Sign(canonical);

        // The published public key (the one the client bundle is built against).
        Assert.True(ConfigSigner.VerifyWithPublicKey(canonical, signature, ConfigTestData.Signer.PublicKeyBase64));

        // One flipped kill switch changes the canonical bytes, so the signature
        // no longer verifies - a backup-tampered cache cannot move a device.
        var tampered = document.Replace("\"tier3CloudFallback\":true", "\"tier3CloudFallback\":false", StringComparison.Ordinal);
        Assert.NotEqual(canonical, ConfigCanonicalizer.Canonicalize(tampered));
        Assert.False(ConfigSigner.VerifyWithPublicKey(
            ConfigCanonicalizer.Canonicalize(tampered), signature, ConfigTestData.Signer.PublicKeyBase64));
    }

    [Fact]
    public void Canonicalize_MalformedJson_Throws()
    {
        Assert.ThrowsAny<Exception>(() => ConfigCanonicalizer.Canonicalize("""{"a":}"""));
    }
}

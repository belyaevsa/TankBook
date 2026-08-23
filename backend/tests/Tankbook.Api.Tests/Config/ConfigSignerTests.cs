using System.Text;
using Tankbook.Api.Config;

namespace Tankbook.Api.Tests.Config;

public class ConfigSignerTests
{
    [Fact]
    public void Sign_Verify_RoundTripsThroughThePublishedPublicKey()
    {
        var canonical = ConfigCanonicalizer.Canonicalize(ConfigTestData.Document());
        var signature = ConfigTestData.Signer.Sign(canonical);

        Assert.True(ConfigSigner.VerifyWithPublicKey(canonical, signature, ConfigTestData.Signer.PublicKeyBase64));
    }

    [Fact]
    public void Verify_WrongPublicKey_Fails()
    {
        var otherSigner = new ConfigSigner(Convert.ToBase64String(
            System.Security.Cryptography.SHA256.HashData(Encoding.UTF8.GetBytes("some-other-seed"))));
        var canonical = ConfigCanonicalizer.Canonicalize(ConfigTestData.Document());
        var signature = ConfigTestData.Signer.Sign(canonical);

        Assert.False(ConfigSigner.VerifyWithPublicKey(canonical, signature, otherSigner.PublicKeyBase64));
    }

    [Fact]
    public void DifferentSeed_ProducesDifferentPublicKeyAndKeyId()
    {
        var otherSigner = new ConfigSigner(Convert.ToBase64String(
            System.Security.Cryptography.SHA256.HashData(Encoding.UTF8.GetBytes("yet-another-seed"))));

        Assert.NotEqual(ConfigTestData.Signer.PublicKeyBase64, otherSigner.PublicKeyBase64);
        Assert.NotEqual(ConfigTestData.Signer.KeyId, otherSigner.KeyId);
    }

    [Fact]
    public void KeyId_IsAStable16HexDigitFingerprint()
    {
        var signerA = new ConfigSigner(ConfigTestData.SeedBase64);
        var signerB = new ConfigSigner(ConfigTestData.SeedBase64);

        Assert.Equal(16, signerA.KeyId.Length);
        Assert.True(signerA.KeyId.All(Uri.IsHexDigit));
        Assert.Equal(signerA.KeyId, signerB.KeyId);
    }

    [Fact]
    public void Verify_GarbageSignatureOrKey_ReturnsFalseWithoutThrowing()
    {
        var canonical = ConfigCanonicalizer.Canonicalize(ConfigTestData.Document());

        Assert.False(ConfigSigner.VerifyWithPublicKey(canonical, "not-base64!!", ConfigTestData.Signer.PublicKeyBase64));
        Assert.False(ConfigSigner.VerifyWithPublicKey(canonical, ConfigTestData.Signer.Sign(canonical), "not-a-key"));
        Assert.False(ConfigSigner.VerifyWithPublicKey(canonical, "aGVsbG8=", ConfigTestData.Signer.PublicKeyBase64));
    }

    [Fact]
    public void InvalidSeedLength_Throws()
    {
        // 31 bytes, not 32.
        Assert.Throws<ArgumentException>(() => new ConfigSigner(Convert.ToBase64String(new byte[31])));
    }

    [Fact]
    public void NotConfiguredSigner_CannotSign_AndExposesNoKey()
    {
        var signer = new ConfigSigner(null);

        Assert.False(signer.IsConfigured);
        Assert.Equal(string.Empty, signer.PublicKeyBase64);
        Assert.Throws<InvalidOperationException>(() => signer.Sign(new byte[] { 1, 2, 3 }));
    }
}

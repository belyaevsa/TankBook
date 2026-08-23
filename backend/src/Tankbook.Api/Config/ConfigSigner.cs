using System.Security.Cryptography;
using Org.BouncyCastle.Crypto.Parameters;
using Org.BouncyCastle.Crypto.Signers;

namespace Tankbook.Api.Config;

/// <summary>
/// Ed25519 signer for config documents (docs/CONFIG.md "Signed payload",
/// docs/SECURITY.md). The private key lives in the platform secret store,
/// injected at runtime from Config:SigningKey as a base64-encoded 32-byte seed;
/// only a dev-only default sits in appsettings.Development.json. The public key
/// is exposed at GET /v1/config/public-key so the client bundle can be built
/// against it. Signatures are computed over the CANONICAL serialization of the
/// document (see <see cref="ConfigCanonicalizer"/>) - the detail that silently
/// breaks verification if the two sides disagree about the byte form.
/// </summary>
public sealed class ConfigSigner
{
    private readonly Ed25519PrivateKeyParameters? _privateKey;
    private readonly byte[] _publicKey;

    /// <summary>Constructs a signer from a base64 32-byte Ed25519 seed.</summary>
    /// <param name="signingKeyBase64">
    /// Base64-encoded 32-byte Ed25519 private seed from Config:SigningKey. Empty
    /// or null means "not configured": the signer cannot sign but reports
    /// <see cref="IsConfigured"/> false so call sites degrade gracefully.
    /// </param>
    public ConfigSigner(string? signingKeyBase64)
    {
        if (string.IsNullOrWhiteSpace(signingKeyBase64))
        {
            IsConfigured = false;
            _publicKey = Array.Empty<byte>();
            return;
        }

        var seed = Convert.FromBase64String(signingKeyBase64);
        if (seed.Length != 32)
        {
            throw new ArgumentException(
                "Config:SigningKey must be a base64-encoded 32-byte Ed25519 seed.", nameof(signingKeyBase64));
        }

        _privateKey = new Ed25519PrivateKeyParameters(seed, 0);
        _publicKey = _privateKey.GeneratePublicKey().GetEncoded();
        IsConfigured = true;
    }

    /// <summary>True when a private key was supplied, so signatures can be produced.</summary>
    public bool IsConfigured { get; }

    /// <summary>The 32-byte public key, base64-encoded, for bundling into clients.</summary>
    public string PublicKeyBase64 => Convert.ToBase64String(_publicKey);

    /// <summary>A short fingerprint of the public key so clients can detect key rotation.</summary>
    public string KeyId => Convert.ToHexString(SHA256.HashData(_publicKey))[..16].ToLowerInvariant();

    /// <summary>Signs the canonical document bytes, returning a base64-encoded Ed25519 signature.</summary>
    public string Sign(ReadOnlySpan<byte> canonicalBytes)
    {
        if (!IsConfigured || _privateKey is null)
        {
            throw new InvalidOperationException("No signing key is configured (Config:SigningKey).");
        }

        var signer = new Ed25519Signer();
        signer.Init(forSigning: true, _privateKey);
        signer.BlockUpdate(canonicalBytes.ToArray(), 0, canonicalBytes.Length);
        return Convert.ToBase64String(signer.GenerateSignature());
    }

    /// <summary>Verifies a base64 signature against canonical bytes with this signer's public key.</summary>
    public bool Verify(ReadOnlySpan<byte> canonicalBytes, string signatureBase64)
        => VerifyWithPublicKey(canonicalBytes, signatureBase64, PublicKeyBase64);

    /// <summary>
    /// Verifies a base64 Ed25519 signature over canonical bytes using the given
    /// base64 public key (the key the client bundle was built against).
    /// </summary>
    public static bool VerifyWithPublicKey(ReadOnlySpan<byte> canonicalBytes, string signatureBase64, string publicKeyBase64)
    {
        byte[] signature;
        byte[] publicKey;
        try
        {
            signature = Convert.FromBase64String(signatureBase64);
            publicKey = Convert.FromBase64String(publicKeyBase64);
        }
        catch (FormatException)
        {
            return false;
        }

        if (signature.Length != 64 || publicKey.Length != 32)
        {
            return false;
        }

        var verifier = new Ed25519Signer();
        verifier.Init(forSigning: false, new Ed25519PublicKeyParameters(publicKey, 0));
        verifier.BlockUpdate(canonicalBytes.ToArray(), 0, canonicalBytes.Length);
        return verifier.VerifySignature(signature);
    }
}

import CryptoKit
import Foundation

/// Verifies the Ed25519 signature on a remote config document
/// (docs/CONFIG.md -> "Threat: the cache file is tampered with", rule 1).
///
/// **Verification runs on every load from cache, not only on fetch.** Validating
/// at fetch time and then trusting the cache would bypass signing entirely, and
/// with it every guardrail that depends on it. Verifying on read makes editing
/// the cache equivalent to forging a signature, and the public key lives in the
/// app binary, which a backup restore cannot modify.
///
/// The public key is **injected, never fetched**. `GET /v1/config/public-key`
/// exists for operational tooling only: an attacker who could move `apiBaseUrl`
/// would otherwise simply serve their own key, which defeats the whole threat
/// model. Do not "fix" this by loading the key over the network.
///
/// Cross-language parity with the server's BouncyCastle signer is pinned by the
/// fixture in `Tests/.../Fixtures/config/`; see that directory's README.
public struct ConfigSignatureVerifier: Sendable {
    private let publicKey: Curve25519.Signing.PublicKey?

    /// Creates a verifier over a raw 32-byte Ed25519 public key.
    ///
    /// A malformed key does not throw: it produces a verifier that rejects
    /// everything. A build shipped with a broken key must degrade to bundled
    /// defaults, not crash on launch.
    public init(publicKey rawKey: Data) {
        self.publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: rawKey)
    }

    /// Creates a verifier from a base64-encoded raw public key.
    public init(publicKeyBase64: String) {
        let trimmed = publicKeyBase64.trimmingCharacters(in: .whitespacesAndNewlines)
        self.init(publicKey: Data(base64Encoded: trimmed) ?? Data())
    }

    /// True when the verifier holds a usable key. A false value means every
    /// verification will fail, which callers surface as `config.reject`.
    public var isConfigured: Bool { publicKey != nil }

    /// Verifies `signature` over the canonical bytes of the document.
    ///
    /// Returns `false` rather than throwing for every failure mode - bad key,
    /// bad base64, wrong signature length, wrong signature - because a tampered
    /// cache must fall back to bundled defaults, never propagate an error that
    /// some call site might treat as fatal.
    ///
    /// - Parameters:
    ///   - signature: raw 64-byte Ed25519 signature.
    ///   - canonicalBytes: output of `ConfigCanonicalizer.canonicalize(_:)`.
    public func isValid(signature: Data, canonicalBytes: Data) -> Bool {
        guard let publicKey, signature.count == 64 else { return false }
        return publicKey.isValidSignature(signature, for: canonicalBytes)
    }

    /// Verifies a base64-encoded signature over the canonical bytes.
    ///
    /// An empty or whitespace-only signature is rejected before any decoding.
    /// That is not a theoretical case: server migration 003 seeds config v1 with
    /// an empty signature placeholder, signed at startup by `ConfigBaselineSeeder`,
    /// so a client can genuinely observe that transient state.
    public func isValid(signatureBase64: String, canonicalBytes: Data) -> Bool {
        let trimmed = signatureBase64.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let signature = Data(base64Encoded: trimmed) else { return false }
        return isValid(signature: signature, canonicalBytes: canonicalBytes)
    }

    /// Canonicalizes `documentBytes` and verifies the signature over the result.
    ///
    /// This is the call site the cache read and the fetch path both use, so the
    /// two can never drift apart on which bytes were actually signed.
    public func isValid(signatureBase64: String, documentBytes: Data) -> Bool {
        guard let canonical = try? ConfigCanonicalizer.canonicalize(documentBytes) else { return false }
        return isValid(signatureBase64: signatureBase64, canonicalBytes: canonical)
    }
}

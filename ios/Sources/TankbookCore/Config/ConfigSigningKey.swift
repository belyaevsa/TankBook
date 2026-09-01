import Foundation

/// The public half of the config-signing key, compiled into the app binary
/// (docs/CONFIG.md -> "Signed payload" and "Defence in depth": the key is
/// injected, never fetched). `GET /v1/config/public-key` exists for operational
/// tooling only - an attacker who could move `apiBaseUrl` could otherwise serve
/// their own key, which defeats the whole threat model.
///
/// Two values, one per build configuration, and the split is deliberate:
///
/// - **DEBUG** bundles the public half of the DEV signing key
///   (`backend/src/Tankbook.Api/appsettings.Development.json` ->
///   `Config:SigningKey`). Bundling it exercises the full sign-verify path end
///   to end against the dev backend, so a broken key, canonicalizer or verifier
///   fails in development, not in the field.
/// - **RELEASE** bundles the **production** key's public half, provisioned
///   2026-09-01 (keyId `c35fceea2d937708` - the first 16 hex characters of the
///   key's SHA-256, which is what `GET /v1/config/public-key` reports, so the
///   two can be compared without handling the private half). Before that this
///   branch returned `""`, which made every signature fail OPEN to bundled
///   defaults and meant remote config could never verify - a release blocker
///   enforced by `ConfigSigningKeyTests` rather than left as a silent fail-open
///   (docs/PRACTICES.md §6.1).
///
/// **This value is public and belongs in the binary; the matching PRIVATE seed
/// must be deployed as the server's `Config:SigningKey`.** Bundling one without
/// deploying the other does not fail loudly: signatures simply never verify and
/// the app falls back to `Config.default.json` for the life of the build. Rotating
/// the server key without shipping a new binary has exactly the same effect, which
/// is why the keyId is written above - it is the cheap way to tell a mismatch from
/// an outage.
public enum ConfigSigningKey {
    /// Base64-encoded Ed25519 public key: the dev key's public half in DEBUG,
    /// the production key's in RELEASE.
    public static var bundledPublicKeyBase64: String {
        #if DEBUG
        return "cdLMDhOLOTNvUCbnluHI9zchTSbr4iE2s+EFKzkrQlk="
        #else
        return "gaFhyMVjkJDYTki5SxCJzsz0Nc0Qw+S4djXkReWiqKw="
        #endif
    }
}

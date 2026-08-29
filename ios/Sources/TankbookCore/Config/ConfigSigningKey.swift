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
/// - **RELEASE** stays empty: the production signing key is not provisioned
///   (`appsettings.json` has `Config:SigningKey = ""`) and provisioning it is an
///   ops action nobody in this repo can take. An empty key makes every signature
///   fail OPEN to bundled defaults - the correct fail-open behaviour - but it
///   also means remote config can never verify, so an empty RELEASE key is a
///   release blocker, enforced by `ConfigSigningKeyTests` instead of left as a
///   silent fail-open (docs/PRACTICES.md §6.1).
public enum ConfigSigningKey {
    /// Base64-encoded Ed25519 public key. The dev key's public half in DEBUG;
    /// empty in RELEASE until ops provisions the production key.
    public static var bundledPublicKeyBase64: String {
        #if DEBUG
        return "cdLMDhOLOTNvUCbnluHI9zchTSbr4iE2s+EFKzkrQlk="
        #else
        return ""
        #endif
    }
}

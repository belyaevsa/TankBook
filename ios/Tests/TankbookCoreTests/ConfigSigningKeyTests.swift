import Foundation
import Testing
@testable import TankbookCore

// PR.3a: the bundled config-signing public key (docs/CONFIG.md ->
// "Defence in depth": the key is injected, never fetched). Two invariants:
// 1. DEBUG bundles the DEV signing key's public half, so the end-to-end path is
//    exercised against the dev backend. Parity with the backend signer is pinned
//    by the backend's ConfigSigningKeyParityTests, which reads this exact
//    literal.
// 2. No build ships with an empty key. An empty key fails every signature OPEN
//    to bundled defaults, so remote config can never verify. The RELEASE key is
//    not provisioned yet (appsettings.json Config:SigningKey = ""), which is why
//    the RELEASE branch returns "" - and why that branch fails
//    `aBuildWithNoConfigSigningKeyIsAReleaseBlocker`, turning a silent fail-open
//    into an explicit release blocker (docs/PRACTICES.md §6.1).

private let devPublicKeyBase64 = "cdLMDhOLOTNvUCbnluHI9zchTSbr4iE2s+EFKzkrQlk="

@Suite("ConfigSigningKey (PR.3a)")
struct ConfigSigningKeyTests {

    @Test func bundledKeyIsTheDevSignersPublicHalfInDebug() {
        #if DEBUG
        #expect(ConfigSigningKey.bundledPublicKeyBase64 == devPublicKeyBase64,
                "the DEBUG bundled key must be the dev signing key's public half")
        #expect(ConfigSigningKey.bundledPublicKeyBase64.count == 44,
                "an Ed25519 public key is 32 bytes -> 44 base64 characters")
        #endif
    }

    @Test func aBuildWithNoConfigSigningKeyIsAReleaseBlocker() {
        #expect(!ConfigSigningKey.bundledPublicKeyBase64.isEmpty,
                "an empty config signing key means remote config can never verify - a release blocker")
    }

    /// Runs in **every** configuration, unlike the DEBUG-only checks above.
    ///
    /// A non-empty key that is not a usable Ed25519 key fails exactly as an empty
    /// one does - every signature fails open to bundled defaults - but it *looks*
    /// provisioned, so the release blocker above would pass while remote config
    /// stayed inert. The realistic way to get there is a truncated or mangled
    /// paste when a key is provisioned by hand, which is how these values arrive.
    @Test func theBundledKeyIsAUsableEd25519KeyInEveryConfiguration() {
        let key = ConfigSigningKey.bundledPublicKeyBase64
        let raw = Data(base64Encoded: key.trimmingCharacters(in: .whitespacesAndNewlines))
        #expect(raw != nil, "the bundled key must be valid base64")
        #expect(raw?.count == 32, "an Ed25519 public key is exactly 32 bytes")
        // The end that matters: the verifier must actually accept it as a key.
        // Asserted through the real type rather than by counting bytes, so a
        // value that is 32 bytes but not a valid curve point still fails here.
        #expect(ConfigSignatureVerifier(publicKeyBase64: key).isConfigured,
                "the verifier must accept the bundled key, or no signature can ever verify")
    }
}

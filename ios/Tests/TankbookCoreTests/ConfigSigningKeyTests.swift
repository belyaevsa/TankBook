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
}

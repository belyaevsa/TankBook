import Foundation
import Testing
@testable import TankbookCore

// P0.12c: the compiled-in host allowlist (docs/CONFIG.md -> "Guardrails on
// apiBaseUrl"). The near-misses are the whole point: a naive `hasSuffix` would
// pass several of them, so each is a required case, not a convenience.

@Suite("HostAllowlist (P0.12c)")
struct HostAllowlistTests {

    // MARK: Accept list (the negative control)

    @Test func acceptsTheApexDomain() {
        #expect(HostAllowlist.allows(url: URL(string: "https://tankbook.app")!))
    }

    @Test func acceptsASubdomain() {
        #expect(HostAllowlist.allows(url: URL(string: "https://api.tankbook.app")!))
    }

    @Test func acceptsANestedSubdomain() {
        #expect(HostAllowlist.allows(url: URL(string: "https://eu.api.tankbook.app")!))
    }

    @Test func acceptsCaseInsensitively() {
        #expect(HostAllowlist.allows(url: URL(string: "https://API.Tankbook.APP")!))
        #expect(HostAllowlist.allows(url: URL(string: "https://Api.Tankbook.App/")!))
    }

    // MARK: Reject list (each asserted individually)

    @Test func rejectsSuffixWithoutALabelBoundary() {
        #expect(!HostAllowlist.allows(url: URL(string: "https://evil-tankbook.app")!))
    }

    @Test func rejectsOurDomainAsAPrefixOfTheirs() {
        #expect(!HostAllowlist.allows(url: URL(string: "https://tankbook.app.evil.com")!))
    }

    @Test func rejectsAHyphenatedLookalike() {
        #expect(!HostAllowlist.allows(url: URL(string: "https://tankbook-app.com")!))
    }

    @Test func rejectsATrailingDotFQDN() {
        #expect(!HostAllowlist.allows(url: URL(string: "https://api.tankbook.app.")!))
    }

    @Test func rejectsCaseInsensitivePrefixAttack() {
        #expect(!HostAllowlist.allows(url: URL(string: "https://API.TANKBOOK.APP.EVIL.COM")!))
    }

    @Test func rejectsTheRightHostOnTheWrongScheme() {
        // Right host, wrong scheme: HTTPS only.
        #expect(!HostAllowlist.allows(url: URL(string: "http://api.tankbook.app")!))
    }

    @Test func rejectsAUserinfoAuthorityHidingAnEvilHost() {
        // The `api.tankbook.app` before the @ is userinfo, not the host; the
        // real host is evil.com and must be rejected.
        #expect(!HostAllowlist.allows(url: URL(string: "https://api.tankbook.app@evil.com/")!))
    }

    @Test func rejectsAnUnrelatedDomain() {
        #expect(!HostAllowlist.allows(url: URL(string: "https://evil.com")!))
    }

    @Test func rejectsAURLWithNoHost() {
        #expect(!HostAllowlist.allows(url: URL(string: "https://")!))
    }

    @Test func rejectsAnIpAddressHost() {
        #expect(!HostAllowlist.allows(url: URL(string: "https://192.168.1.1")!))
    }

    // MARK: Host-string form

    @Test func hostStringFormMatchesLabelBoundaries() {
        #expect(HostAllowlist.allows(host: "tankbook.app"))
        #expect(HostAllowlist.allows(host: "api.tankbook.app"))
        #expect(HostAllowlist.allows(host: "API.TANKBOOK.APP"))
        #expect(!HostAllowlist.allows(host: "evil-tankbook.app"))
        #expect(!HostAllowlist.allows(host: "tankbook.app.evil.com"))
        #expect(!HostAllowlist.allows(host: "tankbook-app.com"))
        #expect(!HostAllowlist.allows(host: nil))
        #expect(!HostAllowlist.allows(host: ""))
    }
}

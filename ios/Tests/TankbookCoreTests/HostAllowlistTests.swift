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
        #expect(HostAllowlist.allows(url: URL(string: "https://tankbook.live")!))
    }

    @Test func acceptsASubdomain() {
        #expect(HostAllowlist.allows(url: URL(string: "https://api.tankbook.live")!))
    }

    @Test func acceptsANestedSubdomain() {
        #expect(HostAllowlist.allows(url: URL(string: "https://eu.api.tankbook.live")!))
    }

    @Test func acceptsCaseInsensitively() {
        #expect(HostAllowlist.allows(url: URL(string: "https://API.Tankbook.LIVE")!))
        #expect(HostAllowlist.allows(url: URL(string: "https://Api.Tankbook.Live/")!))
    }

    // MARK: Reject list (each asserted individually)

    @Test func rejectsSuffixWithoutALabelBoundary() {
        #expect(!HostAllowlist.allows(url: URL(string: "https://evil-tankbook.live")!))
    }

    @Test func rejectsOurDomainAsAPrefixOfTheirs() {
        #expect(!HostAllowlist.allows(url: URL(string: "https://tankbook.live.evil.com")!))
    }

    @Test func rejectsAHyphenatedLookalike() {
        #expect(!HostAllowlist.allows(url: URL(string: "https://tankbook-app.com")!))
    }

    @Test func rejectsATrailingDotFQDN() {
        #expect(!HostAllowlist.allows(url: URL(string: "https://api.tankbook.live.")!))
    }

    @Test func rejectsCaseInsensitivePrefixAttack() {
        #expect(!HostAllowlist.allows(url: URL(string: "https://API.TANKBOOK.LIVE.EVIL.COM")!))
    }

    @Test func rejectsTheRightHostOnTheWrongScheme() {
        // Right host, wrong scheme: HTTPS only.
        #expect(!HostAllowlist.allows(url: URL(string: "http://api.tankbook.live")!))
    }

    @Test func rejectsAUserinfoAuthorityHidingAnEvilHost() {
        // The `api.tankbook.live` before the @ is userinfo, not the host; the
        // real host is evil.com and must be rejected.
        #expect(!HostAllowlist.allows(url: URL(string: "https://api.tankbook.live@evil.com/")!))
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
        #expect(HostAllowlist.allows(host: "tankbook.live"))
        #expect(HostAllowlist.allows(host: "api.tankbook.live"))
        #expect(HostAllowlist.allows(host: "API.TANKBOOK.LIVE"))
        #expect(!HostAllowlist.allows(host: "evil-tankbook.live"))
        #expect(!HostAllowlist.allows(host: "tankbook.live.evil.com"))
        #expect(!HostAllowlist.allows(host: "tankbook-app.com"))
        #expect(!HostAllowlist.allows(host: nil))
        #expect(!HostAllowlist.allows(host: ""))
    }
}

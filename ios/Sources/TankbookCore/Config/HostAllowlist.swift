import Foundation

/// The compiled-in allowlist of hosts the app may talk to
/// (docs/CONFIG.md -> "Guardrails on apiBaseUrl", docs/SECURITY.md -> "Defence
/// in depth").
///
/// This is the **first** of two independent checkpoints: config validation
/// refuses a document whose `apiBaseUrl` is not here, and `TankbookHTTPClient`
/// re-checks the same rule on every request so a bypass of config validation
/// still cannot reach an attacker's host.
///
/// The rule is deliberately a **suffix over a label boundary**, not a naive
/// `hasSuffix`: a host is allowed when it equals `tankbook.app` or ends with
/// `.tankbook.app`. That accepts `api.tankbook.app` and `eu.api.tankbook.app`
/// while rejecting every near-miss that shares bytes without sharing the label:
/// `evil-tankbook.app` (suffix, no boundary), `tankbook.app.evil.com` (our
/// domain as a prefix of theirs), `tankbook-app.com`.
///
/// The allowlist is **compiled in by design** (docs/CONFIG.md -> "Config can
/// never disable a security control"). It has no config key, is never read from
/// a file, and is not injectable in Release. HTTPS is required regardless of
/// host: a non-TLS scheme is rejected even for an allowlisted domain.
public enum HostAllowlist {
    /// The single trusted domain suffix (docs/CONFIG.md).
    ///
    /// **PLACEHOLDER - this domain is not registered yet.** No public domain has
    /// been bought for the app, so this value is a stand-in, not a decision. It
    /// is deliberately the *only* place the domain appears in shipping code:
    /// changing it later is a one-line edit here, and `allows(host:)` /
    /// `allows(url:)` derive everything from it.
    ///
    /// **Shipping with the placeholder unchanged is a release blocker.** The
    /// allowlist is the control that stops a moved `apiBaseUrl` from reaching an
    /// attacker (docs/SECURITY.md), and an allowlist naming a domain we do not
    /// control is worse than useless: someone else can register it. Set this,
    /// and `Config.default.json`'s `apiBaseUrl`, before any real deployment.
    ///
    /// Note the mechanism itself is domain-agnostic and fully tested - the
    /// label-boundary rule, HTTPS enforcement and the userinfo handling do not
    /// depend on which domain this is, so replacing the value does not weaken
    /// or re-open any of it.
    public static let allowedDomain = "tankbook.app"

    /// Whether a host string is inside the allowlist. Case-insensitive, matched
    /// on label boundaries: equal to the domain, or a subdomain ending in
    /// `.tankbook.app`. A nil or empty host is rejected.
    public static func allows(host: String?) -> Bool {
        guard let host, !host.isEmpty else { return false }
        let lower = host.lowercased()
        if lower == allowedDomain { return true }
        if lower.hasSuffix("." + allowedDomain) { return true }
        return false
    }

    /// Whether a URL is allowed: HTTPS only, and its host is in the allowlist.
    ///
    /// The host is read via `URLComponents.host`, never by string-parsing the
    /// URL. That is the property that makes an embedded-userinfo authority such
    /// as `https://api.tankbook.app@evil.com/` resolve to `evil.com` (the real
    /// host), which is then rejected: the `api.tankbook.app` before the `@` is
    /// userinfo, not the host.
    public static func allows(url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "https",
              let host = components.host else {
            return false
        }
        return allows(host: host)
    }
}

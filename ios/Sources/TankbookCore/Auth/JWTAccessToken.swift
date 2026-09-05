import Foundation

/// Reads the `exp` claim from the app's own access token **without verifying
/// it**. The server mints the access token as an RS256 JWT whose payload
/// carries a standard `exp` (Unix seconds) alongside `iss`/`aud`/`sub`/
/// `device_id` (docs/API.md -> Auth; backend `JwtAccessTokenIssuer`).
///
/// RV.59 uses it as a HINT so a bearer the client can already tell is expired
/// is refreshed BEFORE the first request goes out, instead of spending round
/// trips learning it from a 401. It is deliberately unverified:
///
/// - The server verifies the signature on every request; nothing here is an
///   access decision, so an attacker-edited token changes no control plane.
/// - A tampered or unreadable `exp` can only SUPPRESS the pre-refresh, and the
///   ordinary 401 -> refresh -> replay path then handles it exactly as before.
///
/// Returns nil when the token is not a three-segment JWT, its payload does not
/// parse, or it carries no numeric `exp`. nil means "expiry unknown", and the
/// caller must then NOT refresh speculatively: every refresh rotates the
/// refresh chain, and an unnecessary rotation is not free (docs/API.md: reuse
/// of a rotated token is the theft signal).
public enum JWTAccessToken {
    /// The expiry instant carried by the token's `exp` claim, or nil when it
    /// cannot be read (the "unknown" case above).
    public static func expiryDate(of token: String) -> Date? {
        let segments = token.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count == 3,
              let payload = base64URLDecode(String(segments[1])),
              let json = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
              let seconds = json["exp"] as? NSNumber else { return nil }
        return Date(timeIntervalSince1970: seconds.doubleValue)
    }

    /// base64url (RFC 4648 §5) without padding: `-`/`_` in place of `+`/`/`,
    /// and the padding `Data(base64Encoded:)` requires re-added before decoding.
    private static func base64URLDecode(_ string: String) -> Data? {
        var padded = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = padded.count % 4
        if remainder > 0 {
            padded += String(repeating: "=", count: 4 - remainder)
        }
        return Data(base64Encoded: padded)
    }
}

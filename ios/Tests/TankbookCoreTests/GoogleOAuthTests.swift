import CryptoKit
import Foundation
import Testing
@testable import TankbookCore

/// The pure half of the Google sign-in flow (SH.4). Every rule these assert is
/// one an attacker or a misprovisioned build would otherwise exercise for us -
/// so each test names the property, not the method.
@Suite("Google OAuth (PKCE) - the pure half")
struct GoogleOAuthTests {

    /// A deterministic byte source, so the whole authorization URL is
    /// assertable. Production passes `GoogleOAuth.systemRandomBytes`.
    ///
    /// It varies **per call**, not just per seed: a source returning one
    /// constant would hand the verifier, the state and the nonce the same bytes,
    /// which is precisely the defect `secretsAreIndependent` exists to catch -
    /// the double would make the bug untestable by exhibiting it.
    private static func fixedBytes(_ seed: UInt8) -> (Int) -> Data {
        var call = 0
        return { count in
            call += 1
            return Data((0..<count).map {
                UInt8(truncatingIfNeeded: Int(seed) &+ call &* 101 &+ $0)
            })
        }
    }

    private static let config = GoogleOAuth.Configuration.iOS(
        clientId: "1234567890-abcdef.apps.googleusercontent.com")

    private static func request(seed: UInt8 = 0x41) throws -> GoogleOAuth.Request {
        try GoogleOAuth.begin(configuration: config, randomBytes: fixedBytes(seed))
    }

    // MARK: - Configuration

    @Test("the redirect URI is the reversed client id, and the callback scheme is derived from it")
    func reversedClientId() {
        #expect(Self.config.redirectURI
            == "com.googleusercontent.apps.1234567890-abcdef:/oauth2redirect")
        #expect(Self.config.callbackScheme == "com.googleusercontent.apps.1234567890-abcdef")
    }

    @Test("an empty client id fails at the button rather than building a request")
    func misconfiguredClientIsRefused() {
        let empty = GoogleOAuth.Configuration.iOS(clientId: "")
        #expect(throws: GoogleOAuth.Failure.misconfigured) {
            _ = try GoogleOAuth.begin(configuration: empty, randomBytes: Self.fixedBytes(0x41))
        }
    }

    @Test("Google is provisioned only for a real client id")
    func provisioningGate() {
        #expect(GoogleOAuth.Configuration.provisioned(
            clientId: "1234567890-abcdef.apps.googleusercontent.com") != nil)
        #expect(GoogleOAuth.Configuration.provisioned(clientId: nil) == nil)
        #expect(GoogleOAuth.Configuration.provisioned(clientId: "") == nil)
        // A plist carrying the unexpanded literal. Measured: THIS project's
        // Release build ships an empty string instead (Xcode expands an
        // undefined setting to nothing), so emptiness is what covers Release -
        // but the literal survives in a hand-edited plist, where it is a
        // non-empty string that would otherwise read as provisioned.
        #expect(GoogleOAuth.Configuration.provisioned(
            clientId: "$(TANKBOOK_GOOGLE_CLIENT_ID)") == nil)
        // Not a Google client id at all - refused rather than carried into a
        // flow that would fail at the authorization endpoint.
        #expect(GoogleOAuth.Configuration.provisioned(clientId: "not-a-client-id") == nil)
    }

    // MARK: - The authorization request

    @Test("the authorization request is PKCE S256, and the challenge is the SHA-256 of the verifier")
    func challengeProvesTheVerifier() throws {
        let request = try Self.request()
        let items = try #require(
            URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.queryItems)
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }

        #expect(value("code_challenge_method") == "S256")
        #expect(value("response_type") == "code")
        #expect(value("client_id") == Self.config.clientId)
        #expect(value("redirect_uri") == Self.config.redirectURI)
        #expect(value("scope") == "openid email")
        #expect(value("state") == request.state)
        #expect(value("nonce") == request.nonce)

        // The challenge must be the hash of the verifier, not the verifier and
        // not an independent random value - that identity is the whole of PKCE.
        // Computed here from the verifier rather than copied from a constant, so
        // the assertion cannot pass against a challenge that hashes nothing.
        let expected = GoogleOAuth.base64URLEncode(
            Data(SHA256.hash(data: Data(request.codeVerifier.utf8))))
        #expect(value("code_challenge") == expected)
        #expect(value("code_challenge") != request.codeVerifier)
    }

    @Test("the verifier, state and nonce are independent secrets, not one value reused")
    func secretsAreIndependent() throws {
        let request = try Self.request()
        #expect(request.codeVerifier != request.state)
        #expect(request.codeVerifier != request.nonce)
        #expect(request.state != request.nonce)
        // RFC 7636 §4.1: a verifier is 43-128 characters. 32 bytes of base64url
        // is 43, the minimum that carries full entropy.
        #expect(request.codeVerifier.count == 43)
    }

    @Test("two flows never share a verifier or a state")
    func secretsAreFreshPerFlow() throws {
        let first = try GoogleOAuth.begin(configuration: Self.config)
        let second = try GoogleOAuth.begin(configuration: Self.config)
        #expect(first.codeVerifier != second.codeVerifier)
        #expect(first.state != second.state)
        #expect(first.nonce != second.nonce)
    }

    @Test("the account chooser is forced, so the J11a provider switch can reach another account")
    func promptSelectsAccount() throws {
        let request = try Self.request()
        let items = try #require(
            URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(items.first { $0.name == "prompt" }?.value == "select_account")
    }

    // MARK: - The callback

    @Test("a callback carrying the matching state yields its code")
    func goodCallback() throws {
        let request = try Self.request()
        let url = try #require(URL(
            string: "\(request.callbackScheme):/oauth2redirect?code=abc123&state=\(request.state)"))
        #expect(try GoogleOAuth.authorizationCode(fromCallback: url, request: request) == "abc123")
    }

    @Test("a callback whose state does not match is refused - it is a sign-in we did not start")
    func stateMismatchIsRefused() throws {
        let request = try Self.request()
        let url = try #require(URL(
            string: "\(request.callbackScheme):/oauth2redirect?code=abc123&state=someone-elses"))
        #expect(throws: GoogleOAuth.Failure.stateMismatch) {
            _ = try GoogleOAuth.authorizationCode(fromCallback: url, request: request)
        }
    }

    @Test("a callback with no state at all is refused, not treated as absent-therefore-fine")
    func missingStateIsRefused() throws {
        let request = try Self.request()
        let url = try #require(URL(string: "\(request.callbackScheme):/oauth2redirect?code=abc123"))
        #expect(throws: GoogleOAuth.Failure.stateMismatch) {
            _ = try GoogleOAuth.authorizationCode(fromCallback: url, request: request)
        }
    }

    @Test("access_denied reads as a cancellation, not as an error to report")
    func accessDeniedIsCancellation() throws {
        let request = try Self.request()
        let url = try #require(URL(
            string: "\(request.callbackScheme):/oauth2redirect?error=access_denied"))
        #expect(throws: GoogleOAuth.Failure.cancelled) {
            _ = try GoogleOAuth.authorizationCode(fromCallback: url, request: request)
        }
    }

    @Test("any other provider error keeps its machine code and carries nothing else")
    func providerErrorKeepsItsCode() throws {
        let request = try Self.request()
        let url = try #require(URL(
            string: "\(request.callbackScheme):/oauth2redirect?error=invalid_scope"))
        #expect(throws: GoogleOAuth.Failure.denied(code: "invalid_scope")) {
            _ = try GoogleOAuth.authorizationCode(fromCallback: url, request: request)
        }
    }

    @Test("a callback with a state but no code is malformed, not a silent success")
    func missingCodeIsRefused() throws {
        let request = try Self.request()
        let url = try #require(URL(
            string: "\(request.callbackScheme):/oauth2redirect?state=\(request.state)"))
        #expect(throws: GoogleOAuth.Failure.malformedCallback) {
            _ = try GoogleOAuth.authorizationCode(fromCallback: url, request: request)
        }
    }

    // MARK: - The token exchange

    @Test("the token request sends the verifier and carries no client secret")
    func tokenRequestShape() throws {
        let request = try Self.request()
        let urlRequest = GoogleOAuth.tokenRequest(
            configuration: Self.config, code: "the-code", request: request)
        let bodyData = try #require(urlRequest.httpBody)
        let body = try #require(String(bytes: bodyData, encoding: .utf8))

        #expect(urlRequest.httpMethod == "POST")
        #expect(urlRequest.url == Self.config.tokenEndpoint)
        #expect(urlRequest.value(forHTTPHeaderField: "Content-Type")
            == "application/x-www-form-urlencoded")
        #expect(body.contains("code_verifier=\(request.codeVerifier)"))
        #expect(body.contains("grant_type=authorization_code"))
        #expect(body.contains("code=the-code"))
        // A public client has no secret, and shipping one would break hard rule
        // 11. Asserted so nobody "fixes" a 401 by adding one.
        #expect(!body.contains("client_secret"))
    }

    @Test("the token endpoint is Google's, which the Tankbook host allowlist rightly refuses")
    func tokenEndpointIsOutsideTheAllowlist() {
        // Pins the reason the app layer uses a bare URLSession for this one
        // request: routing it through TankbookHTTPClient could not work, and
        // widening the allowlist to make it work would break the host binding.
        #expect(!HostAllowlist.allows(url: Self.config.tokenEndpoint))
        #expect(!HostAllowlist.allows(url: Self.config.authorizationEndpoint))
    }

    // MARK: - The identity

    /// An unsigned JWT carrying `claims`. The signature is deliberately garbage:
    /// nothing on the device verifies it, and a test that signed it would be
    /// asserting a check this tier does not perform.
    private static func idToken(claims: [String: Any]) throws -> String {
        let payload = try JSONSerialization.data(withJSONObject: claims)
        return [
            GoogleOAuth.base64URLEncode(Data(#"{"alg":"RS256"}"#.utf8)),
            GoogleOAuth.base64URLEncode(payload),
            "not-a-real-signature"
        ].joined(separator: ".")
    }

    @Test("a good response yields the Google identity with its email")
    func identityFromResponse() throws {
        let request = try Self.request()
        let token = try Self.idToken(
            claims: ["nonce": request.nonce, "email": "driver@example.com"])
        let data = try JSONSerialization.data(withJSONObject: ["id_token": token])

        let identity = try GoogleOAuth.identity(
            fromTokenResponse: data, statusCode: 200, request: request)
        #expect(identity.provider == .google)
        #expect(identity.idToken == token)
        #expect(identity.email == "driver@example.com")
    }

    @Test("an id token minted for a different request is refused on its nonce")
    func nonceMismatchIsRefused() throws {
        let request = try Self.request()
        let token = try Self.idToken(
            claims: ["nonce": "some-other-flows-nonce", "email": "driver@example.com"])
        let data = try JSONSerialization.data(withJSONObject: ["id_token": token])

        #expect(throws: GoogleOAuth.Failure.nonceMismatch) {
            _ = try GoogleOAuth.identity(fromTokenResponse: data, statusCode: 200, request: request)
        }
    }

    @Test("an id token with no nonce claim is refused, so the check cannot be skipped by omission")
    func absentNonceIsRefused() throws {
        let request = try Self.request()
        let token = try Self.idToken(claims: ["email": "driver@example.com"])
        let data = try JSONSerialization.data(withJSONObject: ["id_token": token])

        #expect(throws: GoogleOAuth.Failure.nonceMismatch) {
            _ = try GoogleOAuth.identity(fromTokenResponse: data, statusCode: 200, request: request)
        }
    }

    @Test("a non-2xx token response is a failure even when it carries a token-shaped body")
    func errorStatusIsRefused() throws {
        let request = try Self.request()
        let token = try Self.idToken(claims: ["nonce": request.nonce])
        let data = try JSONSerialization.data(withJSONObject: ["id_token": token])

        #expect(throws: GoogleOAuth.Failure.tokenExchangeFailed) {
            _ = try GoogleOAuth.identity(fromTokenResponse: data, statusCode: 400, request: request)
        }
    }

    @Test("a 200 with no id_token is missingIDToken, not a silent empty identity")
    func missingIDTokenIsNamed() throws {
        let request = try Self.request()
        let data = try JSONSerialization.data(withJSONObject: ["access_token": "irrelevant"])
        #expect(throws: GoogleOAuth.Failure.missingIDToken) {
            _ = try GoogleOAuth.identity(fromTokenResponse: data, statusCode: 200, request: request)
        }
    }

    @Test("an email-less token still signs in - the server is the authority on that refusal")
    func emailIsOptionalOnTheDevice() throws {
        let request = try Self.request()
        let token = try Self.idToken(claims: ["nonce": request.nonce])
        let data = try JSONSerialization.data(withJSONObject: ["id_token": token])

        let identity = try GoogleOAuth.identity(
            fromTokenResponse: data, statusCode: 200, request: request)
        #expect(identity.email == nil)
    }

    // MARK: - Encoding

    @Test("base64url round-trips, and emits none of base64's three query-hostile characters")
    func base64URLRoundTrip() throws {
        // 0xFB 0xFF encodes to "+/8=" in standard base64 - all three characters
        // that must not survive into a URL query.
        let data = Data([0xFB, 0xFF, 0xBF, 0x00, 0x10, 0x83])
        let encoded = GoogleOAuth.base64URLEncode(data)
        #expect(!encoded.contains("+"))
        #expect(!encoded.contains("/"))
        #expect(!encoded.contains("="))
        #expect(GoogleOAuth.base64URLDecode(encoded) == data)
    }

    @Test("base64url decoding restores the padding it strips, at every remainder")
    func base64URLDecodesUnpadded() {
        for length in 1...8 {
            let data = Data((0..<length).map { UInt8(truncatingIfNeeded: $0 &* 37 &+ 11) })
            let encoded = GoogleOAuth.base64URLEncode(data)
            #expect(GoogleOAuth.base64URLDecode(encoded) == data,
                    "round trip failed at \(length) bytes")
        }
    }

    @Test("the form body escapes the characters a verifier and a redirect actually contain")
    func formEncodingEscapesReservedCharacters() {
        let encoded = GoogleOAuth.formURLEncoded([
            "redirect_uri": "com.example.app:/oauth2redirect",
            "code_verifier": "a-b_c~d.e"
        ])
        // A raw ":" or "/" in a form body is ambiguous, and a raw "+" decodes as
        // a space - which would corrupt a verifier and fail the exchange with a
        // message about the code rather than about the encoding.
        #expect(encoded.contains("redirect_uri=com.example.app%3A%2Foauth2redirect"))
        // The unreserved set is left alone; escaping it is legal but noisy.
        #expect(encoded.contains("code_verifier=a-b_c~d.e"))
    }

    @Test("unverifiedClaims returns empty for anything unreadable rather than throwing")
    func malformedTokensDegradeToEmptyClaims() {
        #expect(GoogleOAuth.unverifiedClaims("").isEmpty)
        #expect(GoogleOAuth.unverifiedClaims("only.two").isEmpty)
        #expect(GoogleOAuth.unverifiedClaims("a.!!!not-base64!!!.c").isEmpty)
    }
}

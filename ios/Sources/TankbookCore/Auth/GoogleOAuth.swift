import CryptoKit
import Foundation

/// The Google sign-in flow, implemented directly rather than through Google's
/// SDK (decided 2026-09-01, product owner: a third-party SDK and its two
/// transitive dependencies are not worth one button).
///
/// This file is the **pure half** - building the authorization URL, minting and
/// proving the PKCE secret, validating the callback, shaping the token request
/// and reading the response. It performs no I/O and presents no UI, so every
/// rule below is pinned by a unit test at L1. The half that cannot be pure -
/// presenting `ASWebAuthenticationSession` and running the token POST - lives in
/// `ios/App/Sources/SignIn/GoogleWebAuthenticator.swift`, which is the P3.7
/// lesson: logic left in `ios/App` pins at L4 or nowhere.
///
/// The shape is OAuth 2.0 **authorization code with PKCE** (RFC 7636), which is
/// what Google requires of an installed app. Three properties matter:
///
/// - **No client secret exists.** A Google "iOS" OAuth client is a public
///   client; there is nothing here that hard rule 11 would object to shipping in
///   the bundle, and the `clientId` is a public identifier exactly as
///   `docs/SECURITY.md` already says of the Apple/Google client identifiers.
/// - **The code exchange must NOT go through `TankbookHTTPClient`.** It talks to
///   `oauth2.googleapis.com`, which `HostAllowlist` rightly refuses, and it must
///   carry no Tankbook bearer. That is not a limitation to work around - it is
///   the host-binding rule doing its job. The app layer uses a bare
///   `URLSession` for this one request and no other.
/// - **The `idToken` this produces is not trusted here.** It is handed to
///   `POST /auth/session`, which verifies the signature against Google's JWKS.
///   The client-side `nonce` check below is defence in depth, not verification.
public enum GoogleOAuth {

    // MARK: - Configuration

    /// The public identity of this app as a Google OAuth client. Every value is
    /// a public identifier, never a secret (`docs/SECURITY.md` -> "What must
    /// never ship in the bundle").
    public struct Configuration: Sendable, Equatable {
        /// Google's iOS client id, `<number>-<hash>.apps.googleusercontent.com`.
        public let clientId: String
        /// Where Google sends the browser back. For an iOS client this is the
        /// **reversed** client id as a custom scheme.
        public let redirectURI: String
        public let authorizationEndpoint: URL
        public let tokenEndpoint: URL
        /// `openid` for an id token at all; `email` because the backend refuses
        /// a token with no email (`IdTokenOutcome.MissingEmail`).
        public let scopes: [String]

        public init(
            clientId: String,
            redirectURI: String,
            authorizationEndpoint: URL = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!,
            tokenEndpoint: URL = URL(string: "https://oauth2.googleapis.com/token")!,
            scopes: [String] = ["openid", "email"]
        ) {
            self.clientId = clientId
            self.redirectURI = redirectURI
            self.authorizationEndpoint = authorizationEndpoint
            self.tokenEndpoint = tokenEndpoint
            self.scopes = scopes
        }

        /// The reversed-client-id redirect Google documents for an iOS client:
        /// `com.googleusercontent.apps.<id>:/oauth2redirect`.
        ///
        /// Note the **single** slash. Google's own iOS convention writes
        /// `scheme:/path`, and the redirect registered in the Cloud console must
        /// match this string byte for byte or the authorization request is
        /// rejected before the user sees anything.
        public static func iOS(clientId: String) -> Configuration {
            let reversed = Self.reversedClientId(clientId)
            return Configuration(clientId: clientId, redirectURI: "\(reversed):/oauth2redirect")
        }

        /// The configuration for a client id shipped in the bundle, or `nil`
        /// when Google is **not provisioned for this build**.
        ///
        /// SH.4's finding was a button that throws on tap - "a dead control and
        /// an App Review finding". The fix is not to hide the button by hand but
        /// to make its presence *derive* from whether the flow can run: the
        /// Sign in screen offers Google exactly when this returns non-nil, so
        /// the two can never disagree.
        ///
        /// Three shapes are refused. **Measured** on this project rather than
        /// assumed: with `TANKBOOK_GOOGLE_CLIENT_ID` undefined, a Release build
        /// ships `GoogleClientID` as an **empty string** - Xcode expands an
        /// undefined build setting to nothing rather than leaving the `$(...)`
        /// literal - so it is the emptiness check that carries the Release case.
        /// The `$(` guard covers the shape a hand-edited or differently
        /// generated plist can still carry, where the literal *does* survive and
        /// is a non-empty string that would otherwise read as provisioned. The
        /// suffix check refuses a value that is neither.
        public static func provisioned(clientId: String?) -> Configuration? {
            guard let clientId,
                  !clientId.isEmpty,
                  !clientId.hasPrefix("$("),
                  clientId.hasSuffix(".apps.googleusercontent.com") else {
                return nil
            }
            return .iOS(clientId: clientId)
        }

        /// `123-abc.apps.googleusercontent.com` -> `com.googleusercontent.apps.123-abc`.
        /// Splitting on the known suffix rather than reversing dot-separated
        /// labels: the client id's own leading label contains a `-` and may
        /// contain dots in no documented arrangement, so only the suffix is
        /// structure we are entitled to assume.
        static func reversedClientId(_ clientId: String) -> String {
            let suffix = ".apps.googleusercontent.com"
            guard clientId.hasSuffix(suffix) else { return clientId }
            return "com.googleusercontent.apps." + String(clientId.dropLast(suffix.count))
        }

        /// The scheme `ASWebAuthenticationSession` waits for. Derived from
        /// `redirectURI` so the two can never disagree.
        ///
        /// It deliberately needs **no `CFBundleURLTypes` entry**:
        /// `ASWebAuthenticationSession(url:callbackURLScheme:)` intercepts the
        /// callback itself. Registering the scheme app-wide would let any other
        /// app on the device hand us a crafted callback; not registering it
        /// keeps the redirect reachable only by the session that started it.
        public var callbackScheme: String? {
            guard let separator = redirectURI.firstIndex(of: ":") else { return nil }
            return String(redirectURI[redirectURI.startIndex..<separator])
        }
    }

    // MARK: - Failures

    /// Sign-in failures. None of these carries a token, a code, an email or a
    /// verifier (hard rule 12): the associated value on `denied` is the
    /// provider's own machine code, which is a fixed vocabulary.
    public enum Failure: Error, Sendable, Equatable {
        /// The user dismissed the browser sheet. Not an error to report - the
        /// caller returns to a working app in silence (hard rule 1).
        case cancelled
        /// Google answered the authorization request with an error, e.g.
        /// `access_denied`.
        case denied(code: String)
        /// The callback did not carry a usable authorization code.
        case malformedCallback
        /// The callback's `state` did not match the one we minted. This is the
        /// cross-site-request-forgery check: a callback we did not start.
        case stateMismatch
        /// The token endpoint refused the exchange, or answered unreadably.
        case tokenExchangeFailed
        /// The exchange succeeded but carried no `id_token` - without one there
        /// is nothing for `POST /auth/session` to verify.
        case missingIDToken
        /// The returned id token's `nonce` is not the one we asked for. Defence
        /// in depth against a token minted for some other request.
        case nonceMismatch
        /// The configuration is not usable (an empty client id, a redirect with
        /// no scheme). A programming or provisioning error, surfaced rather than
        /// crashed so a misprovisioned build fails at the button, not at launch.
        case misconfigured
    }

    // MARK: - Beginning the flow

    /// The one-time secrets for a single authorization attempt. Held only for
    /// the duration of the flow and never persisted: a verifier that outlives
    /// its exchange is a replayable secret.
    public struct Request: Sendable, Equatable {
        public let url: URL
        public let callbackScheme: String
        public let state: String
        public let nonce: String
        public let codeVerifier: String
    }

    /// Builds the authorization request. `randomBytes` is injected so a test can
    /// pin the exact URL; production passes the system CSPRNG.
    ///
    /// `prompt=select_account` is deliberate: without it Google silently reuses
    /// whichever account the system browser last used, which makes the J11a
    /// wrong-provider recovery ("use the other account") impossible to perform -
    /// the user taps and lands straight back in the account they are trying to
    /// leave.
    public static func begin(
        configuration: Configuration,
        randomBytes: (Int) -> Data = Self.systemRandomBytes
    ) throws -> Request {
        guard !configuration.clientId.isEmpty,
              let callbackScheme = configuration.callbackScheme,
              !callbackScheme.isEmpty else {
            throw Failure.misconfigured
        }

        let verifier = base64URLEncode(randomBytes(32))
        let challenge = base64URLEncode(Data(SHA256.hash(data: Data(verifier.utf8))))
        let state = base64URLEncode(randomBytes(16))
        let nonce = base64URLEncode(randomBytes(16))

        var components = URLComponents(url: configuration.authorizationEndpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: configuration.clientId),
            URLQueryItem(name: "redirect_uri", value: configuration.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: configuration.scopes.joined(separator: " ")),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "nonce", value: nonce),
            URLQueryItem(name: "prompt", value: "select_account")
        ]
        guard let url = components?.url else { throw Failure.misconfigured }

        return Request(
            url: url,
            callbackScheme: callbackScheme,
            state: state,
            nonce: nonce,
            codeVerifier: verifier
        )
    }

    // MARK: - The callback

    /// Reads the authorization code out of the callback URL, refusing anything
    /// that is not the answer to `request`.
    ///
    /// The `state` comparison is **constant-time over equal-length strings** by
    /// construction (both are 22-character base64url), but the check that
    /// matters is that it happens at all: without it any app or page that can
    /// reach the callback can complete somebody else's sign-in.
    public static func authorizationCode(fromCallback url: URL, request: Request) throws -> String {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = components.queryItems else {
            throw Failure.malformedCallback
        }
        func value(_ name: String) -> String? {
            items.first { $0.name == name }?.value
        }

        // The error branch is checked BEFORE state: a denial carries no state on
        // some providers, and reporting "stateMismatch" for a user who simply
        // tapped Cancel would name the wrong next step (hard rule 7).
        if let error = value("error") {
            throw error == "access_denied" ? Failure.cancelled : Failure.denied(code: error)
        }
        guard let state = value("state"), state == request.state else {
            throw Failure.stateMismatch
        }
        guard let code = value("code"), !code.isEmpty else {
            throw Failure.malformedCallback
        }
        return code
    }

    // MARK: - The token exchange

    /// The `POST` that trades the code for an id token. Built here so its shape
    /// is asserted at L1; executed by the app layer on a bare `URLSession`.
    public static func tokenRequest(
        configuration: Configuration,
        code: String,
        request: Request
    ) -> URLRequest {
        var urlRequest = URLRequest(url: configuration.tokenEndpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let form = [
            "client_id": configuration.clientId,
            "code": code,
            "code_verifier": request.codeVerifier,
            "grant_type": "authorization_code",
            "redirect_uri": configuration.redirectURI
        ]
        urlRequest.httpBody = Data(formURLEncoded(form).utf8)
        return urlRequest
    }

    /// Turns a token-endpoint response into the identity `POST /auth/session`
    /// takes, refusing a token that is not the answer to `request`.
    ///
    /// The id token is **decoded, not verified**. The signature check is the
    /// server's (`AppleGoogleIdTokenVerifier`), and duplicating it here would
    /// mean shipping a second implementation of the security-critical half in
    /// the tier that cannot be trusted anyway. What is worth doing on the device
    /// is the `nonce` comparison, which the server cannot do: only the client
    /// knows which nonce it asked for.
    public static func identity(
        fromTokenResponse data: Data,
        statusCode: Int,
        request: Request
    ) throws -> ProviderIdentity {
        guard (200..<300).contains(statusCode) else { throw Failure.tokenExchangeFailed }
        guard let response = try? JSONDecoder().decode(GoogleTokenResponse.self, from: data) else {
            throw Failure.tokenExchangeFailed
        }
        guard let idToken = response.idToken, !idToken.isEmpty else {
            throw Failure.missingIDToken
        }

        let claims = unverifiedClaims(idToken)
        guard claims["nonce"] as? String == request.nonce else {
            throw Failure.nonceMismatch
        }

        return ProviderIdentity(
            provider: .google,
            idToken: idToken,
            email: claims["email"] as? String
        )
    }

    // MARK: - JWT and encoding helpers

    /// The claims of a JWT **without checking its signature**. Named so no
    /// caller can mistake it for verification. Returns an empty dictionary for
    /// anything unreadable, so a malformed token fails the `nonce` comparison
    /// rather than throwing a different error from a parsing accident.
    static func unverifiedClaims(_ jwt: String) -> [String: Any] {
        let segments = jwt.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count == 3,
              let payload = base64URLDecode(String(segments[1])),
              let json = try? JSONSerialization.jsonObject(with: payload) as? [String: Any] else {
            return [:]
        }
        return json
    }

    /// base64url without padding (RFC 7636 §4.1: the verifier and challenge are
    /// both this alphabet, and `+`/`/`/`=` would be re-encoded in the query).
    static func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func base64URLDecode(_ string: String) -> Data? {
        var padded = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        // Re-add the padding base64url strips; without it `Data(base64Encoded:)`
        // returns nil for two thirds of all inputs.
        let remainder = padded.count % 4
        if remainder > 0 {
            padded += String(repeating: "=", count: 4 - remainder)
        }
        return Data(base64Encoded: padded)
    }

    /// `application/x-www-form-urlencoded`, sorted so the body is byte-stable
    /// and therefore assertable. `+` and `/` are escaped because a PKCE verifier
    /// is base64url and a redirect URI carries `:` and `/` - the default
    /// `.urlQueryAllowed` set leaves all of those alone, and a raw `+` in a form
    /// body decodes as a space.
    static func formURLEncoded(_ form: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return form.keys.sorted().map { key in
            let value = form[key] ?? ""
            let encoded = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
            return "\(key)=\(encoded)"
        }
        .joined(separator: "&")
    }

    /// The system CSPRNG. `SystemRandomNumberGenerator` is the platform's
    /// cryptographically secure source; the PKCE verifier and the state are the
    /// two secrets this flow rests on, so neither may come from a seeded or
    /// predictable generator.
    public static func systemRandomBytes(_ count: Int) -> Data {
        var generator = SystemRandomNumberGenerator()
        var data = Data(count: count)
        for index in 0..<count {
            data[index] = UInt8.random(in: UInt8.min...UInt8.max, using: &generator)
        }
        return data
    }
}

/// Google's token response. Only `id_token` is read: the access and refresh
/// tokens are Google's, they authorise nothing in Tankbook, and storing a
/// credential nothing consumes is a liability rather than a feature.
private struct GoogleTokenResponse: Decodable {
    let idToken: String?

    enum CodingKeys: String, CodingKey {
        case idToken = "id_token"
    }
}

import AuthenticationServices
import Foundation
import TankbookCore
import UIKit

/// The impure half of Google sign-in (SH.4): presenting
/// `ASWebAuthenticationSession` and running the token POST. Every decision this
/// file makes is in `GoogleOAuth`, which is pure and pinned at L1 - what is left
/// here is I/O and presentation, which is the smallest thing that cannot be
/// unit-tested (the P3.7 lesson).
///
/// Implemented without Google's SDK by decision (2026-09-01, product owner). The
/// SDK would add three packages to an app that has one dependency, for a flow
/// the system framework already performs.
@MainActor
final class GoogleWebAuthenticator: NSObject {
    private let configuration: GoogleOAuth.Configuration
    private let urlSession: URLSession
    /// Held for the flow's duration: an `ASWebAuthenticationSession` that is not
    /// retained is deallocated before the user can finish, and the sheet closes
    /// itself with no callback.
    private var session: ASWebAuthenticationSession?

    init(configuration: GoogleOAuth.Configuration, urlSession: URLSession = .shared) {
        self.configuration = configuration
        self.urlSession = urlSession
    }

    /// The whole flow: authorize in the browser, then exchange the code for an
    /// id token. The id token is handed on unverified - `POST /auth/session`
    /// checks its signature against Google's JWKS (hard rule 9 keeps the client
    /// out of that judgement).
    func signIn() async throws -> ProviderIdentity {
        let request = try GoogleOAuth.begin(configuration: configuration)
        let callback = try await authorize(request: request)
        let code = try GoogleOAuth.authorizationCode(fromCallback: callback, request: request)

        // Deliberately a bare URLSession, NOT TankbookHTTPClient: this request
        // goes to Google, which HostAllowlist refuses by design, and it must
        // carry no Tankbook bearer. Pinned by
        // `tokenEndpointIsOutsideTheAllowlist` so nobody "fixes" it by widening
        // the allowlist.
        let (data, response) = try await urlSession.data(
            for: GoogleOAuth.tokenRequest(
                configuration: configuration, code: code, request: request))
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        return try GoogleOAuth.identity(
            fromTokenResponse: data, statusCode: statusCode, request: request)
    }

    /// Presents the system browser sheet and returns the callback URL.
    private func authorize(request: GoogleOAuth.Request) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: request.url,
                callbackURLScheme: request.callbackScheme
            ) { url, error in
                if let url {
                    continuation.resume(returning: url)
                } else if let error = error as? ASWebAuthenticationSessionError,
                          error.code == .canceledLogin {
                    // The user dismissed the sheet. Not a failure to report -
                    // they return to a working app (hard rule 1).
                    continuation.resume(throwing: GoogleOAuth.Failure.cancelled)
                } else {
                    continuation.resume(throwing: GoogleOAuth.Failure.malformedCallback)
                }
            }
            session.presentationContextProvider = self
            // Shared browser session on purpose: a user already signed in to
            // Google on this device gets an account picker instead of a password
            // prompt. `prompt=select_account` is what keeps that from silently
            // reusing one account, which J11a's recovery depends on.
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            if !session.start() {
                continuation.resume(throwing: GoogleOAuth.Failure.misconfigured)
            }
        }
    }
}

extension GoogleWebAuthenticator: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        return scene?.windows.first(where: \.isKeyWindow)
            ?? scene?.windows.first
            ?? ASPresentationAnchor()
    }
}

extension GoogleOAuth.Configuration {
    /// The Info.plist key carrying the Google iOS client id. A **public
    /// identifier, not a secret** (`docs/SECURITY.md` - "The Apple/Google client
    /// identifiers *are* in the bundle"), so hard rule 11 is untouched: an IPA
    /// is a zip, and this value is meant to be readable.
    static let infoDictionaryKey = "GoogleClientID"

    /// The build's Google configuration, or `nil` when no client id is
    /// provisioned - in which case the Sign in screen offers no Google button
    /// at all, rather than one that throws on tap.
    static func fromBundle(_ bundle: Bundle = .main) -> GoogleOAuth.Configuration? {
        provisioned(clientId: bundle.object(forInfoDictionaryKey: infoDictionaryKey) as? String)
    }
}

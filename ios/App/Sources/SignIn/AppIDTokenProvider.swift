import AuthenticationServices
import Foundation
import UIKit
import TankbookCore

/// The production identity-token provider: Sign in with Apple via
/// `ASAuthorizationController` (docs/SECURITY.md -> "the server verifies the
/// token, so the client's job is to obtain it and hand it over"). Apple's
/// private-relay address is passed through as the display email.
///
/// Google sign-in runs the OAuth 2.0 authorization-code + PKCE flow directly
/// through `ASWebAuthenticationSession` (SH.4, 2026-09-01) - see
/// `GoogleWebAuthenticator` and the pure `GoogleOAuth` it drives. It throws
/// `AuthError.unsupportedProvider` only when no client id is provisioned for the
/// build, which is a state the Sign in screen never offers a button for.
/// Tests and screenshots inject `SignInTestSeed.StubIDTokenProvider` instead, so
/// this type is never exercised in CI (there is no Apple ID there).
@MainActor
final class AppIDTokenProvider: NSObject, IDTokenProvider {
    private var continuation: CheckedContinuation<ProviderIdentity, Error>?
    /// Retained across the flow: `GoogleWebAuthenticator` owns the
    /// `ASWebAuthenticationSession`, which dies with its owner.
    private var googleAuthenticator: GoogleWebAuthenticator?

    func signIn(provider: AuthProvider) async throws -> ProviderIdentity {
        switch provider {
        case .apple:
            return try await signInWithApple()
        case .google:
            return try await signInWithGoogle()
        }
    }

    private func signInWithGoogle() async throws -> ProviderIdentity {
        guard let configuration = GoogleOAuth.Configuration.fromBundle() else {
            throw AuthError.unsupportedProvider
        }
        let authenticator = GoogleWebAuthenticator(configuration: configuration)
        googleAuthenticator = authenticator
        defer { googleAuthenticator = nil }
        return try await authenticator.signIn()
    }

    private func signInWithApple() async throws -> ProviderIdentity {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let request = ASAuthorizationAppleIDProvider().createRequest()
            request.requestedScopes = [.email]
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }
}

extension AppIDTokenProvider: ASAuthorizationControllerDelegate {
    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = credential.identityToken,
              let idToken = String(data: tokenData, encoding: .utf8) else {
            continuation?.resume(throwing: AuthError.invalidResponse)
            continuation = nil
            return
        }
        continuation?.resume(returning: ProviderIdentity(
            provider: .apple,
            idToken: idToken,
            email: credential.email
        ))
        continuation = nil
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}

extension AppIDTokenProvider: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        return scene?.windows.first(where: \.isKeyWindow)
            ?? scene?.windows.first
            ?? ASPresentationAnchor()
    }
}

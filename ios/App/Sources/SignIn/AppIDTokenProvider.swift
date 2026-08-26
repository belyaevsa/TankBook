import AuthenticationServices
import Foundation
import UIKit
import TankbookCore

/// The production identity-token provider: Sign in with Apple via
/// `ASAuthorizationController` (docs/SECURITY.md -> "the server verifies the
/// token, so the client's job is to obtain it and hand it over"). Apple's
/// private-relay address is passed through as the display email.
///
/// Google sign-in requires the Google Sign-In SDK, which is not yet a
/// dependency, so `.google` throws `AuthError.unsupportedProvider` - the flow
/// surfaces it as a next-step message rather than a dead button (hard rule 7).
/// Tests and screenshots inject `SignInTestSeed.StubIDTokenProvider` instead, so
/// this type is never exercised in CI (there is no Apple ID there).
@MainActor
final class AppIDTokenProvider: NSObject, IDTokenProvider {
    private var continuation: CheckedContinuation<ProviderIdentity, Error>?

    func signIn(provider: AuthProvider) async throws -> ProviderIdentity {
        switch provider {
        case .apple:
            return try await signInWithApple()
        case .google:
            throw AuthError.unsupportedProvider
        }
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

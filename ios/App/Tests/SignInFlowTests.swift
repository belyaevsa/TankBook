import Foundation
import os
import TankbookCore
import XCTest
@testable import Tankbook

/// RV.259 - the wrong-provider question loops when both providers are empty.
///
/// A restore-door user whose account is empty is asked "did you sign in with
/// the other provider?". The switch re-runs the flow with no memory of having
/// switched, so when the second account is *also* empty the reverse question is
/// asked, and neither question offers F7's recovery entry point ("import a file
/// you exported yourself" / "Start fresh"). The fix is one flag in the flow:
/// after a switch, an `.empty` outcome resolves to `.emptyRestore`, never to
/// `.wrongProvider` again.
///
/// These tests drive the LIVE path - `startSignIn` / `switchProvider` and the
/// real `performRestore` decision - not a detached copy of it, so they fail
/// when the flow's behaviour changes (the RV.129 discriminator). They live in
/// the app-target bundle because `SignInFlow` is app code over SwiftUI; the
/// package tests cannot see it.
@MainActor
final class SignInFlowTests: XCTestCase {

    /// The DEBUG build ships the placeholder Google client id (project.yml), so
    /// the wrong-provider question is reachable. Without this the "first empty
    /// account asks the question" half would be vacuous.
    private var offersGoogle: Bool { SignInView.offersGoogle }

    private func makeFlow(
        arrivedViaRestore: Bool,
        outcomes: [RestoreOutcome]
    ) -> SignInFlow {
        SignInFlow(
            arrivedViaRestore: arrivedViaRestore,
            idTokenProvider: StubIdentityProvider(),
            authService: StubAuthService(),
            sessionStore: InMemorySessionStore(),
            restoreProvider: ScriptedRestoreProvider(outcomes),
            localHasData: { false },
            firstPush: SignInFirstPush { _ in }
        )
    }

    /// Polls the phase the flow's own tasks move it through. The flow drives
    /// `signIn`/`performRestore` on unstructured tasks, so a fixed sleep would
    /// either be flaky or slow; the deadline is the failure bound, not the wait.
    private func waitForPhase(
        _ flow: SignInFlow,
        _ expected: SignInFlow.Phase,
        timeout: TimeInterval = 5,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if flow.phase == expected { return }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTFail("expected phase \(expected), got \(flow.phase) after \(timeout)s", file: file, line: line)
    }

    // MARK: - The first empty account still asks the question

    func testFirstEmptyAccountViaRestoreAsksTheWrongProviderQuestion() async throws {
        try XCTSkipUnless(offersGoogle, "needs a build that offers Google (the DEBUG placeholder client id)")
        let flow = makeFlow(arrivedViaRestore: true, outcomes: [.empty])

        flow.startSignIn(provider: .apple)

        await waitForPhase(flow, .wrongProvider(.apple))
    }

    // MARK: - The second empty account reaches F7's recovery screen

    /// FAILS TODAY (before the flag): the second `.empty` re-asks the reverse
    /// question, so the phase never becomes `.emptyRestore`.
    func testSecondEmptyAccountAfterSwitchLandsOnEmptyRestore() async throws {
        try XCTSkipUnless(offersGoogle, "needs a build that offers Google (the DEBUG placeholder client id)")
        let flow = makeFlow(arrivedViaRestore: true, outcomes: [.empty, .empty])

        flow.startSignIn(provider: .apple)
        await waitForPhase(flow, .wrongProvider(.apple))

        flow.switchProvider(from: .apple)

        await waitForPhase(flow, .emptyRestore)
        XCTAssertNotEqual(flow.phase, .wrongProvider(.google),
                          "a second empty account must never re-ask the reverse question")
    }

    /// The switch is the only thing the flag records: a sign-out resets it, so
    /// the next restore-door attempt over an empty account asks the question
    /// again (a fresh attempt, not a continuation of the old one).
    func testSignOutClearsTheSwitchMemory() async throws {
        try XCTSkipUnless(offersGoogle, "needs a build that offers Google (the DEBUG placeholder client id)")
        let flow = makeFlow(arrivedViaRestore: true, outcomes: [.empty, .empty, .empty])

        flow.startSignIn(provider: .apple)
        await waitForPhase(flow, .wrongProvider(.apple))
        flow.switchProvider(from: .apple)
        await waitForPhase(flow, .emptyRestore)

        flow.signOutLocally()
        flow.startSignIn(provider: .apple)

        await waitForPhase(flow, .wrongProvider(.apple))
    }

    // MARK: - The sibling: `.unreachable` after a switch

    /// An unreachable account says nothing about *which* account holds the
    /// data, so the wrong-provider question does not apply; the backend-down
    /// screen already carries the import door, a retry and a sign-out. The flag
    /// must not divert it. Pinned so a later "fix" cannot change it silently.
    func testUnreachableAfterSwitchStillShowsTheBackendDownScreen() async throws {
        try XCTSkipUnless(offersGoogle, "needs a build that offers Google (the DEBUG placeholder client id)")
        let flow = makeFlow(arrivedViaRestore: true, outcomes: [.empty, .unreachable])

        flow.startSignIn(provider: .apple)
        await waitForPhase(flow, .wrongProvider(.apple))

        flow.switchProvider(from: .apple)

        await waitForPhase(flow, .restoreUnreachable)
        XCTAssertNotEqual(flow.phase, .wrongProvider(.google))
    }
}

// MARK: - Doubles

/// Returns the scripted outcomes in order, so one flow can be walked through
/// the switch and the second attempt.
private actor ScriptedRestoreProvider: RestoreProviding {
    private var outcomes: [RestoreOutcome]

    init(_ outcomes: [RestoreOutcome]) {
        self.outcomes = outcomes
    }

    func restore(accountId: String) async -> RestoreOutcome {
        guard !outcomes.isEmpty else { return .empty }
        return outcomes.removeFirst()
    }
}

private struct StubIdentityProvider: IDTokenProvider {
    func signIn(provider: AuthProvider) async throws -> ProviderIdentity {
        ProviderIdentity(provider: provider, idToken: "stub-id-token", email: "driver@example.com")
    }
}

private struct StubAuthService: AuthService {
    func signIn(identity: ProviderIdentity) async throws -> AuthSession {
        AuthSession(
            accessToken: "stub-access-token",
            refreshToken: "stub-refresh-token",
            accountId: UUID().uuidString,
            deviceId: UUID().uuidString,
            provider: identity.provider,
            email: identity.email
        )
    }

    func refresh(_ session: AuthSession) async throws -> AuthSession { session }

    func signOut(_ session: AuthSession) async throws {}
}

/// The Keychain double for the flow's session seam. Not the core tests'
/// `InMemorySessionStore` - that type lives in the package test target, which
/// the app-target bundle cannot import.
private final class InMemorySessionStore: SessionStore, @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock<AuthSession?>(initialState: nil)

    func load() throws -> AuthSession? { lock.withLock { $0 } }
    func save(_ session: AuthSession) throws { lock.withLock { $0 = session } }
    func clear() throws { lock.withLock { $0 = nil } }
    func setAuthExpired(_ expired: Bool) throws {}
    func isAuthExpired() throws -> Bool { false }
    func setDeviceRevoked(_ revoked: Bool) throws {}
    func isDeviceRevoked() throws -> Bool { false }
}

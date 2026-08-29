import Foundation
import TankbookCore

/// Decides whether the Welcome root shows at launch (docs/SCREENMAP.md ->
/// Welcome): **no vehicle AND no session**. A car existing anywhere in the
/// log - or a session in the Keychain - means the user is not a fresh install,
/// so Welcome is gone for good (it never reappears once a car exists).
///
/// The decision runs at app-root init, before the first frame, so the tabs
/// never flash behind the onboarding screen. Test-harness escapes, each honest
/// about what it is:
/// - `-skipWelcome`: force the tabbed app even with no vehicle/session.
/// - A `-presentScreen`/`-openManualForm` debug-launch request targets a
///   screen in the tabbed app, so the tabs must exist to host it.
/// - `-homeResetDatabase` is the seed harness's clean-slate flag; the tests
///   using it target the tabbed app, not onboarding.
/// - `-presentWelcome` overrides those three: run the real onboarding decision
///   even under the harness flags (the Welcome UI tests and screenshots use it
///   to reach the fresh-install state deterministically). It forces no outcome
///   on its own - a vehicle or session still suppresses Welcome.
enum WelcomeGate {
    /// `@MainActor` because it consults `AppStore` (the app's MainActor-owned
    /// repository seam) - it runs from the app root init, which is MainActor.
    @MainActor
    static func shouldShowWelcome(
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> Bool {
        if arguments.contains("-skipWelcome") { return false }
        #if DEBUG
        let request = DebugLaunch.resolve(arguments)
        if request.sheet != nil || request.route != nil || request.modal != nil {
            return false
        }
        #endif
        if !arguments.contains("-presentWelcome"),
           arguments.contains("-homeResetDatabase") {
            return false
        }

        // A `-homeResetDatabase` launch wipes the database through the seeding
        // hooks (AppStore.resetForTestsOncePerLaunch). The gate must read the
        // POST-reset state - a previous test's vehicle would otherwise suppress
        // Welcome - so it runs the idempotent wipe itself first. Idempotent:
        // the seeds' own calls then no-op, exactly as they do today.
        if arguments.contains("-homeResetDatabase") {
            AppStore.resetForTestsOncePerLaunch()
        }
        // `-presentWelcome` declares "this launch IS a fresh install": the
        // Keychain outlives `-homeResetDatabase` (which wipes only the SQLite
        // file), so a leftover session from a prior run would otherwise
        // suppress Welcome and make the tests order-dependent. Clearing it
        // here makes the onboarding decision deterministic. The vehicle check
        // below still wins - a car in the log suppresses Welcome even under
        // `-presentWelcome`, which is the "never reappears" guarantee.
        if arguments.contains("-presentWelcome") {
            try? KeychainSessionStore().clear()
        }

        let repository = try? AppStore.repository()
        let hasVehicle = (try? repository?.liveVehicles().isEmpty) == false
        let hasSession = (try? KeychainSessionStore().load()) != nil
        return !hasVehicle && !hasSession
    }
}

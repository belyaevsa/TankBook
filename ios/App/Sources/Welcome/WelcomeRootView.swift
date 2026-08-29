import SwiftUI
import TankbookCore

/// The Welcome root's host (docs/SCREENMAP.md): owns the three paths' landing
/// screens - AddVehicle and ImportWizard pushed on its own stack, the sign-in
/// sheet carrying the restore intent (`arrivedViaRestore: true`). The host
/// re-evaluates on every appear and on any pop, so the moment a car exists or
/// a session lands, onboarding is over and the tabs take over - and the
/// Restoring screen's *Cancel = sign out* returns here (SCREENMAP.md:118)
/// instead of landing the user in a dead end.
struct WelcomeRootView: View {
    /// Called when a car exists or a session was created: the tabs replace
    /// Welcome for good.
    var onFinished: () -> Void

    @Environment(AppSync.self) private var sync
    @State private var path: [Route] = []
    @State private var sheet: SheetRoute?
    @State private var modal: ModalRoute?
    @State private var signInPresented = false
    @State private var didPresentDebugLaunch = false

    var body: some View {
        RootedNavigationStack(path: $path) {
            WelcomeView(
                onAddCar: { path = [.addVehicle] },
                onImport: { path = [.importWizard] },
                onSignIn: { signInPresented = true })
        }
        .sheet(item: $sheet) { route in
            SheetDestinationView(route: route) { target in
                sheet = nil
                path = [target]
            }
        }
        .sheet(isPresented: $signInPresented) {
            // The third path IS the restore intent: an empty account under it
            // asks the honest J11a wrong-provider question (docs/JOURNEYS.md
            // J11a) instead of offering a fresh start.
            SignInFlowHost(arrivedViaRestore: true)
        }
        .fullScreenCover(item: $modal) {
            ModalDestinationView(route: $0)
        }
        .onAppear(perform: presentDebugLaunchIfNeeded)
        .task { reevaluate() }
        .onChange(of: path) { _, _ in reevaluate() }
    }

    /// A car was added (AddVehicle saved), an import committed, or the sign-in
    /// flow finished: onboarding is over. `onFinished` swaps Welcome for the
    /// tabs; the change is driven by real data, never by a flag.
    private func reevaluate() {
        let repository = try? AppStore.repository()
        let hasVehicle = (try? repository?.liveVehicles().isEmpty) == false
        let hasSession = (try? sync.sessionStore.load()) != nil
        if hasVehicle || hasSession {
            onFinished()
        }
    }

    /// `-presentScreen <route>` / `-openManualForm`: DEBUG-only launch hook
    /// (DebugLaunch) so `simctl`-driven screenshots can reach sheet and pushed
    /// screens over Welcome without a UI test tap. The sign-in sheet opened
    /// here carries the restore intent - it is the third path, not Settings'
    /// ordinary sign-in.
    private func presentDebugLaunchIfNeeded() {
        #if DEBUG
        guard !didPresentDebugLaunch else { return }
        didPresentDebugLaunch = true
        let request = DebugLaunch.resolve()
        if request.sheet == .signIn {
            signInPresented = true
        } else if let sheet = request.sheet {
            self.sheet = sheet
        } else if let route = request.route {
            path = [route]
        } else if let modal = request.modal {
            self.modal = modal
        }
        #endif
    }
}

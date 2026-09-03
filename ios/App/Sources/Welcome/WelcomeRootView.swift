import SwiftUI
import TankbookCore

/// The Welcome root's host (docs/SCREENMAP.md): owns the doors' landing
/// screens - AddVehicle and ImportWizard pushed on its own stack, and the
/// sign-in sheet, opened by either of the two sign-in doors.
///
/// RV.23: the restore intent is no longer a constant. It is carried by WHICH
/// door opened the sheet - the returning user's "Already use Tankbook? Restore
/// your garage." line passes `arrivedViaRestore: true`, the peer "Sign in to
/// Tankbook" button passes `false`. That distinction is the J11a guarantee in
/// both directions (docs/JOURNEYS.md J11a): a returning user over an empty
/// account still gets the honest wrong-provider question instead of an empty
/// garage that looks like data loss, and a brand-new user - whose account is
/// empty because it is new - is never asked about a sign-in they never made.
/// The host
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
    @State private var signInRequest: SignInRequest?
    @State private var didPresentDebugLaunch = false

    var body: some View {
        RootedNavigationStack(path: $path) {
            WelcomeView(
                onAddCar: { path = [.addVehicle] },
                onImport: { path = [.importWizard] },
                onSignIn: { signInRequest = .signIn },
                onRestore: { signInRequest = .restore })
        }
        .sheet(item: $sheet) { route in
            SheetDestinationView(route: route) { target in
                sheet = nil
                path = [target]
            }
        }
        .sheet(item: $signInRequest) { request in
            // The door decides: only the restore door claims "I already use
            // Tankbook", so only it can reach the J11a wrong-provider question
            // (docs/JOURNEYS.md J11a). The peer sign-in door is an ordinary
            // first sign-in and an empty account under it is simply empty.
            SignInFlowHost(arrivedViaRestore: request.arrivedViaRestore)
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
    /// here carries the restore intent - it is the restore door, not Settings'
    /// ordinary sign-in.
    private func presentDebugLaunchIfNeeded() {
        #if DEBUG
        guard !didPresentDebugLaunch else { return }
        didPresentDebugLaunch = true
        let request = DebugLaunch.resolve()
        if request.sheet == .signIn {
            signInRequest = .restore
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

/// Which of Welcome's two sign-in doors opened the sheet (RV.23). `Identifiable`
/// so the presentation itself carries the intent: a `Bool` in a separate `@State`
/// can be read before it is written on the first frame of the sheet.
private enum SignInRequest: String, Identifiable {
    /// The peer "Sign in to Tankbook" button - no claim of being a returning user.
    case signIn
    /// "Already use Tankbook? Restore your garage." - the J11a restore intent.
    case restore

    var id: String { rawValue }

    var arrivedViaRestore: Bool { self == .restore }
}

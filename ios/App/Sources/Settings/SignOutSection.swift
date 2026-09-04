import SwiftUI
import TankbookCore

/// The Sign out control on the Settings account surface (RV.40, docs/SYNC.md ->
/// "Sign out"). The mildest account exit: the account card pushes to Account &
/// devices where the two destructive operations (revoke, delete account) live,
/// so the ordinary "stop syncing this phone" has its own row here. Signing out
/// is NOT deleting (hard rule 8) - the confirmation names any unsynced changes
/// and that they are kept, and the local log is never touched.
struct SignOutSection: View {
    @Environment(AppSync.self) private var sync
    @State private var showsConfirm = false

    var body: some View {
        Button {
            showsConfirm = true
        } label: {
            HStack {
                Text("Sign out")
                    .font(.subheadline)
                    .foregroundStyle(Theme.Palette.ink)
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
            .formCard()
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("settingsSignOutButton")
        .alert("Sign out?", isPresented: $showsConfirm) {
            Button("Sign out") {
                Task { await sync.signOut() }
            }
            .accessibilityIdentifier("settingsSignOutConfirmButton")
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(L10n.signOutConfirmation(dirtyCount: sync.dirtyCount))
                .accessibilityIdentifier("settingsSignOutConfirmationMessage")
        }
    }
}

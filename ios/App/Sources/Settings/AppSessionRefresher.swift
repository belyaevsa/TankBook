import Foundation
import TankbookCore

/// The app's ONE shared token refresher (PR.1). Every authenticated transport -
/// sync, blobs, account, import, the gateway, the restore pull - must hand the
/// SAME actor instance to its `TankbookHTTPClient`, so a 401 storm collapses to
/// one in-flight refresh: the server rotates refresh tokens and revokes the
/// chain on reuse, so two racing refreshes sign the user out.
///
/// A process-wide `static let` is the honest shape here: the session store
/// (Keychain), the base URL and the transport selection are process-global, and
/// the alternative - threading one actor through every static factory that
/// builds a transport - would need a new parameter on half the app and would
/// still have to agree on a single owner. Evaluated once, on first use.
enum AppSessionRefresher {
    static let shared: SessionRefresher = {
        return SessionRefresher(
            baseURLProvider: { AppConfigStore.shared.director.baseURL() },
            transport: makeAppTransport(),
            sessionStore: KeychainSessionStore())
    }()
}

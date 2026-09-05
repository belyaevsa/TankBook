import Foundation
import Observation
import TankbookCore

/// The Account & devices screen's state (P6.4, docs/API.md -> "Account &
/// devices"). Owns the three mutations the screen exists for - load the device
/// list, revoke one device, delete the account - over an injected
/// `AccountClient`, with the session read from the Keychain (never invented).
///
/// The screen's two guarantees are enforced here and in the view's copy:
///
/// - **Revoke stops syncing, it erases nothing.** The revoked device's next
///   pull gets 410 (docs/API.md); its local data stays on it. A revoke must
///   never read as data loss.
/// - **Delete account is a tombstone.** The server purges its copy after the
///   grace period; every device's pull gets 410; **the log on this phone is
///   untouched** (docs/SYNC.md, site/delete-account.md). The screen never
///   implies local data is deleted, because it is not - and a user who believes
///   it is will not trust the export that still works.
///
/// `@Observable` + `@MainActor` so the view re-renders on each mutation; the
/// network stays injectable for the UI tests' stub transport.
@MainActor
@Observable
final class AccountDevicesModel {
    /// The list's state. `.failed` carries a localised message and a next step
    /// (hard rule 7), each already resolved.
    enum ListPhase: Equatable {
        case idle
        case loading
        case loaded
        case failed(message: String)
    }

    private let client: AccountClient
    private let sessionStore: any SessionStore

    private(set) var devices: [AccountDevice] = []
    private(set) var phase: ListPhase = .idle
    /// The session's device id, so the screen can mark "This device" - read
    /// from the session, never guessed.
    private(set) var currentDeviceID: UUID?
    /// The session itself, for the identity header (email, provider).
    private(set) var currentSession: AuthSession?
    /// The device whose revoke is in flight (spinner on that row).
    private(set) var inFlightRevoke: UUID?
    /// A failed revoke's next step, shown on the device row (hard rule 7).
    private(set) var revokeErrorFor: UUID?
    private(set) var isDeletingAccount = false
    /// A failed account deletion's next step.
    private(set) var deleteError: String?

    /// Whether the request host is refused / the session invalid: local data is
    /// untouched in every case (hard rule 1) - the screen only loses the list.
    init(client: AccountClient, sessionStore: any SessionStore) {
        self.client = client
        self.sessionStore = sessionStore
        currentSession = try? sessionStore.load()
        if let deviceIDString = currentSession?.deviceId {
            currentDeviceID = UUID(uuidString: deviceIDString)
        }
    }

    var isCurrentDevice: (AccountDevice) -> Bool {
        { device in device.id == self.currentDeviceID }
    }

    /// Loads the device list. Called on appear and after every mutation that
    /// changes membership (a revoke's effect shows as `revoked: true` from the
    /// server, never guessed client-side).
    func load() async {
        phase = .loading
        do {
            devices = try await client.devices()
            phase = .loaded
        } catch AccountClientError.cancelled {
            // RV.68: a `.task` cancelled by a view update is not a failure -
            // the screen must not claim the connection is the problem. Revert
            // to idle so a re-fired `.task` reloads cleanly.
            phase = .idle
        } catch {
            phase = .failed(message: Self.message(for: error, fallback: Self.loadFailedMessage))
        }
    }

    /// Revokes one device (`DELETE /account/devices/{id}`). The device's next
    /// pull gets 410; its local data stays on it. The server's response is the
    /// truth: on success the row reloads from the next `load()`, on 404 the
    /// device is treated as already gone. Returns whether the revoke reached
    /// the server (a reload that then fails does not undo a successful revoke),
    /// so the caller can invalidate anything that depends on the old list.
    @discardableResult
    func revoke(_ device: AccountDevice) async -> Bool {
        guard inFlightRevoke == nil else { return false }
        inFlightRevoke = device.id
        revokeErrorFor = nil
        defer { inFlightRevoke = nil }
        do {
            try await client.revoke(deviceID: device.id)
            await load()
            return true
        } catch AccountClientError.cancelled {
            return false
        } catch {
            revokeErrorFor = device.id
            return false
        }
    }

    /// Deletes the account (`DELETE /account` - a tombstone). On success the
    /// local session is cleared (the server has signed every device out) and
    /// the caller dismisses back to Settings, where the user is a guest again.
    /// Local data is untouched - nothing here touches the repository.
    func deleteAccount() async -> Bool {
        guard !isDeletingAccount else { return false }
        isDeletingAccount = true
        deleteError = nil
        defer { isDeletingAccount = false }
        do {
            try await client.deleteAccount()
            try? sessionStore.clear()
            return true
        } catch AccountClientError.cancelled {
            return false
        } catch {
            deleteError = Self.message(for: error, fallback: Self.deleteFailedMessage)
            return false
        }
    }

    /// The screen's "Try again" for a failed load: reloads the list.
    func retry() async {
        await load()
    }

    /// The honest localised message for a failure, with its next step folded in
    /// (hard rule 7). Transport errors never accuse the user (offline is not an
    /// error, F3/S7); a 401 means the session is gone and the next step is
    /// signing in again.
    private static func message(for error: Error, fallback: String) -> String {
        switch error {
        case AccountClientError.transportUnreachable, AccountClientError.client:
            return L10n.localize("Couldn't reach Tankbook – check your connection and try again.")
        case AccountClientError.transportFailure:
            // RV.68: the device's network was fine - never "check your
            // connection". Same copy as the server row: it is on the far side,
            // not the user's side.
            return L10n.localize("Something went wrong on our side – try again in a moment.")
        case AccountClientError.unauthorized:
            return L10n.localize("Your session has expired – sign in again. Your data on this phone is untouched.")
        case AccountClientError.notFound:
            return L10n.localize("This device or account is already gone – reload.")
        case AccountClientError.server:
            return L10n.localize("Something went wrong on our side – try again in a moment.")
        default:
            return fallback
        }
    }

    private static let loadFailedMessage =
        L10n.localize("Couldn't load devices – check your connection and try again.")
    private static let deleteFailedMessage =
        L10n.localize("Couldn't delete the account – try again.")
}

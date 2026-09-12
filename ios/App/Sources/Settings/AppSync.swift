import Foundation
import Observation
import TankbookCore
import UIKit

/// Supplies the current access token to the sync transport, read from the
/// Keychain exactly as the auth service does (docs/SECURITY.md -> the token is
/// bound to the host, not the session). The host allowlist is enforced by
/// `TankbookHTTPClient` before this is consulted. Internal (not private) so the
/// sign-in restore provider (P4.7) reuses the same token path.
struct KeychainTokenProvider: AuthorizationTokenProvider {
    let sessionStore: any SessionStore

    func token() -> String? {
        try? sessionStore.load()?.accessToken
    }
}

/// The app's single sync surface (docs/SYNC.md -> "The Settings sync surface").
/// Owns the one `SyncCoordinator` and derives the Settings status from it plus
/// the repository's recomputed counts. Signed-in vs guest is read from the
/// session store, never invented (the Keychain is the source of truth).
///
/// `@Observable` + `@MainActor` so the Settings view re-renders when the state
/// changes; the heavy idempotency gate lives in the core `SyncCoordinator`.
@MainActor
@Observable
final class AppSync {
    let sessionStore: any SessionStore
    /// The config service the sync gate reads (P6.18b): under `.required` a
    /// push is withheld client-side - the server has stopped supporting this
    /// build, the same set 426 already withholds (docs/CONFIG.md). Everything
    /// local is untouched; a paused push leaves the queue exactly as S7 does.
    private let configService: AppConfigService
    private var core: SyncCoordinator?
    /// RV.249: the account `core` was built for. The coordinator holds an
    /// account-keyed cursor store, so an account change must discard it rather
    /// than reuse a cursor that belongs to the previous account.
    private var coreAccountId: String?

    /// The injected Low Power Mode state (P6.8, docs/SYNC.md -> Low Power
    /// Mode). Never `ProcessInfo` read at a call site - the app's one seam is
    /// `AppPower`, and the deferral decision is the injected boolean's alone.
    private let powerState: any PowerStateProvider
    /// Drains the work a background cycle deferred, the moment the mode ends -
    /// resume on the state change, not at next launch. The same resumer the
    /// rate refresh registers its deferred fetch on.
    private let resumer: LowPowerResumer
    private var powerChangeObserver: NSObjectProtocol?
    /// One stable id for the deferred-sync work, so a second deferral replaces
    /// the first registration instead of stacking a duplicate drain.
    private static let deferredSyncID = UUID()

    /// RV.157: the debounced write trigger (docs/SYNC.md - a cycle runs "after
    /// every local write (debounced)"). Poked by the database write signal; run
    /// through `runSync(.background)`, the SAME door as the foreground pass.
    /// Built lazily; a guest's pokes are no-ops.
    private var writeTrigger: SyncWriteScheduler?
    /// The `DatabaseWriteSignal` under observation, so re-arming (e.g. after a
    /// test reset rebuilt the database) replaces rather than stacks the observer.
    private var armedWriteSignal: DatabaseWriteSignal?

    private(set) var session: AuthSession?
    private(set) var dirtyCount = 0
    private(set) var flaggedCount = 0
    private(set) var lastSyncDate: Date?
    private(set) var lastOutcome: SyncOutcome?
    /// OB.3: the last failure, restored from the device store so Settings can
    /// render it on a relaunch before any cycle has run. nil when nothing has
    /// ever failed, or once a successful cycle cleared it. The raw `code` and
    /// `traceId` inside are persisted and exported (OB.4), never shown to the
    /// user.
    private(set) var lastFailure: SyncFailureRecord?
    private(set) var isSyncing = false
    /// RV.26: whether the session store carries the persisted `authExpired` mark
    /// (a rejected refresh). Read in `refresh` and OR-ed into the surface state,
    /// so an expiry the cloud gateway detected - not only one a sync cycle
    /// detected - surfaces as "session expired - sign in again" in Settings and
    /// on RV.22's chip. Distinct from `lastOutcome.authExpired`, which is the
    /// in-memory outcome of the last sync cycle.
    private(set) var storedAuthExpired = false
    /// RV.58: whether the session store carries the persisted `deviceRevoked`
    /// mark (a 410, docs/SECURITY.md: a revoked device discards its tokens and
    /// stops syncing). The revoked session is dropped the moment a cycle answers
    /// 410; this mark is what keeps the surface reading "this device was signed
    /// out - sign in to reconnect" (never a plain guest) across relaunches,
    /// until the user signs in again and the device row re-attaches.
    private(set) var storedDeviceRevoked = false
    /// PR.14: the number of entries the last sync batch flagged (docs/SYNC.md
    /// -> the post-batch toast "Synced. N entries need a look"). Nil while no
    /// batch has flagged anything; the Home toast reads it and clears it when
    /// the user taps through. Derived from the outcome, never a stored counter.
    private(set) var lastBatchFlaggedEntries: Int?

    /// PJ.13 (docs/JOURNEYS.md J11a -> First push): whether the user just
    /// signed in and the first push ran, so the account card shows the one-line
    /// "Your garage now follows your account" confirmation. Set by the sign-in
    /// flow's first push, cleared on sign-out or relaunch; in-memory only.
    private var didJustSignIn = false
    /// The Settings card's device count (`GET /account/devices`,
    /// docs/JOURNEYS.md J11a) behind a `DeviceCountCache` (RV.6); LIVE devices
    /// only, revoked rows stay in the list but do not count (RV.54).
    private var deviceCountCache = DeviceCountCache()
    /// RV.18: when the last opportunistic (launch/foreground) cycle started, so
    /// a burst of `.active` transitions is one cycle, not one each. Only the
    /// launch/foreground door reads it - the Settings "Sync now" tap, the retry
    /// backoff and the Low Power drain never consult it, so a forced cycle is
    /// always available.
    private var lastOpportunisticSyncAt: Date?

    /// DEBUG/test fixtures for states a real transport never produces in a
    /// screenshot (410 device revoked, blob-quota 429, offline with a queue).
    /// Nil/absent = not forced; production never sets them.
    var forcedRevoked = false
    var forcedQuotaPercent: Int?
    /// PJ.13 fixtures for the just-signed-in card (the J11a screenshot): a
    /// device count and the confirmation line, which a frozen sync cannot
    /// produce (the sync is frozen, so no push and no device fetch runs).
    /// Absent = not forced; production never sets them.
    var forcedDeviceCount: Int?
    var forcedJustSignedIn = false
    /// PR.13 fixtures for the two transport-failure states: offline (a passive
    /// "back online" row) and server-down (a 5xx, the "service unreachable"
    /// card with Try again). A frozen screenshot cannot run a real cycle, so
    /// these force the outcome a real transport would produce. Absent = not
    /// forced; production never sets them.
    var forcedOffline = false
    var forcedServerUnavailable = false
    /// P6.11 fixtures for a server that has moved ahead of this client (426,
    /// 402, unknown 4xx, 429): outcomes this app version can never provoke from
    /// a real server, so the only way to render them is to force them. Nil/
    /// absent = not forced; production never sets them.
    var forcedUpgradeRequired = false
    var forcedRefused: SyncServerError?
    var forcedRetryAfterSeconds: Int?
    /// RV.22 fixtures for the sync chip's presentation: force the chip state
    /// (and its label counts) directly so a screenshot or UI test can show each
    /// of the five states without reproducing the transport outcome that
    /// produces it. The mapping itself is L1-tested (`SyncChipTests`); these
    /// only let the L4 layer and screenshots drive the presentation. Nil/absent
    /// = derive from the real surface; production never sets them.
    var forcedChipState: SyncChipState?
    var forcedChipDirtyCount: Int?
    var forcedChipFlaggedCount: Int?

    init(sessionStore: any SessionStore = KeychainSessionStore(),
         configService: AppConfigService,
         powerState: any PowerStateProvider = ProcessInfoPowerState(),
         resumer: LowPowerResumer? = nil) {
        self.sessionStore = sessionStore
        self.configService = configService
        self.powerState = powerState
        let resumer = resumer ?? LowPowerResumer(powerState: powerState)
        self.resumer = resumer
        Task { await resumer.start() }
        // The surface must re-render the instant the mode changes: when Low
        // Power turns on the row gains the reason, when it ends the reason
        // vanishes (and the resumer drains what was deferred). The resumer and
        // this observer listen to the same change - one drains, one re-draws.
        powerChangeObserver = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.refresh() }
        }
    }

    var signedIn: Bool { session != nil }

    /// Whether the account card should show the J11a confirmation line
    /// ("Your garage now follows your account"). The real flag comes from the
    /// sign-in flow's first push; the fixture lets a frozen-sync screenshot
    /// render the just-signed-in card.
    var justSignedIn: Bool { didJustSignIn || forcedJustSignedIn }

    /// The live device count for the account card's "· N device(s)" suffix, or
    /// nil while unknown; the fixture lets a frozen-sync screenshot render it.
    var deviceCount: Int? { forcedDeviceCount ?? deviceCountCache.count }

    /// RV.6: an event changed the account's devices (a revoke, account delete,
    /// sign-out, sign-in) - the next refresh re-reads the count.
    func invalidateDeviceCount() {
        deviceCountCache.invalidate()
    }

    var surfaceState: SyncSurfaceState {
        SyncSurfaceState(
            isSignedIn: signedIn,
            lastSyncDate: lastSyncDate,
            dirtyCount: dirtyCount,
            offline: forcedOffline || (lastOutcome?.offline ?? false),
            serverUnavailable: forcedServerUnavailable || (lastOutcome?.serverUnavailable ?? false),
            deviceRevoked: forcedRevoked || storedDeviceRevoked
                || (lastOutcome?.deviceRevoked ?? false),
            authExpired: storedAuthExpired || (lastOutcome?.authExpired ?? false),
            // RV.253: last cycle's blob-429 percent, or the screenshot fixture.
            quotaUsedPercent: SyncSurface.quotaUsedPercent(forced: forcedQuotaPercent, outcome: lastOutcome),
            flaggedCount: flaggedCount,
            isSyncing: isSyncing,
            // P6.8: the reason is on whenever the mode is; the S7 row names it
            // only when a queue is actually waiting (SyncSurface.lowPowerReason).
            lowPowerModeDeferring: powerState.isLowPowerModeEnabled
        )
    }

    var status: SyncStatus { SyncSurface.status(surfaceState) }

    /// RV.22: which Settings card the sync chip's Settings tap should scroll to.
    /// The chip sets this just before it pushes Settings; `SettingsView` scrolls
    /// to the named card and clears it. Nil for the gear and for states 3-5, so
    /// only a chip tap on an attention state (the only states with a named fix)
    /// scrolls. Transient UI intent, not sync state - never persisted, never
    /// logged.
    var settingsScrollTarget: SettingsScrollTarget?

    /// Whether the last cycle ended with an expired session whose refresh was
    /// rejected (PR.1), or the persisted mark says the session is expired
    /// (RV.26 - the cloud gateway sets the same mark on its own 401). The
    /// account card shows the re-sign-in card for this, never "update the app".
    var authExpired: Bool { storedAuthExpired || (lastOutcome?.authExpired ?? false) }

    /// RV.58: whether this device was revoked server-side (a 410). The persisted
    /// mark (`storedDeviceRevoked`) is what outlives the dropped session and a
    /// relaunch; the in-memory outcome covers the moments before the mark is
    /// written; `forcedRevoked` is the screenshot/test fixture. The account card
    /// renders the "device signed out - sign in to reconnect" card for this,
    /// never a plain guest and never "update the app".
    var deviceRevoked: Bool {
        forcedRevoked || storedDeviceRevoked || (lastOutcome?.deviceRevoked ?? false)
    }

    /// The server-ahead notice the Settings account card surfaces: the forced
    /// fixture when a seed set one, else the coordinator's last outcome. It is
    /// the one place `SyncOutcome.upgradeRequired` / `refusedByServer` /
    /// `retryAfterSeconds` become visible - the P6.11 defect was that nothing
    /// read them.
    var serverNotice: SyncServerNotice {
        if forcedUpgradeRequired { return .upgradeRequired }
        if let forcedRefused {
            switch forcedRefused {
            case .tierRefused:
                return .tierRefused
            case .rateLimited(let retryAfter):
                return .rateLimited(retryAfterSeconds: forcedRetryAfterSeconds ?? retryAfter)
            case .refused(let status):
                return .refused(status: status)
            default:
                break
            }
        }
        guard let outcome = lastOutcome else { return .none }
        return SyncServerNotice.classify(outcome)
    }

    private func coordinator() -> SyncCoordinator? {
        // RV.249: the coordinator owns an account-keyed cursor store, so it is
        // only valid for the account it was built for. Resolve the current
        // account here and rebuild when it changed - sign-out clears the
        // session but keeps the old coordinator, and the next sign-in may be a
        // different account that must start from its own cursor (0 when new).
        let accountId = (try? sessionStore.load())?.accountId
        if let core, let accountId, coreAccountId == accountId { return core }
        core = nil
        coreAccountId = nil
        guard let accountId, let repository = try? AppStore.repository() else { return nil }
        let coordinator = SyncService.makeCoordinator(repository: repository,
                                                      sessionStore: sessionStore,
                                                      accountId: accountId,
                                                      powerState: powerState)
        core = coordinator
        coreAccountId = accountId
        ensureWriteTriggerArmed(repository: repository)
        return coordinator
    }

    /// RV.157: arms the database write signal - the seam every local write
    /// passes through. The trigger's gates decide whether a cycle runs; a poke
    /// that dirtied nothing is a no-op. Re-arms when a test reset rebuilt the
    /// database; never armed under a seeded launch (UI test / screenshot).
    private func ensureWriteTriggerArmed(repository: TankbookRepository) {
        #if DEBUG
        guard !SeededLaunch.isSeeded() else { return }
        #endif
        let writeSignal = repository.database.writeSignal
        if writeSignal === armedWriteSignal { return }
        writeSignal.observer = { [weak self] in
            Task { @MainActor in self?.noteLocalWrite() }
        }
        armedWriteSignal = writeSignal
    }

    /// A local write landed (RV.157). Cheap and non-blocking - the write already
    /// committed; this only nudges the debounced trigger. A guest's poke is a
    /// no-op; a frozen screenshot launch skips it like the launch cycle. Loads
    /// `session` on demand so a relaunch's first edit is not lost.
    private func noteLocalWrite() {
        #if DEBUG
        guard !SeededLaunch.freezesSyncState() else { return }
        #endif
        if session == nil { session = try? sessionStore.load() }
        guard signedIn else { return }
        let trigger = writeTrigger ?? makeWriteTrigger()
        writeTrigger = trigger
        trigger.noteWrite()
    }

    /// Builds the app's one write trigger; gates read live state at fire time.
    /// Shares AppSync's deferred-work id so write + foreground deferrals in one
    /// Low Power session coalesce into one drain.
    private func makeWriteTrigger() -> SyncWriteScheduler {
        let trigger = SyncWriteScheduler(powerState: powerState, resumer: resumer,
                                         deferredWorkID: Self.deferredSyncID)
        trigger.isArmed = { [weak self] in
            self?.session != nil && (self?.configService.allowsServerBacked ?? false)
        }
        trigger.isBusy = { [weak self] in self?.isSyncing ?? false }
        trigger.hasWork = { [weak self] in
            guard let repository = try? AppStore.repository() else { return false }
            return ((try? repository.fetchDirtyRows())?.isEmpty == false)
        }
        trigger.isRetryPending = { [weak self] in
            self?.core?.scheduledRetryDelay() != nil
        }
        trigger.run = { [weak self] in await self?.runWriteTriggeredCycle() }
        return trigger
    }

    /// The write trigger's cycle uses the SAME door as the foreground pass
    /// (`runSync(.background)`) - never a second path.
    private func runWriteTriggeredCycle() async {
        await runSync(trigger: .background)
    }

    /// Reads the session, the derived counts and the coordinator's last outcome.
    /// Cheap and pure - called on appear and after every sync.
    func refresh() async {
        session = try? sessionStore.load()
        storedAuthExpired = (try? sessionStore.isAuthExpired()) ?? false
        storedDeviceRevoked = (try? sessionStore.isDeviceRevoked()) ?? false
        if session == nil {
            // The account is gone; the just-signed-in confirmation must not
            // outlive the session it confirmed.
            didJustSignIn = false
        }
        // RV.249: a different account signed in - the cached coordinator (and
        // its account-keyed cursor) belongs to the old one. Drop it here so the
        // card does not read the old account's outcome and the rebuild below
        // keys the cursor to the new account.
        if let session, let coreAccountId, coreAccountId != session.accountId {
            core = nil
            self.coreAccountId = nil
        }
        if session != nil, core == nil {
            // OB.3: a signed-in relaunch must see its persisted sync state (the
            // last success date and last failure) even before any cycle runs -
            // the coordinator restores it from the store when created here. A
            // guest has no sync surface, so no coordinator is built.
            _ = coordinator()
        }
        if let core {
            lastSyncDate = core.lastSyncDate()
            lastOutcome = core.lastOutcome()
            lastFailure = core.lastFailure()
        } else {
            lastFailure = nil
        }
        // The "· N device(s)" suffix (docs/JOURNEYS.md J11a), decided by the
        // `DeviceCountCache` (RV.6): reuse/fetch/clear as it decides. RV.54:
        // the count is LIVE only (`liveDeviceCount`) - revoked rows stay in
        // the list, the counting excludes them.
        if case .fetch = deviceCountCache.refreshAction(signedIn: session != nil),
           let devices = try? await accountDevicesClient().devices() {
            deviceCountCache.record(devices.liveDeviceCount)
        }
        do {
            let repository = try AppStore.repository()
            ensureWriteTriggerArmed(repository: repository)
            let dirty = (try? repository.fetchDirtyRows()) ?? []
            dirtyCount = dirty.count
            flaggedCount = (try? repository.flaggedEntryCount()) ?? 0
            // OB.2: the sync.queue line - the number behind Settings' "Waiting
            // to sync" count and how long the oldest has waited. Counts and an
            // age only; never which records (docs/LOGGING.md §4).
            if session != nil {
                let oldest = dirty.map(\.updatedAt).min()
                let oldestAge = oldest.map { Int(Date().timeIntervalSince($0)) } ?? 0
                AppLog.shared.emit(SyncQueue(dirtyCount: dirtyCount,
                                             oldestDirtyAgeSeconds: oldestAge))
            }
        } catch {
            dirtyCount = 0
            flaggedCount = 0
        }
    }

    /// PJ.13 (docs/JOURNEYS.md J11a -> First push): the user-initiated cycle
    /// the sign-in flow runs before finishing. Marks the account as just
    /// signed in, then runs the ONE coordinator with a `.userInitiated`
    /// trigger - never `.background`, which LowPowerPolicy defers while Low
    /// Power Mode is on.
    ///
    /// Deliberately does NOT update this surface's state. The Settings card
    /// must learn about the new session from its own refresh on sheet
    /// dismissal - a `.sheet` does not re-trigger the presenter's `.task` on
    /// iOS 26 (the P6.18b finding, pinned by a UI test), so the dismissal
    /// refresh is what makes the card reflect the sign-in. The coordinator
    /// instance is the same one Settings reads, so that refresh sees this
    /// push's outcome.
    @discardableResult
    func firstPushNow() async -> SyncOutcome {
        didJustSignIn = true
        // RV.6: sign-in is an invalidation event; the next refresh re-fetches.
        invalidateDeviceCount()
        guard !isSyncing, configService.allowsServerBacked, let coordinator = coordinator() else {
            return SyncOutcome()
        }
        let outcome = await coordinator.syncNow(trigger: .userInitiated)
        // RV.58: a first push that answers 410 is still a revocation - the
        // device row was revoked between the exchange and the push, so the
        // fresh session must not survive. Same terminal handling as runSync.
        if outcome.deviceRevoked {
            await detachRevokedDevice()
        }
        return outcome
    }

    /// The host-bound account client for the card's device count - the same
    /// endpoint the Account & devices screen uses, over the app's transport
    /// selection (offline under a seeded launch, the sign-in stub under a UI
    /// test that must see the count).
    ///
    /// Built WITHOUT the session refresher on purpose: the count is a secondary
    /// display detail, so a stale token must read as "count unknown", never as
    /// a refresh attempt that clears the session out from under the sync's own
    /// auth path (a 401 here maps straight to `.unauthorized` and the card
    /// shows the plain status line).
    private func accountDevicesClient() -> AccountClient {
        AccountClient(
            httpClient: TankbookHTTPClient(
                transport: makeAppTransport(),
                tokenProvider: KeychainTokenProvider(sessionStore: sessionStore)),
            director: AppConfigStore.shared.director)
    }

    /// The manual trigger. Idempotency is the coordinator's guarantee (the push
    /// count, not this flag); `isSyncing` only drives the spinner.
    ///
    /// Under `.required` (P6.18b) the trigger is a no-op: the server has
    /// stopped supporting this build, so the push would be refused anyway
    /// (426), and the sync surface renders the non-dismissible update notice
    /// instead of this affordance. The queue stays dirty (S7) - nothing is
    /// lost, nothing is claimed.
    func syncNow() async {
        await runSync(trigger: .userInitiated)
    }

    /// Signs this device out (RV.40, docs/SYNC.md -> "Sign out"). Two steps in
    /// the existing `SessionSignOut` order: revoke the refresh chain server-side
    /// (`DELETE /auth/session`, best-effort - a handed-over phone must not keep
    /// a 90-day chain valid) and clear the Keychain unconditionally (offline
    /// sign-out still signs out locally, hard rule 1). It is NOT a device
    /// revoke: the device row survives, so a later sign-in reuses it (RV.41).
    /// The local log is never touched - nothing here reads or writes the
    /// repository. After the clear, the surface re-reads the (now empty)
    /// session so the account card renders the guest state.
    func signOut() async {
        let store = sessionStore
        let authService: any AuthService = RemoteAuthService(
            director: AppConfigStore.shared.director,
            transport: makeAppTransport(),
            sessionStore: store,
            device: RemoteAuthService.SessionDevice(
                name: UIDevice.current.name,
                platform: "iOS"
            )
        )
        await SessionSignOut(authService: authService, sessionStore: store).signOut()
        // RV.6: sign-out is an invalidation event - explicit, not a side effect.
        invalidateDeviceCount()
        await refresh()
    }

    /// The launch / foreground cycle (docs/SYNC.md -> Low Power Mode; the
    /// debounced write trigger is the other `.background` door). Passes
    /// `.background`, so the cycle defers while the mode is on - the queue is
    /// exactly as it was (hard rule 8) - and the deferred cycle is registered
    /// with the resumer, which drains it the moment the mode ends. The ONLY
    /// callers are app-scheduled events; a sync the user tapped goes through
    /// `syncNow()`. A guest has nothing to sync, so the cycle is a no-op until
    /// there is an account.
    ///
    /// RV.18: rate-limited by `OpportunisticSyncPolicy` - a burst of `.active`
    /// transitions (the launch double-fire, a permission-alert dismissal, the
    /// Photos picker) is one cycle, not one each. The Settings "Sync now" tap,
    /// the retry backoff and the Low Power resumer drain never come through
    /// this door, so a forced cycle is always available.
    func runOpportunisticSync() async {
        session = try? sessionStore.load()
        guard signedIn else { return }
        let now = Date()
        guard OpportunisticSyncPolicy.shouldRun(lastOpportunisticSyncAt: lastOpportunisticSyncAt,
                                                now: now) else { return }
        lastOpportunisticSyncAt = now
        await runSync(trigger: .background)
    }

    private func runSync(trigger: PowerWorkTrigger) async {
        guard !isSyncing, configService.allowsServerBacked, let coordinator = coordinator() else { return }
        isSyncing = true
        defer { isSyncing = false }
        // OB.2: the cycle runs under a `beginBackgroundTask` guard so a sync (or
        // its blob uploads) started just before a backgrounding gets iOS's
        // grace time to finish. The expiry handler is the async edge nothing
        // else can narrate - it emits `background.task.expired` when the OS runs
        // out of patience mid-cycle (docs/LOGGING.md §4, OB.2).
        let background = BackgroundTaskLogging(log: AppLog.shared, kind: "sync")
        var backgroundTask: UIBackgroundTaskIdentifier = .invalid
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "tankbook.sync") {
            let remaining = UIApplication.shared.backgroundTimeRemaining
            DispatchQueue.main.async {
                background.note(grantedSeconds: remaining.isFinite ? max(0, Int(remaining)) : 0)
                background.expired()
                if backgroundTask != .invalid {
                    UIApplication.shared.endBackgroundTask(backgroundTask)
                    backgroundTask = .invalid
                }
            }
        }
        defer {
            if backgroundTask != .invalid {
                UIApplication.shared.endBackgroundTask(backgroundTask)
            }
        }
        let outcome = await coordinator.syncNow(trigger: trigger)
        if outcome.deferred {
            registerDeferredSync()
        }
        // RV.18: observe that the door was knocked and how many cycles have
        // actually fired per trigger. Shape-only - the trigger name and running
        // counts are loggable, domain values are not (hard rule 12).
        let counts = coordinator.cycleCounts()
        AppLog.shared.emit(SyncCycleFired(
            trigger: trigger.name,
            backgroundCount: counts.background,
            userInitiatedCount: counts.userInitiated))
        if outcome.deviceRevoked {
            // RV.58: a 410 is terminal for this device's account, and the drop
            // is what actually stops the tail - keep the tokens and every
            // opportunistic trigger re-fires a doomed cycle. Drop first, then
            // refresh so the surface reads the cleared session and the mark.
            await detachRevokedDevice()
        } else {
            await refresh()
        }
        // PR.14: the post-batch toast count. A batch that flagged nothing
        // clears any earlier count; the toast is about what just arrived.
        lastBatchFlaggedEntries = outcome.flaggedEntries > 0 ? outcome.flaggedEntries : nil
    }

    /// RV.58: a 410 (device revoked) ends this device's session. The server
    /// answers 410 to a revoked device's pull, but the access token it handed
    /// out is still valid - keep the session and every later trigger (foreground,
    /// timer, nudge, "Sync now") starts another pull that the server refuses
    /// (the three-minute 410 tail in the production log, 14:53:10 -> 14:56:04).
    /// So the credentials are dropped - docs/SECURITY.md: "a device revoked
    /// server-side gets 410, discards its tokens, and stops syncing" - and a
    /// `deviceRevoked` mark is persisted (the RV.26 `authExpired` pattern) so
    /// the surface keeps naming "sign in" instead of reading as a plain sign-out.
    /// Hard rule 8: nothing here touches the repository - the log and the dirty
    /// queue stay on the device, unsynced rows wait dirty (S7) and go up when
    /// the user signs in again (a re-attaching sign-in reuses the device row).
    /// Hard rule 1: no screen is gated on this - a revoked device keeps working
    /// locally, it just stops reaching the account.
    private func detachRevokedDevice() async {
        // clear() removes the credentials AND any stale marks, so the mark must
        // be written after it - the same order SessionRefresher uses for
        // authExpired. Best-effort exactly like sign-out: even a failed write
        // leaves the in-memory outcome driving the surface this run.
        try? sessionStore.clear()
        try? sessionStore.setDeviceRevoked(true)
        didJustSignIn = false
        // RV.6: a revoke is an invalidation event - the count fetch must re-read
        // next refresh rather than reuse a stale live count.
        invalidateDeviceCount()
        await refresh()
    }

    /// Clears the post-batch toast once the user taps through to the flagged
    /// entries (the toast's next step, docs/SYNC.md).
    func acknowledgeFlaggedBatch() {
        lastBatchFlaggedEntries = nil
    }

    /// P6.8: records the deferred cycle with the resumer so it drains on the
    /// power-state change, not at next launch (docs/SYNC.md). The id is stable,
    /// so a second deferral replaces the first registration - the queue drains
    /// once. The drain re-runs the SAME background trigger, so a mode that
    /// merely toggles re-defers cleanly.
    private func registerDeferredSync() {
        let work = LowPowerResumer.PendingWork(id: Self.deferredSyncID, kind: .syncCycle) {
            await self.runDeferredSync()
        }
        Task { await resumer.register(work) }
    }

    private func runDeferredSync() async {
        await runSync(trigger: .background)
    }
}

/// The app's one transport selection (P6.21): under a DEBUG seeded launch the
/// transport is offline/deterministic, and in release it is always the real
/// URLSession transport - the seed transports never ship.
func makeAppTransport() -> any TankbookHTTPTransport {
    #if DEBUG
    return appTransport(SeededLaunch.transport())
    #else
    return appTransport(URLSessionTransport())
    #endif
}

/// Every transport the app builds is observable (OB.2): wrapping it makes each
/// physical request emit `net.request` / `net.response` with the endpoint's
/// path and the byte counts, so a duplicate fetch (RV.59) or a doubled upload
/// (RV.65) reads from the device side. The wrapper logs shape only - never the
/// host, the query, a header or a body (hard rule 12).
func appTransport(_ inner: any TankbookHTTPTransport) -> any TankbookHTTPTransport {
    LoggingHTTPTransport(inner: inner, log: AppLog.shared)
}

/// RV.22: the Settings card the sync chip's Settings tap should scroll to
/// (docs/SYNC.md -> "The sync state chip", state 2: "Settings, scrolled to the
/// card naming the fix"). Each attention reason maps to the card that names its
/// next step; `account` is the auth-expired card (rendered in the account card's
/// signed-out branch), `revokedCard` and `quotaCard` the two issue cards below.
enum SettingsScrollTarget: Hashable, Sendable {
    case account
    case revokedCard
    case quotaCard
}

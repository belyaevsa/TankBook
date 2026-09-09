import CoreLocation
import Foundation
import TankbookCore

/// PJ.19: the app-layer seam between the Confirm sheet and the device's
/// location. The ranking lives in `TankbookCore.StationSuggestion` as a pure
/// function over injected coordinates (docs/TESTING.md, L1); CoreLocation lives
/// HERE, never in core, and this type resolves "is the location authorised, and
/// where are we?" once per Confirm sheet (docs/JOURNEYS.md -> J4).
///
/// Permission policy (docs/JOURNEYS.md -> J4): the question is asked on the
/// first Confirm after the second fill-up, never at launch and never before a
/// station is on file; a denial or a restriction is silent and permanent - the
/// ranking keeps running without its distance rungs, with no re-prompt. A
/// coordinate is a domain value and is never logged (hard rule 12): nothing
/// here logs one.
@MainActor
final class ForecourtLocationReader: NSObject, CLLocationManagerDelegate {

    private let manager: CLLocationManager?
    private let seededCoordinate: GeoCoordinate?
    private var captureContinuation: CheckedContinuation<GeoCoordinate?, Never>?
    private var watchdog: Task<Void, Never>?
    private var isReading = false

    /// The launch-argument seed `-seedStationLocation "<lat>,<lon>"` replaces
    /// the real device location so the suggestion is deterministic under UI
    /// tests and in screenshots - no permission dialog, no moving simulator
    /// (docs/TESTING.md, L4). Without it the real manager is used.
    init(arguments: [String] = ProcessInfo.processInfo.arguments) {
        if let seed = Self.parseSeed(arguments) {
            seededCoordinate = seed
            manager = nil
        } else {
            seededCoordinate = nil
            manager = CLLocationManager()
        }
        super.init()
        manager?.delegate = self
    }

    /// A fix available without waiting - the seeded location only. A real
    /// device has no fix until the GPS answers, so the synchronous ranking pass
    /// runs rung 3 (no location needed) and the distance rungs land when the
    /// read completes.
    var immediateFix: GeoCoordinate? { seededCoordinate }

    var isAuthorised: Bool {
        if seededCoordinate != nil { return true }
        guard let manager else { return false }
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: return true
        default: return false
        }
    }

    var hasAskedBefore: Bool {
        UserDefaults.standard.bool(forKey: Self.permissionAskedKey)
    }

    /// Whether the one-time permission question may be presented at all. Under
    /// the UI-test harness the system dialog must never appear (it would stall
    /// the run); those launches seed the location instead.
    func mayPresentPermissionPrompt() -> Bool {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        let harness = arguments.contains("-homeResetDatabase")
            || arguments.contains("-seedVehicleForUITests")
            || arguments.contains("-presentScreen")
        return !harness
        #else
        return true
        #endif
    }

    /// The one permission ask, at the caller's eligibility decision (first
    /// Confirm after the second fill-up with a station on file). Asking once is
    /// recorded so a later Confirm never re-prompts, and a denied or restricted
    /// status is the OS's own answer - the ranking simply runs without its
    /// distance rungs from then on.
    func requestPermissionOnce() {
        guard !hasAskedBefore, mayPresentPermissionPrompt() else { return }
        guard let manager, manager.authorizationStatus == .notDetermined else { return }
        UserDefaults.standard.set(true, forKey: Self.permissionAskedKey)
        manager.requestWhenInUseAuthorization()
    }

    /// One location read per Confirm sheet, bounded so the sheet never waits on
    /// the GPS: a fix that has not arrived in time yields nil and the ranking
    /// falls through to its no-location rungs. Settles exactly once - whichever
    /// of the delegate or the watchdog fires first clears the continuation.
    func readOnce() async -> GeoCoordinate? {
        if let seededCoordinate { return seededCoordinate }
        guard let manager, isAuthorised, !isReading else { return nil }
        isReading = true
        defer {
            isReading = false
            captureContinuation = nil
            watchdog?.cancel()
            watchdog = nil
        }
        return await withCheckedContinuation { (continuation: CheckedContinuation<GeoCoordinate?, Never>) in
            captureContinuation = continuation
            watchdog = Task { [weak self] in
                try? await Task.sleep(for: .seconds(Self.fixTimeoutSeconds))
                self?.settle(nil)
            }
            manager.requestLocation()
        }
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didUpdateLocations locations: [CLLocation]) {
        let coordinate = locations.last.map {
            GeoCoordinate(latitude: $0.coordinate.latitude,
                          longitude: $0.coordinate.longitude)
        }
        Task { @MainActor [weak self] in self?.settle(coordinate) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didFailWithError error: Error) {
        // No fix (no GPS, permission lost mid-read): the distance rungs simply
        // do not run. Nothing to say to the user - a suggestion is a bonus,
        // never an error (docs/ERRORS.md -> Confirm).
        Task { @MainActor [weak self] in self?.settle(nil) }
    }

    private func settle(_ coordinate: GeoCoordinate?) {
        captureContinuation?.resume(returning: coordinate)
        captureContinuation = nil
        watchdog?.cancel()
        watchdog = nil
    }

    private static let permissionAskedKey = "stationLocationPermissionAsked"
    private static let fixTimeoutSeconds = 6.0

    private static func parseSeed(_ arguments: [String]) -> GeoCoordinate? {
        guard let index = arguments.firstIndex(of: "-seedStationLocation"),
              arguments.indices.contains(index + 1) else { return nil }
        let parts = arguments[index + 1]
            .split(separator: ",")
            .compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count == 2 else { return nil }
        return GeoCoordinate(latitude: parts[0], longitude: parts[1])
    }
}

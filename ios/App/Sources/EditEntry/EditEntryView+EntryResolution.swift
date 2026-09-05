import SwiftUI
import TankbookCore

// RV.66 (2026-09-05): how Edit entry resolves the entry it is editing.
// Split out of EditEntryView.swift to keep that file under the linter's
// length limits - the same reason EditEntryView+Discard.swift exists.
//
// The split is functional, not cosmetic. An edit opened from the on-screen
// car's own rows (Home's log, the conflict badge) belongs to the car on
// screen, and `nil` entry ids keep meaning "the selected car's most recent
// entry" (the placeholder/debug-screenshot path). But an EXPLICIT entry id
// from an account-wide surface - the flagged list, the inbox's "use a
// different receipt" - names an entry that may live on ANY car, and the
// screen must open that entry and adopt ITS car as the screen's vehicle,
// never reject it because the currently-selected car does not own it.

extension EditEntryView {

    /// The resolved edit target: the entry, its own vehicle (the screen adopts
    /// that car's units and currency - the entry is what is being edited) and
    /// the car's other entries (the timeline-validation baseline).
    private struct ResolvedTarget {
        let vehicle: Vehicle
        let target: any Entry
        let others: [any Entry]
    }

    /// Reads the entry, its attachments and its overwrite log row from the
    /// repository. Runs on first load and again after "Restore my version" so
    /// the restored values render in the form.
    func reloadData() async {
        do {
            let repository = try AppStore.repository()
            let vehicles = try repository.liveVehicles()
            let resolved: ResolvedTarget
            if let entryID {
                // RV.66: an EXPLICIT entry id (the account-wide flagged list,
                // the inbox's "use a different receipt") opens the entry it
                // names wherever that entry lives. Scoping the search to the
                // SELECTED car's rows made an entry on the other car read
                // "Entry not found - it may have been deleted on another
                // device": the account-wide list could surface the conflict but
                // never open it while that car was unselected - the same
                // account-wide-signal/car-scoped-evidence split the chip fix
                // answers, on the screen that actually resolves the conflict
                // (hard rule 8).
                guard let match = try Self.locate(id: entryID, vehicles: vehicles,
                                                  repository: repository) else {
                    loadFailed = true
                    return
                }
                resolved = match
            } else {
                // No explicit id: same selection as Home - an edit opened from
                // the on-screen car's own rows belongs to the car on screen
                // (the Home log rows, placeholder links, `-presentScreen
                // editEntry`).
                guard let vehicle = carSelection.selectedVehicle(vehicles) else {
                    loadFailed = true
                    return
                }
                let all = try repository.liveEntries(forVehicle: vehicle.id)
                guard let target = all.first(where: { $0.id == Self.mostRecentID(all) }) else {
                    loadFailed = true
                    return
                }
                resolved = ResolvedTarget(vehicle: vehicle, target: target,
                                          others: all.filter { $0.id != target.id })
            }
            vehicle = resolved.vehicle
            otherEntries = resolved.others
            try bind(resolved.target, vehicle: resolved.vehicle, repository: repository)
        } catch {
            AppLog.error(operation: "editEntry.load", category: .ui, error: error)
            loadFailed = true
        }
    }

    /// Finds an entry by id across every live vehicle (RV.66). The account-wide
    /// list passes ids that may belong to any car; the edit screen must open
    /// the entry it names and adopt that entry's car, never reject it because
    /// the currently-selected car does not own it. The entry's car's other
    /// entries ride along - the baseline an odometer/date edit is validated
    /// against is that car's own timeline.
    private static func locate(id: UUID, vehicles: [Vehicle],
                               repository: TankbookRepository) throws -> ResolvedTarget? {
        for vehicle in vehicles {
            let all = try repository.liveEntries(forVehicle: vehicle.id)
            if let target = all.first(where: { $0.id == id }) {
                return ResolvedTarget(vehicle: vehicle, target: target,
                                      others: all.filter { $0.id != target.id })
            }
        }
        return nil
    }

    /// Fills every form and support state from the resolved entry: stations,
    /// attachments, the pending-blob set, the overwrite-log row and the right
    /// form (fill-up vs the other three entry types).
    private func bind(_ target: any Entry, vehicle: Vehicle,
                      repository: TankbookRepository) throws {
        stations = try repository.liveStations()
        attachments = try repository.liveAttachments()
            .filter { target.attachments.contains($0.id) }
        pendingBlobIDs = Set(attachments
            .filter { !BlobService.isBlobAvailable($0) }
            .map(\.id))
        // PR.14: the "Changed by sync" row is real data - the newest
        // overwrite the sync log recorded for this entry, or nil when none.
        syncOverwrite = try repository.syncOverwrite(for: target.id)
        if let fill = target as? FillUp {
            fillUp = fill
            selectedStation = stations.first { $0.id == fill.stationId }
            fillForm.load(from: fill, vehicle: vehicle)
            note = fill.note ?? ""
            #if DEBUG
            seedAttachSuggestionIfRequested()
            #endif
        } else {
            loadNonFill(target)
        }
    }

    private func loadNonFill(_ entry: any Entry) {
        switch entry {
        case let charge as ChargeSession: self.charge = charge
        case let service as ServiceRecord: self.service = service
        case let expense as Expense: self.expense = expense
        default: break
        }
        // Single source of truth with the RV.31 discard baseline
        // (`pristineNonFillForm`, EditEntryView+Discard.swift): the form is
        // loaded through the same builder the dirty check compares against, so
        // the two cannot drift.
        guard let vehicle else { return }
        nonFillForm = Self.pristineNonFillForm(for: entry, vehicle: vehicle)
    }

    /// P4.6 lazy download: opening the entry fetches the missing full rendition
    /// (docs/SYNC.md -> Delivery). Signed-out or offline, the fetch fails
    /// silently and the "photo syncing" shimmer stays - nothing blocks the
    /// entry (hard rule 1).
    func fetchPendingBlobs() async {
        guard !pendingBlobIDs.isEmpty,
              let fetcher = SyncService.makeBlobFetcher(sessionStore: KeychainSessionStore()) else { return }
        for id in pendingBlobIDs {
            guard let attachment = attachments.first(where: { $0.id == id }) else { continue }
            if (try? await fetcher.fetch(sha256: attachment.file.sha256)) != nil {
                pendingBlobIDs.remove(id)
            }
        }
    }

    private static func mostRecentID(_ entries: [any Entry]) -> UUID? {
        entries.max { $0.date < $1.date }?.id
    }
}

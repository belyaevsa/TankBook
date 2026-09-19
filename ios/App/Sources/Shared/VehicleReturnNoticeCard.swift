import SwiftUI
import TankbookCore

/// One S5 notice as the card renders it: the car's name beside the count the
/// repository keeps (docs/SYNC.md S5).
struct VehicleReturnNoticeItem: Identifiable, Equatable {
    let id: UUID
    let name: String
    let entryCount: Int
}

/// The S5 notices with their car names, and the two answers a card offers.
/// Home and Garage read the same rows and route both answers here, so the two
/// surfaces cannot disagree about which cars came back.
@MainActor
enum VehicleReturnNotices {
    static func items(repository: TankbookRepository) throws -> [VehicleReturnNoticeItem] {
        let notices = try repository.vehicleReturnNotices()
        guard !notices.isEmpty else { return [] }
        let names = Dictionary(uniqueKeysWithValues: try repository.liveVehicles().map { ($0.id, $0.name) })
        return notices.compactMap { notice in
            guard let name = names[notice.vehicleId] else { return nil }
            return VehicleReturnNoticeItem(id: notice.vehicleId, name: name, entryCount: notice.entryCount)
        }
    }

    /// "Delete again" re-tombstones the car (dirty, so the delete pushes) and
    /// consumes the notice; "Keep" consumes only the notice.
    static func answer(_ id: UUID, deleteAgain: Bool) {
        do {
            let repository = try AppStore.repository()
            if deleteAgain {
                try repository.deleteReturnedVehicleAgain(id: id)
            } else {
                try repository.keepReturnedVehicle(id: id)
            }
        } catch {
            AppLog.error(operation: deleteAgain ? "vehicleReturn.deleteAgain" : "vehicleReturn.keep",
                         category: .ui, error: error)
        }
    }
}

/// The quiet S5 card (docs/ERRORS.md -> Home, "Archived car returned via
/// sync"): a notice, never a modal (hard rule 8), with both next steps on it.
/// An answer bumps the shared revision, so Home and Garage - both mounted,
/// both showing the same row - drop the card together.
struct VehicleReturnNoticeCard: View {
    let item: VehicleReturnNoticeItem

    @Environment(AppToastCenter.self) private var toastCenter

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "archivebox")
                .font(.caption)
                .foregroundStyle(Theme.Palette.inkSoft)
            VStack(alignment: .leading, spacing: 8) {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.inkSoft)
                    .accessibilityIdentifier("vehicleReturnMessage")
                HStack(spacing: 14) {
                    Button("Delete again") { answer(deleteAgain: true) }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.Palette.action)
                        .accessibilityIdentifier("vehicleReturnDeleteAgain")
                    Button("Keep") { answer(deleteAgain: false) }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.Palette.action)
                        .accessibilityIdentifier("vehicleReturnKeep")
                }
                .font(.caption.weight(.semibold))
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .formCard()
    }

    /// A full localized phrase per count - the Russian instrumental changes
    /// with the number, so this is never composed from parts.
    private var message: String {
        String(localized: "\(item.name) came back with \(item.entryCount) new entries – stays archived.")
    }

    private func answer(deleteAgain: Bool) {
        VehicleReturnNotices.answer(item.id, deleteAgain: deleteAgain)
        toastCenter.noteEntryChanged()
    }
}

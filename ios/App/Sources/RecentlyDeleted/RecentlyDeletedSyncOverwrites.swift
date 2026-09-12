import Foundation
import SwiftUI
import TankbookCore

/// One row of Recently deleted's "Overwritten by sync" section, read from the
/// device-local `syncOverwrite` undo log (docs/SYNC.md S1/S4) - the same record
/// the Edit entry "Changed by sync" row renders (PR.14). `entry` is the user's
/// LOSING version; the section's point is that it is kept for the 30-day window
/// and can be put back (hard rule 8 - nothing lost silently).
struct SyncOverwrittenRow: Identifiable {
    let id: UUID
    let recordId: UUID
    let entry: any Entry
    let replacedAt: Date
    /// The device whose version won, when the wire carried it. Nil leaves the
    /// row unattributed rather than inventing a name (docs/LOCALIZATION.md).
    let deviceName: String?
}

/// Builds the "Overwritten by sync" section from the real undo log the merge
/// writes (`SyncEngine.applyPull` / `resolveConflict` -> `recordSyncOverwrite`).
/// It is deliberately not a launch-argument fixture: a user whose entry lost a
/// merge sees this section in a Release build, with no flag (docs/ERRORS.md ->
/// Recently deleted).
enum RecentlyDeletedSyncOverwrites {
    /// The section's rows, newest overwrite first. Empty when nothing was
    /// overwritten - the section then does not exist, which is the honest state.
    /// An overwrite whose losing payload this build cannot decode is skipped
    /// rather than rendered as a blank row.
    static func rows(from repository: TankbookRepository) throws -> [SyncOverwrittenRow] {
        try repository.syncOverwrittenEntries().compactMap { overwrite in
            guard let entry = entry(from: overwrite) else { return nil }
            return SyncOverwrittenRow(id: overwrite.id,
                                      recordId: overwrite.recordId,
                                      entry: entry,
                                      replacedAt: overwrite.replacedAt,
                                      deviceName: overwrite.deviceName)
        }
    }

    /// "Replaced Aug 21", "28 days left", "changed on iPad" - one fact per line:
    /// the losing version's own countdown (the same 30-day window every
    /// tombstone row carries) plus the winning device when the wire attributed
    /// it. Line-separated rather than dot-joined because the column beside the
    /// two-line action is narrow enough that RU hyphenates a joined caption.
    static func subtitle(_ row: SyncOverwrittenRow, now: Date = Date()) -> String {
        let day = HomeFormat.day(row.replacedAt)
        let days = TombstoneCountdown.daysRemaining(deletedAt: row.replacedAt, now: now)
        var parts = [String(format: L10n.localize("Replaced %@"), day),
                     String(localized: "\(days) days left")]
        if let device = row.deviceName {
            parts.append(String(format: L10n.localize("changed on %@"), device))
        }
        return parts.joined(separator: "\n")
    }

    /// Decodes the losing version from the log's stored payload. The entity
    /// dispatch mirrors `restoreSyncOverwrite`, the action this section offers.
    private static func entry(from overwrite: SyncOverwrite) -> (any Entry)? {
        let envelope = PayloadEnvelope(entityType: overwrite.entityType,
                                       schemaVersion: PayloadCodec.currentSchemaVersion,
                                       payload: overwrite.losingPayload)
        switch overwrite.entityType {
        case FillUp.entityType:
            return try? PayloadCodec.decode(envelope, as: FillUp.self).entity
        case ChargeSession.entityType:
            return try? PayloadCodec.decode(envelope, as: ChargeSession.self).entity
        case ServiceRecord.entityType:
            return try? PayloadCodec.decode(envelope, as: ServiceRecord.self).entity
        case Expense.entityType:
            return try? PayloadCodec.decode(envelope, as: Expense.self).entity
        default:
            return nil
        }
    }
}

/// A losing version's card in the "Overwritten by sync" section. It carries the
/// one real action the undo log supports - "Restore my version" - because the
/// Compare diff screen the old fixture named was never built (PJ.59). Same card
/// language as the tombstone rows: title + subtitle + a capsule action.
struct SyncOverwrittenCard: View {
    let title: String
    let subtitle: String
    let onRestore: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.Palette.inkSoft)
                .frame(width: 17, height: 17)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.Palette.inkSoft)
                    .lineLimit(2)
                // The caption names the device and the days left - the next
                // step's context - so it shows in full rather than truncating.
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.inkSoft.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button(action: onRestore) {
                Text("Restore my version")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.Palette.action)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .overlay(Capsule().stroke(Theme.Palette.hairline, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("recentlyDeletedSyncRestoreButton")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .formCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("recentlyDeletedSyncRow")
    }
}

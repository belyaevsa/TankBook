import SwiftUI
import TankbookCore
import UniformTypeIdentifiers

/// The local restore-from-backup door (RV.260; docs/SCREENMAP.md). Picks a
/// Tankbook backup folder, imports it through `VehicleArchiveReader` with no
/// network and no account (hard rule 1), and surfaces the reader's refusal with
/// its named next step (hard rule 7).
///
/// Pushed as `Route.restoreFromBackup` from both restore-failure screens (inside
/// the sign-in sheet) and from Settings, beside Export.
struct RestoreFromBackupView: View {
    @Environment(\.dismiss) private var dismiss
    /// The sign-in flow's sheet dismissal. The failure screens present this
    /// screen INSIDE the sign-in sheet, where the local `dismiss` would only pop
    /// the pushed stack and leave the sheet up; the host injects the sheet's
    /// dismissal so a successful import lands on Home. Settings injects nothing,
    /// so there the plain `dismiss` pops back.
    @Environment(\.restoreBackupFlow) private var flowContext
    @Environment(AppToastCenter.self) private var toastCenter
    @Environment(AppCarSelection.self) private var carSelection

    @State private var model: RestoreFromBackupModel?
    @State private var showingPicker = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if let model {
                    switch model.phase {
                    case .failed(let failure):
                        errorCard(failure)
                    case .idle, .importing, .imported:
                        EmptyView()
                    }
                }
                pickCard
            }
            .padding(.horizontal, Theme.Spacing.screenMargin)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .background(Theme.Palette.midnight)
        .fileImporter(isPresented: $showingPicker,
                      allowedContentTypes: [.folder],
                      allowsMultipleSelection: false) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            model?.importBackup(at: url)
            handleOutcome()
        }
        .task {
            guard model == nil else { return }
            model = try? RestoreFromBackupModel.makeDefault()
            #if DEBUG
            // RV.260 UI-test/screenshot seam: `simctl` cannot drive the system
            // file picker, so a launch with `-seedRestoreBackup` imports the
            // archive `RestoreBackupTestSeed` built through the REAL
            // `ExportBuilder` path - the picker is the only step replaced.
            if let seeded = RestoreBackupTestSeed.archiveURL {
                model?.importBackup(at: seeded)
                handleOutcome()
            }
            #endif
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "externaldrive.badge.timemachine")
                .font(.system(size: 40))
                .foregroundStyle(Theme.Palette.action)
            Text("Restore a Tankbook backup")
                .font(.title2.weight(.bold))
                .foregroundStyle(Theme.Palette.ink)
                .accessibilityIdentifier("restoreBackupTitle")
            Text("Pick the backup folder you saved with Export – no account or connection needed.")
                .font(.footnote)
                .foregroundStyle(Theme.Palette.inkSoft)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var pickCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            if model?.phase == .importing {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small).tint(Theme.Palette.inkSoft)
                    Text("Restoring…")
                        .font(.subheadline)
                        .foregroundStyle(Theme.Palette.inkSoft)
                }
                .accessibilityIdentifier("restoreBackupImporting")
            } else {
                Button {
                    showingPicker = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "folder")
                            .font(.subheadline)
                        Text("Choose backup folder")
                            .font(.body.weight(.semibold))
                    }
                    .foregroundStyle(Theme.Palette.midnight)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(Theme.Palette.taillight)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("restoreBackupChooseButton")
            }
        }
        .padding(18)
        .formCard()
    }

    private func errorCard(_ failure: RestoreFromBackupFailure) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(message(for: failure))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("restoreBackupError")
            Text(nextStep(for: failure))
                .font(.footnote)
                .foregroundStyle(Theme.Palette.inkSoft)
                .lineSpacing(1.5)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Theme.Palette.warn.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Theme.Palette.warn.opacity(0.3), lineWidth: 1)
        )
    }

    private func message(for failure: RestoreFromBackupFailure) -> LocalizedStringKey {
        switch failure {
        case .unreadable:
            "We couldn't read that folder."
        case .archive(.missingManifest), .archive(.malformedManifest), .archive(.malformedData):
            "That folder isn't a Tankbook backup."
        case .archive(.scopeMismatch(_, .account)):
            "This is a full-account backup, not a single car."
        case .archive(.scopeMismatch):
            "This backup doesn't match what this screen restores."
        case .archive(.unsupportedSchemaVersion):
            "This backup was made by a newer version of Tankbook."
        case .archive(.passphraseRequired), .archive(.wrongPassphrase):
            "This backup is protected by a password."
        case .archive(.invalidPayload), .archive(.blobHashMismatch):
            "This backup is damaged and can't be restored."
        case .archive(.missingData), .archive(.vehicleNotFound), .archive(.underlying):
            "We couldn't restore this backup."
        }
    }

    private func nextStep(for failure: RestoreFromBackupFailure) -> LocalizedStringKey {
        switch failure {
        case .unreadable:
            "Make sure the folder is downloaded, then choose it again."
        case .archive(.missingManifest), .archive(.malformedManifest), .archive(.malformedData):
            "Choose the folder Tankbook created when you exported – it holds manifest.json and data.json."
        case .archive(.scopeMismatch(_, .account)):
            "Sign in with the same account to restore everything, or export a single car and restore that here."
        case .archive(.scopeMismatch):
            "Choose a backup exported from a single car's screen."
        case .archive(.unsupportedSchemaVersion):
            "Update Tankbook, then try again."
        case .archive(.passphraseRequired), .archive(.wrongPassphrase):
            "Export a backup without a password, or restore from your account instead."
        case .archive(.invalidPayload), .archive(.blobHashMismatch):
            "Try another backup, or sign in to restore from your account."
        case .archive(.missingData), .archive(.vehicleNotFound), .archive(.underlying):
            "Try again, or sign in to restore from your account."
        }
    }

    /// A successful import reloads Home and leaves the screen: the sheet closes
    /// when the door was opened from a restore-failure screen, otherwise the
    /// pushed screen pops.
    private func handleOutcome() {
        guard case .imported = model?.phase else { return }
        toastCenter.noteEntryChanged()
        carSelection.reload()
        if let onImported = flowContext.onImported {
            onImported()
        } else {
            dismiss()
        }
    }
}

// MARK: - The completion seam

/// The sign-in sheet's dismissal, carried to a backup screen pushed inside the
/// sheet. `@unchecked Sendable`: it is only read and written on the main actor
/// through the SwiftUI environment, so it never crosses a thread - the blanket
/// restriction is the wrong fit, not a real race.
final class RestoreBackupFlowContext: @unchecked Sendable {
    /// Called after a successful local restore. nil means "just pop".
    var onImported: (() -> Void)?
    /// The default for every non-injected context (Settings): pop the screen.
    static let popping = RestoreBackupFlowContext()
}

private struct RestoreBackupFlowKey: EnvironmentKey {
    static let defaultValue = RestoreBackupFlowContext.popping
}

extension EnvironmentValues {
    var restoreBackupFlow: RestoreBackupFlowContext {
        get { self[RestoreBackupFlowKey.self] }
        set { self[RestoreBackupFlowKey.self] = newValue }
    }
}

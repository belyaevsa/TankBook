import SwiftUI
import TankbookCore

// The per-car export (P5.5b) - reached from the car in the Garage (Vehicle
// detail). Builds THAT car's archive through P5.5a's writer (one car: its
// Vehicle, every entry, reminders, tariffs, stations, attachments and every
// tombstone - docs/SCHEMA.md -> Backup format) and hands it off through the
// system share sheet. No second writer was written: this is the P5.5a surface.
struct VehicleExportRow: View {
    let vehicle: Vehicle

    @Environment(AppToastCenter.self) private var toastCenter
    @State private var isExporting = false
    @State private var shareable: ShareableURL?
    @State private var showError = false

    var body: some View {
        Button(action: buildExport) {
            HStack(spacing: 10) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.Palette.headlight)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Export this car's data")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.Palette.ink)
                    Text("One car's full history – keep it or import it anywhere · always free")
                        .font(.caption)
                        .foregroundStyle(Theme.Palette.inkSoft)
                }
                Spacer(minLength: 8)
                if isExporting {
                    ProgressView().controlSize(.small).tint(Theme.Palette.inkSoft)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.Palette.inkSoft)
                }
            }
            .padding(.horizontal, Theme.Spacing.cardPadding)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
            .formCard()
        }
        .buttonStyle(.plain)
        .disabled(isExporting)
        .accessibilityIdentifier("vehicleExportRow")
        .sheet(item: $shareable) { shareable in
            ActivityView(items: [shareable.url])
                .presentationDetents([.medium, .large])
        }
        .alert("Couldn't build the export", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Not enough space to build the export – free some space and try again.")
        }
    }

    private func buildExport() {
        guard !isExporting else { return }
        isExporting = true
        Task {
            do {
                let repository = try AppStore.repository()
                let directory = try VehicleExport.makeTemporaryDirectory(vehicleID: vehicle.id)
                let writer = VehicleArchiveWriter(
                    repository: repository,
                    blobSource: FileBackedBlobSource(
                        directory: (try? VehiclePhotoStore.attachmentsDirectory())
                            ?? FileManager.default.temporaryDirectory))
                _ = try writer.writeArchive(vehicleID: vehicle.id, to: directory)
                shareable = ShareableURL(url: directory)
            } catch {
                showError = true
            }
            isExporting = false
        }
    }
}

/// A directory URL the share sheet can present (`URL` is not Identifiable).
private struct ShareableURL: Identifiable {
    let id = UUID()
    let url: URL
}

enum VehicleExport {
    /// A fresh temp directory for one car's archive - cleaned by the system,
    /// never inside Application Support (an export is a hand-off, not data).
    static func makeTemporaryDirectory(vehicleID: UUID) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("tankbook-exports", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let directory = root.appendingPathComponent("Tankbook-\(vehicleID.uuidString.prefix(8))",
                                                    isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

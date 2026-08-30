import SwiftUI
import TankbookCore

// The per-car export (P5.5b, PJ.38) - reached from the car in the Garage
// (Vehicle detail). Builds THAT car's archive through P5.5a's writer (one car:
// its Vehicle, every entry, reminders, tariffs, stations, attachments and every
// tombstone - docs/SCHEMA.md -> Backup format) plus the four per-car CSV files
// (fill-ups, charge sessions, service, expenses - flat rows with SCHEMA.md
// field names, the money pair, ISO dates). The CSVs ride INSIDE the archive
// directory and are handed to the share sheet as their own items (PJ.38). A
// disk-full failure surfaces its message as a state, never a crash
// (docs/ERRORS.md -> Settings; hard rule 7).
struct VehicleExportRow: View {
    let vehicle: Vehicle

    @State private var isExporting = false
    @State private var shareable: ExportShareable?
    @State private var failure: ExportFailure?

    var body: some View {
        Button(action: buildExport) {
            HStack(spacing: 10) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.Palette.action)
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
        .onAppear { presentCarExportIfRequested() }
        .exportFlow(shareable: $shareable, failure: $failure, retry: buildExport)
    }

    private func buildExport() {
        guard !isExporting else { return }
        isExporting = true
        Task {
            do {
                shareable = try ExportBuilder.buildCarExport(vehicleID: vehicle.id)
            } catch {
                failure = ExportFailure.map(error)
            }
            isExporting = false
        }
    }

    /// DEBUG/test-only: `-presentCarExportShare` opens the per-car share sheet
    /// a beat after the row appears, so a screenshot can show the CSV share
    /// sheet without a UI test driving a tap (`simctl` cannot tap). Routes
    /// through the exact method the button calls.
    private func presentCarExportIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-presentCarExportShare") else { return }
        Task {
            try? await Task.sleep(for: .milliseconds(600))
            buildExport()
        }
    }
}

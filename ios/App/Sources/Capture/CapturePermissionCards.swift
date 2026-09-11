import SwiftUI
import TankbookCore
import UIKit

/// The capture surface's two recovery cards, split out of `CaptureView.swift`
/// because that file is at its length limit. The F8 permission card and the
/// RV.223 camera-fault card look alike but name different next steps: Settings
/// can fix a permission denial and cannot fix a busy camera, so the fault card
/// offers the manual door instead.
extension CaptureView {
    /// F8: permission denied. Rendered over the embedded manual form, so the
    /// core promise degrades but the screen never becomes a dead end.
    var permissionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "camera.fill")
                    .font(.subheadline)
                    .foregroundStyle(Theme.Palette.taillight)
                Text("Scanning needs the camera – enable in Settings.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.Palette.ink)
            }
            HStack(spacing: 8) {
                permissionAction("Settings",
                                 identifier: "capturePermissionSettingsButton",
                                 action: openSettings)
                permissionAction("Type it",
                                 identifier: "capturePermissionTypeItButton",
                                 action: openManualEntry)
                permissionAction("Photos",
                                 identifier: "capturePermissionPhotosButton",
                                 action: openPhotos)
            }
        }
        .padding(Theme.Spacing.cardPadding)
        .background(Theme.Palette.dash)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card)
                .stroke(Theme.Palette.hairline, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("capturePermissionCard")
    }

    /// RV.223: the camera is authorised but handed back no frame - in use by
    /// another app, or a hardware fault. The shutter stays for a retry; the
    /// card's one next step is the manual door, and it never names Settings
    /// because a permission grant cannot fix a busy camera.
    var cameraFaultCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .foregroundStyle(Theme.Palette.warn)
                Text("The camera didn't respond – type the entry instead.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.Palette.ink)
            }
            permissionAction("Type it",
                             identifier: "captureFaultTypeItButton",
                             action: openManualEntry)
        }
        .padding(Theme.Spacing.cardPadding)
        .background(Theme.Palette.dash)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card)
                .stroke(Theme.Palette.hairline, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("captureFaultCard")
    }

    func permissionAction(_ label: LocalizedStringKey,
                          identifier: String,
                          action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.Palette.ink)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Capsule().fill(Theme.Palette.midnight))
                .overlay(Capsule().stroke(Theme.Palette.ink.opacity(0.15), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }

    func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

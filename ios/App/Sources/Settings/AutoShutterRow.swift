import SwiftUI
import TankbookCore

/// PJ.16: the auto-shutter setting. Off by default - an unexpected shot is worse
/// than a tap. Device-local (`UserDefaults`), never synced: it is about this
/// phone's camera, not the user's data.
struct AutoShutterRow: View {
    @AppStorage(CaptureHints.autoShutterKey) private var autoShutter = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: $autoShutter) {
                Text("Capture automatically")
                    .font(.subheadline)
                    .foregroundStyle(Theme.Palette.ink)
            }
            .tint(Theme.Palette.taillight)
            .accessibilityIdentifier("settingsAutoShutterToggle")
            Text("Takes the photo by itself once a receipt holds still in the frame.")
                .font(.caption2)
                .foregroundStyle(Theme.Palette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

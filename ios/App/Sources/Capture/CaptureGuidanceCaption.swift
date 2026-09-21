import SwiftUI
import TankbookCore

/// PU.40b - the capture screen's guidance caption and hint, split out of
/// `CaptureView` (which is at its length limit). `PreviewGuidance` owns the
/// state; this extension only decides how the screen says it.
extension CaptureView {

    /// Starts or stops the preview detector for the current mode: guidance is
    /// for the fill-up scan only, where a pump display is what the camera is
    /// pointed at. Expense, Service and charge modes keep the plain caption.
    func updateGuidance() {
        camera.setGuidanceActive(mode == .fillUpAuto)
    }

    /// True while the detector has something to say about the live frame. A
    /// search with no row leaves the ordinary caption standing.
    private var showsGuidance: Bool {
        camera.guidance.state != .searching
    }

    /// The caption slot: the guidance hint while the detector sees something,
    /// the ordinary powertrain/gate caption otherwise. The hint is a head start
    /// like any scan - the shutter stays enabled in every state (hard rule 15).
    @ViewBuilder
    var captureCaptionArea: some View {
        if showsGuidance {
            guidanceHint
                .font(.system(size: 12))
                .foregroundStyle(Theme.Palette.inkSoft)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .padding(.horizontal, 36)
                .padding(.bottom, 22)
                .accessibilityIdentifier("captureGuidance")
                .accessibilityValue(guidanceAccessibilityValue)
        } else {
            Text(captureCaption)
                .font(.system(size: 12))
                .foregroundStyle(Theme.Palette.inkSoft)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .padding(.horizontal, 36)
                .padding(.bottom, 22)
        }
    }

    /// The hint per state. `tooSmall` offers a 2× tap only when the device can
    /// actually zoom; the tap is `action` (an affordance, P6.7), never the
    /// taillight the fuel outline uses.
    @ViewBuilder
    private var guidanceHint: some View {
        switch camera.guidance.state {
        case .searching:
            EmptyView()
        case .tooSmall:
            if camera.hasZoomRange {
                Button {
                    camera.applyZoom(2)
                } label: {
                    HStack(spacing: 6) {
                        Text("Move closer")
                        Text("2×")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Theme.Palette.action)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Theme.Palette.action.opacity(0.14)))
                            .overlay(Capsule().stroke(Theme.Palette.action, lineWidth: 1))
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("captureGuidanceZoomButton")
            } else {
                Text("Move closer")
            }
        case .oneRow:
            Text("Tilt to show the whole display")
        case .ready:
            Text("Display in view")
        }
    }

    /// Shape only - the state token and frame counts, never a pixel of the
    /// frame (hard rule 12). It lets a UI test read the analyser's cost without
    /// a screenshot.
    private var guidanceAccessibilityValue: String {
        "\(camera.guidance.state.rawValue) frames=\(camera.guidance.framesAnalysed) "
            + "ms=\(camera.guidance.lastAnalysisMs)"
    }
}

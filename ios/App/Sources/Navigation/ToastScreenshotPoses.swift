import Foundation
import TankbookCore

#if DEBUG
/// The root's DEBUG launch hooks, run once from its `.task`.
@MainActor
enum DebugLaunchHooks {
    static func run(toastCenter: AppToastCenter) {
        // PJ.5/RV.78: replay a tap/action via the delegate's own handle.
        NotificationReplayDriver.driveIfRequested()
        ToastScreenshotPoses.showIfRequested(toastCenter: toastCenter)
    }
}

/// Screenshot poses for the toast host: each argument posts the REAL message
/// through the real `AppToastCenter`, held on screen by `-freezeToasts`, so a
/// capture shows the exact line the app would run. Debug builds only; the
/// arguments are documented beside their capture lines in
/// `scripts/capture-screenshots.sh`.
@MainActor
enum ToastScreenshotPoses {
    static func showIfRequested(toastCenter: AppToastCenter) {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-screenshotReceiptNotSavedToast") {
            // The line a fill-up save with a lost photo runs (docs/ERRORS.md ->
            // Confirm, "receipt not saved").
            toastCenter.show(L10n.receiptNotSavedMessage)
        }
        if arguments.contains("-screenshotAfterSaveInsight") {
            // The after-save one-liner (docs/JOURNEYS.md J3 -> Done) through
            // the real copy builder. The unit is given, not read: at `.task`
            // time the seed has not written its car yet.
            toastCenter.show(AfterSaveInsightMessage.text(
                for: .segmentClosed(per100: 6.8, isBestThisYear: true),
                unit: .consumption(.lPer100)))
        }
    }
}
#endif

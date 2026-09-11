import Foundation

extension ManualFillUpView {
    /// RV.218 screenshot pose: the CHECK 5 consumption warn. 8 L over the 500 km
    /// since the seeded prior full fill implies 1.6 L/100km, below the ICE band's
    /// floor, so the warn renders with both next steps and Save stays enabled
    /// (simctl cannot type). Mirrors the `-screenshotPrefill` / `-screenshotOdometer`
    /// hooks in `load()`; kept here because `ManualFillUpView.swift` is at the
    /// SwiftLint file-length ceiling.
    func applyConsumptionOutlierPoseIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-screenshotConsumptionOutlier") else { return }
        form.odometer = "119986"
        form.liters = "8"
        form.total = "13.44"
    }
}

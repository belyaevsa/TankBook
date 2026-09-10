import SwiftUI
import TankbookCore

// PJ.45's screenshot pose, split out of VehicleDetailView.swift for the
// linter's file-length limit (the EditEntryView+Neighbourhood.swift precedent).

#if DEBUG
extension VehicleDetailView {
    /// PJ.45 screenshot pose `-scrollToPaceLimit`: simctl cannot scroll, and
    /// the pace-limit row sits under the odometer and management cards - below
    /// the fold. The pose parks it at the top of the viewport once the form has
    /// loaded (the load is async, so it retries). Screenshot-only.
    func scrollToPaceLimitIfRequested(_ proxy: ScrollViewProxy) {
        guard ProcessInfo.processInfo.arguments.contains("-scrollToPaceLimit") else { return }
        Task {
            for _ in 0..<12 {
                try? await Task.sleep(for: .milliseconds(300))
                guard vehicle != nil else { continue }
                withAnimation {
                    proxy.scrollTo(VehiclePaceLimitRow.scrollTarget, anchor: .top)
                }
                return
            }
        }
    }

    /// RV.182 screenshot pose `-scrollToAccuracy`: the capacity card sits below
    /// the fold, and the capture must show the filled tank/battery field.
    /// Screenshot-only.
    func scrollToAccuracyIfRequested(_ proxy: ScrollViewProxy) {
        guard ProcessInfo.processInfo.arguments.contains("-scrollToAccuracy") else { return }
        Task {
            for _ in 0..<12 {
                try? await Task.sleep(for: .milliseconds(300))
                guard vehicle != nil else { continue }
                withAnimation {
                    proxy.scrollTo(VehicleDetailAccuracyCard.scrollTarget, anchor: .top)
                }
                return
            }
        }
    }
}
#endif

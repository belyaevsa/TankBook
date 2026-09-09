import SwiftUI
import TankbookCore

// RV.117b: the neighbourhood computed property, split out of EditEntryView.swift
// for the linter's file-length limit (the fillUpContent extension precedent).

extension EditEntryView {
    /// The ScrollViewReader id the RV.117b neighbourhood card carries, so the
    /// `-scrollToNeighbourhood` screenshot pose can bring the panel into view.
    static let neighbourhoodScrollTarget = "timelineNeighbourhoodScrollTarget"

    /// RV.117b: the live neighbourhood behind an F9a conflict, derived by the
    /// validator from the form's candidate - nil when nothing flags or the
    /// entry has no odometer.
    var timelineNeighbourhood: TimelineNeighbourhood? {
        guard let vehicle else { return nil }
        return fillForm.timelineNeighbourhood(vehicle: vehicle,
                                              existingEntries: otherEntries)
    }

    /// RV.117b: the neighbourhood panel, present only while the candidate flags
    /// and carries a `validRange` - otherwise the card is absent entirely
    /// (never an empty box under a clean odometer card).
    @ViewBuilder
    var neighbourhoodCard: some View {
        if let neighbourhood = timelineNeighbourhood {
            TimelineNeighbourhoodCard(model: neighbourhood,
                                      distanceUnit: distanceUnit)
        }
    }

    /// RV.117b screenshot pose `-scrollToNeighbourhood`: `simctl` cannot
    /// scroll, and the panel sits under the odometer card - below the fold once
    /// the F9a warning expands. The pose scrolls the panel to the top of the
    /// viewport once it exists (the form loads asynchronously, so it retries
    /// until the card is present). Screenshot-only, like every `-open*` seam.
    #if DEBUG
    func scrollToNeighbourhoodIfRequested(_ proxy: ScrollViewProxy) {
        guard ProcessInfo.processInfo.arguments.contains("-scrollToNeighbourhood") else { return }
        Task {
            for _ in 0..<12 {
                try? await Task.sleep(for: .milliseconds(300))
                guard timelineNeighbourhood != nil else { continue }
                withAnimation {
                    proxy.scrollTo(Self.neighbourhoodScrollTarget, anchor: .top)
                }
                return
            }
        }
    }
    #endif
}

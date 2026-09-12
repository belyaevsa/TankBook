import Foundation

/// Which of Home's data sections render. The decision is a pure function of the
/// derived `HomeStats`, deliberately with no account or session input: hard rule
/// 1 forbids gating any screen on account state, so a guest with entries sees the
/// same log stream a signed-in user sees. Keeping the choice here (rather than
/// inline in the view) is what makes the "entry count, never session" property
/// assertable at L1.
///
/// The guest Home and the signed-in Home both consult this one function, so the
/// log cannot be present in one layout and absent from the other for the same
/// data.
public enum HomeLayout {
    /// What Home's log area shows. `stream` once at least one entry exists,
    /// `empty` before that (the empty-state card, or the guest's capture card).
    public enum LogArea: Equatable {
        case empty
        case stream
    }

    /// The log area for a car. `stats` is nil before a car exists, so the area is
    /// `empty` there too. No session parameter exists: no account state can change
    /// this answer (hard rule 1).
    public static func logArea(for stats: HomeStats?) -> LogArea {
        guard let stats, stats.hasEntries else { return .empty }
        return .stream
    }

    /// Whether Home renders the car switcher. More than one live car is the
    /// whole input, and there is no session parameter, so account state cannot
    /// gate it (hard rule 1) - a car switcher is not a sync feature, and a guest
    /// with two cars picks between them exactly as a signed-in user does. The
    /// signed-in header and the guest Home both consult this one function
    /// (RV.251).
    public static func showsCarSwitcher(liveCarCount: Int) -> Bool {
        liveCarCount > 1
    }
}

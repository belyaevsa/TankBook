import Foundation

/// RV.211: which F9a fix affordances an entry kind presents. A fill-up shows the
/// validator's ranked, evidence-ordered list (`PJ.34`) - with a printed receipt
/// date the odometer is preselected, without one the date is. A service or an
/// expense shows the SINGLE odometer fix instead.
///
/// The reason, written here rather than by omission (docs/ERRORS.md -> Service &
/// expenses): a fill-up's ranking exists to arbitrate between a printed receipt
/// date and a typed odometer. A service's conflict is not that question - its
/// odometer is the field on the card and the field the warn sentence names - and
/// the fill-up's no-receipt order would preselect "fix date" for a typed
/// service, which is the wrong field. One odometer fix is right whether or not
/// the service was scanned, so the non-fill kinds present it; the date stays
/// editable on the card and "save anyway" stays available, so the single fix is
/// never a dead end.
///
/// The rule lives in ONE function so the service and expense paths cannot drift.
public enum F9aFixPresentation {

    /// The entry kinds whose F9a conflict can reach a screen.
    public enum EntryKind: Equatable, Sendable {
        case fillUp
        case service
        case expense
    }

    /// The fixes a screen presents for `kind`, in order. A fill-up keeps the
    /// validator's order untouched (it is evidence-ranked); a non-fill kind is
    /// collapsed to the one odometer fix.
    public static func fixes(
        _ suggestions: [TimelineValidator.ResolutionSuggestion],
        for kind: EntryKind
    ) -> [TimelineValidator.ResolutionSuggestion] {
        switch kind {
        case .fillUp:
            return suggestions
        case .service, .expense:
            return [.fixOdometer(from: nil, to: nil)]
        }
    }
}

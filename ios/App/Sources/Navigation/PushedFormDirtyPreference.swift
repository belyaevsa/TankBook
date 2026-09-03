import SwiftUI

/// RV.31: whether the pushed screen now on top of a tab's stack holds unsaved
/// typed work (today: a pushed `EditEntry` the user has edited). Each tab's
/// content reports its own subtree's value into this key and `AppRootView`
/// reads it on a same-tab re-tap, so the pop to root either happens
/// immediately (nothing to lose) or goes through the discard confirmation
/// first (hard rule 8 - never silently lost).
///
/// A preference, not an environment value, on purpose: the publisher is a
/// PUSHED destination and the reader lives ABOVE the stack where the `[Route]`
/// paths are owned. Preferences bubble up through a `NavigationStack` push -
/// the same mechanism `ConfirmableFormPreference` already relies on to hide
/// the tab bar under a pushed Reminder form - while a value handed down into
/// the stack's root does not reliably reach pushed destinations. The value is
/// naturally per-tab: each tab's wrapper reads only its own subtree's
/// contribution, and an inactive tab (kept mounted, opacity 0) reporting into
/// ITS wrapper never leaks into a sibling tab's decision.
struct PushedFormDirtyPreference: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

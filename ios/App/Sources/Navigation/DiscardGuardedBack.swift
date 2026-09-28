import SwiftUI

/// Back navigation that never silently throws away typed work on a pushed form
/// (hard rule 8). While `isDirty`, the system back button - and with it the
/// edge swipe - is replaced by one that asks "Discard changes?", the same
/// prompt the sheet forms show; with nothing to lose, back works as usual. It
/// also publishes `PushedFormDirtyPreference`, so a re-tap of the active tab
/// asks first too.
struct DiscardGuardedBack: ViewModifier {
    let isDirty: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var isAsking = false

    func body(content: Content) -> some View {
        content
            .navigationBarBackButtonHidden(isDirty)
            .toolbar {
                if isDirty {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            isAsking = true
                        } label: {
                            Image(systemName: "chevron.backward")
                        }
                        .accessibilityLabel("Back")
                        .accessibilityIdentifier("formBackButton")
                    }
                }
            }
            .preference(key: PushedFormDirtyPreference.self, value: isDirty)
            .alert("Discard changes?", isPresented: $isAsking) {
                Button("Keep editing") {}
                Button("Discard", role: .destructive) { dismiss() }
            }
    }
}

extension View {
    func discardGuardedBack(isDirty: Bool) -> some View {
        modifier(DiscardGuardedBack(isDirty: isDirty))
    }
}

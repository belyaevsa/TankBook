import SwiftUI

/// How a sheet treats a dismissal attempt while it holds unsaved input
/// (docs/SCREENMAP.md navigation conventions, rule 1).
enum DiscardPolicy: Equatable {
    /// Only scanned data: dismissing discards silently - the photo is never
    /// lost, it re-offers from the camera roll.
    case discardSilently
    /// Unsaved typed input: dismissing asks first (Keep editing / Discard).
    case askBeforeDiscarding

    func requestsConfirmation(hasUnsavedChanges: Bool) -> Bool {
        self == .askBeforeDiscarding && hasUnsavedChanges
    }
}

/// Reusable sheet chrome that encodes the dismiss rule. Individual sheets
/// (P1.3, P1.9, P1.11) pass their own "dirty" binding; this wrapper owns the
/// drag handle (system), the swipe guard, the explicit close, and the
/// Keep editing / Discard prompt.
struct DiscardAwareSheet<Content: View>: View {
    let policy: DiscardPolicy
    @Binding var hasUnsavedChanges: Bool
    @ViewBuilder var content: () -> Content

    @Environment(\.dismiss) private var dismiss
    @State private var isShowingDiscardPrompt = false

    var body: some View {
        NavigationStack {
            content()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            requestDismiss()
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .accessibilityLabel("Close")
                        .accessibilityIdentifier("sheetCloseButton")
                    }
                }
        }
        .interactiveDismissDisabled(policy.requestsConfirmation(hasUnsavedChanges: hasUnsavedChanges))
        .alert("Discard changes?", isPresented: $isShowingDiscardPrompt) {
            Button("Keep editing") {}
            Button("Discard", role: .destructive) {
                hasUnsavedChanges = false
                dismiss()
            }
        }
    }

    private func requestDismiss() {
        if policy.requestsConfirmation(hasUnsavedChanges: hasUnsavedChanges) {
            isShowingDiscardPrompt = true
        } else {
            dismiss()
        }
    }
}

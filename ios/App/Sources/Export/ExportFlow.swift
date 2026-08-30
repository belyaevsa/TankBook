import SwiftUI
import TankbookCore

// The shared export-flow plumbing (PJ.36 whole-account on Settings, PJ.38
// per-car on Vehicle detail). The two export rows build different archives and
// different labels, but they share the same three surfaces: the system share
// sheet, the disk-full alert (docs/ERRORS.md -> Settings, "Export fails (disk)"
// - a real state that names its next step, never a crash, hard rule 7) and the
// in-flight spinner. `ExportFlowModifier` owns those three; the row owns the
// build.

/// The share-sheet payload an export row hands off. `URL` is not Identifiable,
/// so the sheet needs this wrapper; `items` are what `UIActivityViewController`
/// receives (the archive directory, plus the per-car CSV files as their own
/// share items - PJ.38).
struct ExportShareable: Identifiable {
    let id = UUID()
    let items: [Any]
}

/// The `.sheet(item:)` + disk-full `.alert` pair every export row attaches.
/// The disk-full classification comes from `ExportFailure.map` in core - the
/// same pure function the L1 test pins - so the surfaced state can never
/// silently become a thrown crash. "Try again" is the alert's next step (hard
/// rule 7): it re-runs the row's build, which is what the user is doing when
/// they have freed space.
struct ExportFlowModifier: ViewModifier {
    @Binding var shareable: ExportShareable?
    @Binding var failure: ExportFailure?
    let retry: () -> Void

    private var showsError: Binding<Bool> {
        Binding(
            get: { failure != nil },
            set: { if !$0 { failure = nil } }
        )
    }

    func body(content: Content) -> some View {
        content
            .sheet(item: $shareable) { item in
                ActivityView(items: item.items)
                    .presentationDetents([.medium, .large])
            }
            .alert("Couldn't build the export", isPresented: showsError) {
                Button("Try again") { retry() }
                Button("OK", role: .cancel) {}
            } message: {
                Text(message(for: failure))
            }
    }

    private func message(for failure: ExportFailure?) -> LocalizedStringKey {
        switch failure {
        case .insufficientStorage:
            "Not enough space to build the export."
        case .underlying:
            "Couldn't build the export."
        case nil:
            ""
        }
    }
}

extension View {
    /// The share sheet + disk-full alert pair the two export rows both use.
    func exportFlow(shareable: Binding<ExportShareable?>,
                    failure: Binding<ExportFailure?>,
                    retry: @escaping () -> Void) -> some View {
        modifier(ExportFlowModifier(shareable: shareable, failure: failure, retry: retry))
    }
}

import SwiftUI
import TankbookCore

// The shared export-flow plumbing (PJ.36 whole-account on Settings, PJ.38
// per-car on Vehicle detail). The two export rows build different archives and
// different labels, but they share the same surfaces: the system share sheet,
// the disk-full alert (docs/ERRORS.md -> Settings, "Export fails (disk)" - a
// real state that names its next step, never a crash, hard rule 7) and the
// in-flight spinner. `ExportFlowModifier` owns the alert; the row owns the
// build and hands the result to `ExportShareable.present()`.

/// The share payload an export row hands off: the archive directory, plus the
/// per-car CSV files as their own share items (PJ.38). It is not `Identifiable`
/// and no `.sheet` presents it - the row calls `present()`, which goes through
/// the one share seam (`SharePresenter`) from the button action, so no SwiftUI
/// sheet owns the activity's lifetime (RV.181).
struct ExportShareable {
    let items: [Any]
}

extension ExportShareable {
    /// Presents the export through the one share seam, logging shape-only: that
    /// the share ended, how, and that the payload was the CSV/archive export -
    /// never a filename, a row or a destination app (hard rule 12).
    @MainActor
    func present() {
        SharePresenter.present(items: items) { outcome in
            AppLog.share(operation: "export.share", kind: "csv", outcome: outcome)
        }
    }
}

/// The disk-full `.alert` every export row attaches. The disk-full
/// classification comes from `ExportFailure.map` in core - the same pure
/// function the L1 test pins - so the surfaced state can never silently become a
/// thrown crash. "Try again" is the alert's next step (hard rule 7): it re-runs
/// the row's build, which is what the user is doing when they have freed space.
struct ExportFlowModifier: ViewModifier {
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
    /// The disk-full alert the two export rows both use. The share itself is
    /// presented by `ExportShareable.present()` from the row's button action,
    /// not by a sheet here.
    func exportFlow(failure: Binding<ExportFailure?>,
                    retry: @escaping () -> Void) -> some View {
        modifier(ExportFlowModifier(failure: failure, retry: retry))
    }
}

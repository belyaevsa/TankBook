import SwiftUI
import UIKit

/// The system share sheet (`UIActivityViewController`) - the one door every
/// share in the app goes through: the diagnostics bundle, the receipt photo or
/// PDF, the whole-account and per-car exports, and "send us the file".
///
/// The activity controller is **presented by** a plain host controller rather
/// than returned as the representable's root. That is a deliberate choice, NOT
/// a proven fix: a share reported as never reaching its destination (iOS 26,
/// iPhone 13) does not reproduce on the simulator, and *Save to Files completes
/// under BOTH shapes* - which is evidence AGAINST the "the old shape had no
/// presenter" theory, since UIKit forwards a presentation up the parent
/// hierarchy. The cause is open (RV.181); what this file guarantees is a
/// visible presenter and, more usefully, an outcome record detailed enough to
/// diagnose the next device report.
///
/// UIKit is used rather than `ShareLink` because an export shares a directory
/// plus its CSV files as separate items, which `ShareLink` cannot carry.
struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]
    /// The share's outcome, called at most once when the sheet settles. It
    /// carries the WHOLE completion tuple, not just `completed`: a share that
    /// fails at its destination is otherwise indistinguishable from one the
    /// user cancelled, which is precisely why the device report could not be
    /// diagnosed. Callers log it shape-only (docs/LOGGING.md, hard rule 12) -
    /// an activity type and an error domain/code are shape, the shared content
    /// never is.
    var completion: ((ShareOutcome) -> Void)?

    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator {
        Coordinator(items: items, completion: completion, dismissSheet: { dismiss() })
    }

    func makeUIViewController(context: Context) -> ShareHostController {
        let host = ShareHostController()
        host.onFirstAppear = { [weak host] in
            guard let host else { return }
            context.coordinator.presentIfNeeded(from: host)
        }
        return host
    }

    func updateUIViewController(_ host: ShareHostController, context: Context) {
        context.coordinator.presentIfNeeded(from: host)
    }

    /// Owns the activity controller and its one-shot presentation and outcome.
    /// SwiftUI calls `updateUIViewController` repeatedly, so both the
    /// presentation and the outcome are guarded to fire exactly once.
    @MainActor
    final class Coordinator {
        let activity: UIActivityViewController
        private let completion: ((ShareOutcome) -> Void)?
        private let dismissSheet: () -> Void
        private(set) var hasPresented = false
        private(set) var hasFinished = false

        init(items: [Any], completion: ((ShareOutcome) -> Void)?,
             dismissSheet: @escaping () -> Void) {
            self.completion = completion
            self.dismissSheet = dismissSheet
            self.activity = UIActivityViewController(activityItems: items,
                                                     applicationActivities: nil)
            activity.completionWithItemsHandler = { [weak self] type, completed, _, error in
                self?.finish(ShareOutcome(activityType: type?.rawValue,
                                          completed: completed,
                                          errorDomain: (error as NSError?)?.domain,
                                          errorCode: (error as NSError?)?.code))
            }
        }

        /// Presents the activity controller from `host` once the host is in a
        /// window and is not already presenting. **The latch is set only AFTER
        /// UIKit accepts the presentation**: setting it first turns a
        /// presentation UIKit drops mid-transition into a permanent blank
        /// sheet, because `viewDidAppear` can then never retry. `presentedViewController`
        /// is the check that makes a retry safe - presenting twice throws.
        func presentIfNeeded(from host: UIViewController) {
            guard !hasPresented,
                  host.view.window != nil,
                  host.presentedViewController == nil else { return }
            host.present(activity, animated: true) { [weak self] in
                self?.hasPresented = true
            }
        }

        /// The single outcome path: forward the result and close the sheet so
        /// the empty host does not linger behind the dismissed activity.
        func finish(_ outcome: ShareOutcome) {
            guard !hasFinished else { return }
            hasFinished = true
            completion?(outcome)
            dismissSheet()
        }
    }
}

/// The plain host the activity controller is presented from. Its view is empty;
/// it exists only to be a presenter and to signal its first appearance.
final class ShareHostController: UIViewController {
    var onFirstAppear: (() -> Void)?
    private var hasAppeared = false

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !hasAppeared else { return }
        hasAppeared = true
        onFirstAppear?()
    }
}

/// What a share actually did, as UIKit reported it (RV.181). `completed` alone
/// cannot tell a cancelled share from one that failed at its destination, which
/// is why a device report of "nothing arrived" could not be diagnosed. Every
/// field here is SHAPE - an activity type, an error domain and code - never the
/// content that was shared (hard rule 12).
struct ShareOutcome: Equatable {
    let activityType: String?
    let completed: Bool
    let errorDomain: String?
    let errorCode: Int?

    /// A share the user chose that then failed - the state that used to be
    /// indistinguishable from a cancel.
    var failedAtDestination: Bool { errorDomain != nil }

    /// The stable outcome code for the info record. Three states, because
    /// "chosen and failed" is the one the device report is about and the one
    /// `completed == false` used to hide inside "cancelled".
    var logOutcome: String {
        if failedAtDestination { return "failed" }
        return completed ? "completed" : "cancelled"
    }

    /// The shape-only detail that makes a failure diagnosable: the activity
    /// identifier UIKit reported and the error's domain and code. All three are
    /// system codes; none of them is the shared content (hard rule 12).
    var failureReason: String {
        "activity=\(activityType ?? "none") error=\(errorDomain ?? "none")#\(errorCode.map(String.init) ?? "none")"
    }
}

extension AppLog {
    /// The one logging path every share in the app uses. It exists so a failed
    /// share is recorded as a **failure** with its activity and error code,
    /// rather than as a cancel: four call sites each writing that by hand is
    /// how the distinction went missing in the first place.
    static func share(operation: String, kind: String, outcome: ShareOutcome) {
        AppLog.info(operation: operation, category: .ui,
                    outcome: outcome.logOutcome, kind: kind)
        if outcome.failedAtDestination {
            AppLog.warning(operation: operation, category: .ui,
                           reason: outcome.failureReason)
        }
    }
}

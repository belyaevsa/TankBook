import SwiftUI
import UIKit

/// The system share sheet (`UIActivityViewController`) - the one door every
/// share in the app goes through: the diagnostics bundle, the receipt photo or
/// PDF, the whole-account and per-car exports, and "send us the file".
///
/// The activity controller is presented by the key window's **top-most**
/// controller (`SharePresenter.present`), never hosted as a SwiftUI `.sheet`'s
/// root. The sheet-root shape put the activity two or three modal levels deep
/// and left the chosen destination's own UI - Mail's composer, the Files
/// browser, a third-party extension - to be presented from a host that SwiftUI
/// could tear down as it re-evaluated the `.sheet`; a device report of "I picked
/// a destination and nothing arrived" (iOS 26, iPhone 13) is the failure shape
/// this removes. Presenting from the top-most controller means no view in the
/// tree owns the activity's lifetime.
///
/// Every share, single-item photo/PDF included, uses this seam rather than
/// SwiftUI's `ShareLink`. The reason is the outcome record below: a share that
/// ran and then failed at its destination must be distinguishable from one the
/// user cancelled, and that record (`ShareOutcome`, logged by `AppLog.share`)
/// is the evidence the RV.181 device report needs. `ShareLink` presents natively
/// but reports nothing, so a `ShareLink` photo share could never name its
/// destination error in the diagnostics preview. One seam, one record.
///
/// UIKit is also what the export needs regardless: it shares a directory plus
/// its CSV files as separate items, which `ShareLink` cannot carry.
@MainActor
enum SharePresenter {

    /// The production entry point: the key window's top-most controller. A
    /// share is a button action, so this runs while a SwiftUI sheet may still
    /// be on screen; walking to the top is what keeps the destination's UI
    /// alive for as long as UIKit needs it.
    @discardableResult
    static func present(items: [Any],
                        completion: ((ShareOutcome) -> Void)? = nil) -> UIActivityViewController? {
        present(items: items, from: keyWindow()?.rootViewController, completion: completion)
    }

    /// Presents from an explicit root. Split out so a unit test can drive a
    /// stacked controller chain without a live key window.
    @discardableResult
    static func present(items: [Any],
                        from root: UIViewController?,
                        completion: ((ShareOutcome) -> Void)? = nil) -> UIActivityViewController? {
        guard let presenter = topMost(from: root),
              !(presenter is UIActivityViewController) else { return nil }
        let activity = makeActivity(items: items, completion: completion)
        presenter.present(activity, animated: true)
        return activity
    }

    /// Builds the activity controller and its one-shot outcome handler. The
    /// gate exists because `completionWithItemsHandler` is UIKit's to call and a
    /// late second call must not double-log a share.
    static func makeActivity(items: [Any],
                             completion: ((ShareOutcome) -> Void)?) -> UIActivityViewController {
        let activity = UIActivityViewController(activityItems: items, applicationActivities: nil)
        let gate = ShareCompletionGate(completion: completion)
        activity.completionWithItemsHandler = { type, completed, _, error in
            gate.finish(ShareOutcome(activityType: type?.rawValue,
                                     completed: completed,
                                     errorDomain: (error as NSError?)?.domain,
                                     errorCode: (error as NSError?)?.code))
        }
        return activity
    }

    /// Walks `presentedViewController` from `root` to the controller nothing is
    /// presented on. That controller is the only safe presenter: presenting on a
    /// controller that already presents something throws.
    static func topMost(from root: UIViewController?) -> UIViewController? {
        var top = root
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }

    private static func keyWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
    }
}

/// Holds the one-shot guard for a share's outcome. It is retained by the
/// activity controller's handler, so it lives exactly as long as the activity.
@MainActor
private final class ShareCompletionGate {
    private var hasFinished = false
    private let completion: ((ShareOutcome) -> Void)?

    init(completion: ((ShareOutcome) -> Void)?) {
        self.completion = completion
    }

    func finish(_ outcome: ShareOutcome) {
        guard !hasFinished else { return }
        hasFinished = true
        completion?(outcome)
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

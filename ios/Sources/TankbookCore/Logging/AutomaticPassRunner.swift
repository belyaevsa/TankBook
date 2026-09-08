import Foundation

/// Runs the automatic foreground pass's ordered steps, recording each step on
/// the log BEFORE its work runs (RV.139b, docs/LOGGING.md §4). The mark is
/// written ahead of the await it names, so a step that hangs leaves every mark
/// up to and including its own already in the log - "which step the pass
/// reached" survives a stall, and a session with no `automatic.pass` line at
/// all means `runAutomaticPass` never ran. Shape only: step codes and nothing
/// else (hard rule 12).
@MainActor
public enum AutomaticPassRunner {
    /// One step of the pass: the stable code that names it on the log, and the
    /// work itself. Both halves travel together so a step cannot be added to
    /// the pass without naming it - the mark is the point of the type.
    public struct Step {
        public let code: AutomaticPassMark
        public let work: () async -> Void

        public init(code: AutomaticPassMark, work: @escaping () async -> Void) {
            self.code = code
            self.work = work
        }
    }

    /// Emits `.started`, awaits each step's work behind its mark, then emits
    /// `.finished`. Sequential by construction: step N's work has fully
    /// returned before step N+1 is even marked, so the pass order reads off the
    /// steps array.
    public static func run(steps: [Step], log: TankbookLog) async {
        log.emit(AutomaticPass(step: .started))
        for step in steps {
            log.emit(AutomaticPass(step: step.code))
            await step.work()
        }
        log.emit(AutomaticPass(step: .finished))
    }
}

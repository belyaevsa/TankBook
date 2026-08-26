import Foundation

/// The inputs to the J11a sign-in decision (docs/JOURNEYS.md J11a): whether the
/// user arrived intending to restore ("Already use Tankbook?"), whether the
/// just-signed-in account has any data, and whether the device holds a local log.
public struct SignInContext: Sendable, Equatable {
    public let arrivedViaRestore: Bool
    public let accountHasData: Bool
    public let localHasData: Bool

    public init(arrivedViaRestore: Bool, accountHasData: Bool, localHasData: Bool) {
        self.arrivedViaRestore = arrivedViaRestore
        self.accountHasData = accountHasData
        self.localHasData = localHasData
    }
}

/// What the app should do next after a successful sign-in.
public enum SignInOutcome: Sendable, Equatable {
    /// The account has data -> pull it (the Restoring screen).
    case restore
    /// Empty account, arrived via "Already use Tankbook?" -> the wrong-provider
    /// question (never an empty garage presented as data loss).
    case wrongProvider
    /// A local log exists -> upload it (J11a never overwrites local data).
    case uploadLocalLog
    /// Nothing to restore and nothing to upload -> an ordinary sign-in.
    case plainSignIn
}

/// The pure J11a decision. This is the piece that turns the wrong-provider trap
/// (docs/JOURNEYS.md J11a) into a guarantee instead of a hope, so it is unit
/// tested exhaustively rather than hidden inside a view.
///
/// Precedence is deliberate:
///
/// 1. **A local log never gets overwritten.** Whatever the intent and whatever
///    the account holds, a populated local log uploads - it is never replaced by
///    a pull or left looking empty (J11a's reverse guard).
/// 2. **Empty account + restore intent = wrong provider.** The user expected
///    their data and the account is empty, so the honest question is shown with
///    a one-tap provider switch.
/// 3. An account with data restores.
/// 4. Nothing anywhere = an ordinary sign-in.
public enum SignInRouter {
    public static func decide(_ context: SignInContext) -> SignInOutcome {
        if context.localHasData { return .uploadLocalLog }
        if context.arrivedViaRestore && !context.accountHasData { return .wrongProvider }
        if context.accountHasData { return .restore }
        return .plainSignIn
    }
}

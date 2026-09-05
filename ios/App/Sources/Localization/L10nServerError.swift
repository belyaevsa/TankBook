import TankbookCore

// MARK: - Sign in: copy the coded error envelope drives (PR.9)

extension L10n {
    /// "Apple couldn't sign you in – try again." - the provider-refused row
    /// (docs/ERRORS.md -> Sign in): the server rejected the identity token
    /// (`token_invalid` / `provider_unsupported`). The status alone said only
    /// "401"; the code lets the surface name the provider that refused, whose
    /// next step is a retry - not "check your connection". One full localised
    /// phrase per language; the provider name never governs a case
    /// (Apple/Google are indeclinable, docs/LOCALIZATION.md).
    static func providerSignInFailed(_ provider: AuthProvider) -> String {
        String(format: localize("%@ couldn't sign you in – try again."), providerName(provider))
    }

    /// "Your device's date looks off (Aug 2019) – sign-in needs it correct.
    /// Open Settings > Date & Time." - the clock-skew row (docs/ERRORS.md ->
    /// Sign in): the server rejected the identity token because the device
    /// clock is wrong, which a retry will not fix. Only the server knows this,
    /// so only a `clock_skew` code (PR.9) can surface it. The month-year is
    /// runtime data in a slot; the phrase is one full localised key per language.
    static func clockSkewMessage(monthYear: String) -> String {
        String(format: localize("Your device's date looks off (%1$@) – sign-in needs it correct. Open Settings > Date & Time."), monthYear)
    }
}

import Foundation

// MARK: - Language picker (RV.24)

extension L10n {
    /// "System default" - the picker's way back to following the system. A
    /// distinct state from "the system language happens to be English"
    /// (docs/TASKS.md RV.24).
    static var languageSystemDefault: String {
        localize("System default")
    }

    /// The restart prompt (docs/ERRORS.md -> Settings): names its next step -
    /// open the app again. Never a bare "restart required", never a
    /// programmatic exit (hard rule 7).
    static var languageRestartPrompt: String {
        localize("Language changes the next time you open Tankbook")
    }
}

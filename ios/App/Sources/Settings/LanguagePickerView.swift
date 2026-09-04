import SwiftUI
import TankbookCore

/// The language codes the app offers, derived from the bundle (never a
/// hardcoded pair - a third language needs no code change here), plus their
/// display names and the language the app is currently rendering in.
enum LanguageDisplay {
    /// `Bundle.main.localizations` minus "Base", sorted. Today ["en", "ru"].
    static var offered: [String] {
        Bundle.main.localizations
            .filter { $0 != "Base" }
            .sorted()
    }

    /// The endonym for a language code, capitalised: "English", "Русский".
    static func name(_ code: String) -> String {
        let locale = Locale(identifier: code)
        return locale.localizedString(forLanguageCode: code)?.capitalized ?? code
    }

    /// The language the app is currently rendering in (follow-system and
    /// overridden-at-launch both resolve here). Falls back to "en".
    static var currentCode: String {
        Bundle.main.preferredLocalizations.first ?? "en"
    }
}

/// The Settings row that opens the language picker (docs/TASKS.md RV.24). Shows
/// the current language - the stored choice when one exists, else the language
/// the app is currently rendering in - never a hardcoded name.
///
/// RV.42: when the app is pending a relaunch to apply the stored choice, the row
/// carries the restart prompt itself - the notice survives dismissing the picker
/// (hard rule 7: every error names its next step and survives being ignored).
/// `pendingRestart` is derived (docs/TASKS.md RV.42), never a stored flag.
struct LanguageRow: View {
    /// The language the row displays: the user's stored choice wins; without one
    /// the app follows the system (docs/TASKS.md RV.24 - the L1 rule, resolved).
    let value: String
    /// Whether the stored choice differs from the language actually running, so
    /// a relaunch is needed to apply it (RV.42, derived in core).
    let pendingRestart: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("Language")
                        .font(.subheadline)
                        .foregroundStyle(Theme.Palette.ink)
                    Spacer(minLength: 8)
                    Text(verbatim: value)
                        .font(.footnote)
                        .foregroundStyle(Theme.Palette.inkSoft)
                        .accessibilityIdentifier("settingsLanguageValue")
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.Palette.inkSoft)
                }
                if pendingRestart {
                    // AMBER, and with a glyph (product owner, 2026-09-04: the
                    // earlier grey line "is blind"). `warn` is hard rule 5's
                    // attention colour and this is attention by definition - the
                    // user changed a setting and an action is still outstanding
                    // before it takes effect. It is NOT an error: nothing failed
                    // and nothing is lost, so it stays a notice in `warn`, never
                    // red and never a system dialog.
                    //
                    // The icon is not decoration. `DESIGN.md`'s accessibility
                    // floor says colour is never the only channel, so an amber
                    // line with no glyph would fail a colour-blind reader
                    // exactly as the grey one failed everyone.
                    Label {
                        Text(L10n.languageRestartPrompt)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                    }
                    .font(.footnote)
                    .foregroundStyle(Theme.Palette.warn)
                    .accessibilityIdentifier("settingsLanguagePendingNotice")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("settingsLanguageRow")
    }
}

/// The in-app language picker (docs/TASKS.md RV.24, Option B): lists the app's
/// real localizations plus a "System default" way back to following the system,
/// writes the choice to `AppleLanguages` so it applies on the next launch, and
/// names the next step (open the app again - never a programmatic exit, hard
/// rule 7). `selection` is a binding so the row reflects the choice immediately
/// (nil = follow the system); `store` is the persistence (the `AppleLanguages`
/// effect).
struct LanguagePickerView: View {
    let store: LanguagePreferenceStore
    @Binding var selection: String?
    @Environment(\.dismiss) private var dismiss
    @State private var pendingChange: Bool

    init(store: LanguagePreferenceStore, selection: Binding<String?>, promptOnOpen: Bool = false) {
        self.store = store
        self._selection = selection
        self._pendingChange = State(initialValue: promptOnOpen)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    VStack(spacing: 0) {
                        optionRow(title: L10n.languageSystemDefault,
                                  selected: selection == nil,
                                  identifier: "languageOption-system",
                                  action: chooseSystem)
                        ForEach(LanguageDisplay.offered, id: \.self) { code in
                            CardDivider()
                            optionRow(title: LanguageDisplay.name(code),
                                      selected: selection == code,
                                      identifier: "languageOption-\(code)",
                                      action: { choose(code) })
                        }
                    }
                    .formCard()

                    if pendingChange {
                        Text(L10n.languageRestartPrompt)
                            .font(.footnote)
                            .foregroundStyle(Theme.Palette.inkSoft)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, Theme.Spacing.cardPadding)
                            .padding(.vertical, 10)
                            .formCard()
                            .accessibilityIdentifier("settingsLanguagePrompt")
                    }
                }
                .padding(.horizontal, Theme.Spacing.screenMargin)
                .padding(.top, 4)
                .padding(.bottom, 32)
            }
            .background(Theme.Palette.midnight)
            .navigationTitle("Language")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("settingsLanguageDoneButton")
                }
            }
        }
    }

    private func optionRow(title: String, selected: Bool, identifier: String,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(verbatim: title)
                    .font(.subheadline)
                    .foregroundStyle(Theme.Palette.ink)
                Spacer(minLength: 8)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.Palette.taillight)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }

    private func chooseSystem() {
        let before = selection
        store.followSystem()
        selection = nil
        pendingChange = before != nil
    }

    private func choose(_ code: String) {
        let before = selection
        store.select(code)
        selection = code
        pendingChange = before != code
    }
}

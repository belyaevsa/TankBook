import SwiftUI
import TankbookCore

/// The About screen's "Tell us" composer (PJ.20, design/screens/About.dc.html,
/// docs/ERRORS.md -> About & feedback). The send-feedback row posts to
/// `POST /feedback` through the core `FeedbackOutbox`, with queued-offline and
/// 429 states that each name their next step and survive being ignored.
///
/// The consent is the load-bearing part: it defaults OFF, persists, and is
/// changeable afterwards (hard rule 13); a case is queued only with consent.
/// The device model rides only with its own toggle, per the contract.
///
/// RV.159: the consent is drawn as the requirement it is, not as a twin of
/// About's optional "Attach diagnostics" opt-in above it. It sits in its own
/// section under the "Before you send" eyebrow (the same SectionEyebrow idiom
/// StationSettingsView uses), so the user can tell the gate - the one thing
/// that must be ON for Send to work - from the optional attachments, whose
/// consent never blocks anything.
///
/// RV.160: a terminal outcome (sent OR queued - a queued case is not a failure)
/// COLLAPSES the composer into a confirmation panel, because the outcome line
/// used to sit below the Send button at the bottom of a tall composer in a
/// scroll view - below the fold at the moment of the tap on a small screen, and
/// under the keyboard when one was up - so a send that succeeded read as a send
/// that did nothing. Replacing the whole form with a prominent panel where the
/// form's top was puts the confirmation in the visible region at ANY scroll
/// position: the About content above the composer never moves, and the collapse
/// shortens the scroll so deep positions clamp back toward the panel.
struct FeedbackComposerView: View {
    @Bindable var model: FeedbackModel

    var body: some View {
        if model.state.isTerminalOutcome {
            terminalComposer
        } else {
            composerForm
        }
    }

    /// The full composer: category, message, toggles, reply, consent, then the
    /// Send action. `consentRequired` is a refusal, not an outcome, so it keeps
    /// the whole form and shows its warn next step above the button.
    private var composerForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionEyebrow("Tell us")
            categoryChips
            textEditor
            deviceModelToggle
            replyField
            SectionEyebrow("Before you send", identifier: "feedbackConsentHeader")
            consentToggle
            refusalLine
            sendButton
            footnote
        }
    }

    /// RV.160: what the composer becomes after a send (docs/ERRORS.md -> About
    /// & feedback). The submitted message no longer lives in the form - it is
    /// with the server or in the outbox - so the form is replaced by one clear
    /// statement of where it is. The queued copy is reassurance, never an error,
    /// and `.sent` is the one positive-done state (`Theme.Palette.ok`,
    /// docs/DESIGN.md RV.22).
    private var terminalComposer: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionEyebrow("Tell us")
            outcomePanel
            footnote
        }
    }

    // MARK: - Category

    private var categoryChips: some View {
        HStack(spacing: 6) {
            chip(.feature, label: L10n.feedbackCategory(.feature))
            chip(.problem, label: L10n.feedbackCategory(.problem))
            chip(.other, label: L10n.feedbackCategory(.other))
        }
    }

    private func chip(_ category: FeedbackCategory, label: String) -> some View {
        let selected = model.category == category
        return Button {
            model.category = category
        } label: {
            Text(label)
                .font(.caption.weight(selected ? .bold : .semibold))
                .foregroundStyle(selected ? Theme.Palette.midnight : Theme.Palette.inkSoft)
                .padding(.horizontal, 13)
                .padding(.vertical, 7)
                .background(selected ? Theme.Palette.taillight : Theme.Palette.dash)
                .overlay(Capsule().stroke(selected ? Theme.Palette.taillight : Theme.Palette.hairline,
                                          lineWidth: selected ? 1.5 : 1))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("feedbackCategory-\(category.rawValue)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: - Text

    private var textEditor: some View {
        ZStack(alignment: .topLeading) {
            if model.text.isEmpty {
                Text(L10n.feedbackPlaceholder)
                    .font(.subheadline)
                    .foregroundStyle(Theme.Palette.inkSoft.opacity(0.6))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 18)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $model.text)
                .font(.subheadline)
                .foregroundStyle(Theme.Palette.ink)
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(minHeight: 128)
                .accessibilityIdentifier("feedbackTextEditor")
        }
        .formCard()
    }

    // MARK: - Toggles and reply

    private var deviceModelToggle: some View {
        Toggle(isOn: $model.attachDeviceModel) {
            Text(L10n.feedbackAttachDeviceModel)
                .font(.caption)
                .foregroundStyle(Theme.Palette.inkSoft)
        }
        .tint(Theme.Palette.taillight)
        .padding(.horizontal, 2)
        .accessibilityIdentifier("feedbackDeviceModelToggle")
    }

    private var replyField: some View {
        TextField(L10n.feedbackReplyTo, text: $model.replyTo)
            .font(.subheadline)
            .foregroundStyle(Theme.Palette.ink)
            .keyboardType(.emailAddress)
            .textContentType(.emailAddress)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .padding(.horizontal, Theme.Spacing.cardPadding)
            .padding(.vertical, 12)
            .formCard()
            .accessibilityIdentifier("feedbackReplyField")
    }

    /// The once-asked opt-in, default OFF. This is what "consent means
    /// something" is about: without it the outbox refuses to queue a case.
    /// RV.159: the eyebrow above (`feedbackConsentHeader`, "Before you send")
    /// is what keeps this from reading as a twin of About's optional "Attach
    /// diagnostics" card - it is the one opt-in whose absence blocks Send.
    private var consentToggle: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $model.hasConsented) {
                Text(L10n.feedbackConsent)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.Palette.ink)
            }
            .tint(Theme.Palette.taillight)
            .accessibilityIdentifier("feedbackConsentToggle")
            Text(L10n.feedbackConsentDetail)
                .font(.caption2)
                .foregroundStyle(Theme.Palette.inkSoft)
                .lineSpacing(1.3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .formCard()
    }

    // MARK: - Send

    private var sendButton: some View {
        Button {
            Task { await model.send() }
        } label: {
            Group {
                if model.state == .sending {
                    ProgressView().tint(Theme.Palette.midnight)
                } else {
                    Text(L10n.feedbackSend)
                }
            }
            .font(.body.weight(.bold))
            .foregroundStyle(Theme.Palette.midnight)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(Theme.Palette.taillight)
            .clipShape(RoundedRectangle(cornerRadius: 15))
        }
        .buttonStyle(.plain)
        .disabled(!model.canSend || model.state == .sending)
        .opacity(model.canSend ? 1 : 0.5)
        .accessibilityIdentifier("feedbackSendButton")
    }

    // MARK: - Outcome

    /// The confirmation panel a terminal outcome leaves behind: a leading status
    /// glyph and semibold copy on a bordered `dash` panel. The `ink` text and
    /// the panel lift it out of the muted captions the old line drowned in, and
    /// each outcome keeps its own accessibility identifier - the localization
    /// key itself - so a test or VoiceOver can tell `.sent` from a queued state.
    @ViewBuilder
    private var outcomePanel: some View {
        switch model.state {
        case .sent:
            outcomeCard(L10n.feedbackSent, glyph: "checkmark.seal.fill",
                        glyphTint: Theme.Palette.ok, identifier: "feedbackSent")
        case .queuedOffline:
            outcomeCard(L10n.feedbackQueuedOffline, glyph: "arrow.triangle.2.circlepath",
                        glyphTint: Theme.Palette.inkSoft, identifier: "feedbackQueuedOffline")
        case .queuedRateLimited:
            outcomeCard(L10n.feedbackRateLimited, glyph: "arrow.triangle.2.circlepath",
                        glyphTint: Theme.Palette.inkSoft, identifier: "feedbackRateLimited")
        case .queuedRetry:
            outcomeCard(L10n.feedbackQueuedRetry, glyph: "arrow.triangle.2.circlepath",
                        glyphTint: Theme.Palette.inkSoft, identifier: "feedbackQueuedRetry")
        case .idle, .sending, .consentRequired:
            EmptyView()
        }
    }

    /// The consent refusal stays with the full form (a refusal is not an
    /// outcome): the warn line names the toggle to enable, its next step (hard
    /// rule 7), sitting directly above the Send button it refers to.
    @ViewBuilder
    private var refusalLine: some View {
        if model.state == .consentRequired {
            statusText(L10n.feedbackConsentRequired, identifier: "feedbackConsentRequired",
                       color: Theme.Palette.warn)
        }
    }

    private func outcomeCard(_ text: String, glyph: String, glyphTint: Color,
                             identifier: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: glyph)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(glyphTint)
                .accessibilityHidden(true)
            Text(text)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.Palette.ink)
                .lineSpacing(1.3)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(identifier)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Palette.dash, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card)
            .stroke(Theme.Palette.hairline, lineWidth: 1))
    }

    private func statusText(_ text: String, identifier: String, color: Color) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(color)
            .lineSpacing(1.3)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier(identifier)
    }

    private var footnote: some View {
        Text(L10n.feedbackFootnote)
            .font(.caption2)
            .foregroundStyle(Theme.Palette.inkSoft.opacity(0.7))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, 2)
    }
}

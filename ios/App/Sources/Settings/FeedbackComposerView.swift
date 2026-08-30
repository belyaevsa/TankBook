import SwiftUI
import TankbookCore

/// The About screen's "Tell us" composer (PJ.20, design/screens/About.dc.html,
/// docs/ERRORS.md -> About & feedback). The send-feedback row posts to
/// `POST /feedback` through the core `FeedbackOutbox`, with queued-offline and
/// 429 states that each name their next step and survive being ignored.
///
/// The consent is the load-bearing part: "Help improve scanning - attach this
/// case" defaults OFF, persists, and is changeable afterwards (hard rule 13);
/// a case is queued only with consent. The device model rides only with its own
/// toggle, per the contract.
struct FeedbackComposerView: View {
    @Bindable var model: FeedbackModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionEyebrow("Tell us")
            categoryChips
            textEditor
            deviceModelToggle
            replyField
            consentToggle
            sendButton
            statusLine
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

    // MARK: - Status and footnote

    /// The outcome line. Each state names its next step and survives being
    /// ignored (hard rule 7, docs/ERRORS.md -> About & feedback).
    @ViewBuilder
    private var statusLine: some View {
        switch model.state {
        case .sent:
            statusText(L10n.feedbackSent, identifier: "feedbackSent", color: Theme.Palette.inkSoft)
        case .queuedOffline:
            statusText(L10n.feedbackQueuedOffline, identifier: "feedbackQueuedOffline",
                       color: Theme.Palette.inkSoft)
        case .queuedRateLimited:
            statusText(L10n.feedbackRateLimited, identifier: "feedbackRateLimited",
                       color: Theme.Palette.inkSoft)
        case .queuedRetry:
            statusText(L10n.feedbackQueuedRetry, identifier: "feedbackQueuedRetry",
                       color: Theme.Palette.inkSoft)
        case .consentRequired:
            statusText(L10n.feedbackConsentRequired, identifier: "feedbackConsentRequired",
                       color: Theme.Palette.warn)
        case .idle, .sending:
            EmptyView()
        }
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

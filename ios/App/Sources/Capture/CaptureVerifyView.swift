import SwiftUI
import TankbookCore

/// The capture verify step: the photo, upright and zoomable, with the numbers
/// recognised from it underneath, so the user checks each one against the
/// paper or the display before anything reaches the entry. What the app could
/// not read, or read with doubt, is said here, above the fields - the entry
/// form that follows does not repeat it (docs/ERRORS.md -> Capture verify).
///
/// "Continue" copies the three numbers into the entry as the user left them.
/// The fields are editable from the first frame, recognition or not, so this
/// screen is itself the typed door (hard rule 15) and carries no separate
/// "Type it": that would open the same entry minus the photo. Every field here
/// and on the entry stays editable (hard rule 13).
struct CaptureVerifyView: View {
    @Bindable var session: CaptureVerifySession
    let onContinue: () -> Void
    let onRetake: () -> Void

    @FocusState private var focus: ManualFillUpMath.Field?

    var body: some View {
        ZStack {
            Theme.Palette.midnight.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                ZoomablePhoto(image: session.image, rotationDegrees: session.rotationDegrees,
                              onTurn: { session.userTurns += 1 })
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
                    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card)
                        .stroke(Theme.Palette.hairline, lineWidth: 1))
                    .frame(maxHeight: typing ? Self.typingPhotoHeight : .infinity)
                    .padding(.horizontal, Theme.Spacing.screenMargin)
                if !typing { notices }
                fields
                if !typing { actions }
            }
            .padding(.bottom, typing ? 8 : 0)
            .animation(.easeOut(duration: 0.2), value: typing)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("captureVerifyScreen")
    }

    /// While a field is being typed in, the decimal pad takes the lower half
    /// of the screen: the subtitle, the notices and the actions step aside and
    /// the photo takes a fixed height, so the title, the photo and all three
    /// fields fit above the keyboard without relying on the system shrinking
    /// the photo. "Done" puts the keyboard away (the decimal pad has no return
    /// key) and brings the rest back.
    private var typing: Bool { focus != nil }

    /// The photo's height while typing: sized so title, photo and the three
    /// fields fit above the decimal pad on a 390 x 844 pt phone.
    static let typingPhotoHeight: CGFloat = 180

    private var header: some View {
        VStack(spacing: 4) {
            Text("Check the numbers")
                .font(.headline)
                .foregroundStyle(Theme.Palette.ink)
                .frame(maxWidth: .infinity)
                .overlay(alignment: .trailing) {
                    if typing {
                        Button("Done") { focus = nil }
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Theme.Palette.taillight)
                            .frame(minHeight: 44)
                            .accessibilityIdentifier("captureVerifyDoneButton")
                    }
                }
            if !typing {
                Text("Compare them with the photo and correct any that are wrong.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.Palette.inkSoft)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, Theme.Spacing.screenMargin)
        .padding(.top, typing ? 4 : 14)
        .padding(.bottom, typing ? 4 : 10)
    }

    // MARK: Notices

    @ViewBuilder
    private var notices: some View {
        let list = session.notices
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(list.enumerated()), id: \.offset) { _, notice in
                    noticeLine(notice)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Spacing.screenMargin)
            .padding(.top, 10)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("captureVerifyNotices")
        }
    }

    /// Admissions are a quiet hint (nothing went wrong that the user must fix
    /// before going on); doubts about a reading are amber attention, the words
    /// carrying the meaning (hard rule 5).
    @ViewBuilder
    private func noticeLine(_ notice: CaptureVerifyNotice) -> some View {
        switch notice {
        case .pumpNothingRead:
            hint("Couldn't read the pump display – type the numbers from it, the photo stays attached.",
                 identifier: "captureVerifyNothingRead")
        case .nothingRead:
            hint("Couldn't read this one – type it, the photo stays attached.",
                 identifier: "captureVerifyNothingRead")
        case .pumpAlpha:
            warn(Text(L10n.pumpDisplayAlphaMessage), identifier: "captureVerifyPumpAlpha")
        case .pumpPriceDiffers(let shown, let implied):
            PumpReadingCautionNotice(caution: .shownPriceDiffers(shown: shown, implied: implied))
                .padding(.horizontal, -16)
                .accessibilityIdentifier("captureVerifyPriceDiffers")
        case .numbersDisagree:
            warn(Text("These numbers don't multiply up – check them against the photo."),
                 identifier: "captureVerifyDisagree")
        }
    }

    private func hint(_ text: LocalizedStringKey, identifier: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(Theme.Palette.inkSoft)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier(identifier)
    }

    private func warn(_ text: Text, identifier: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(Theme.Palette.warn)
            text
                .font(.footnote)
                .foregroundStyle(Theme.Palette.warn)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }

    // MARK: Fields

    private var fields: some View {
        VStack(spacing: 0) {
            fieldRow(.total, label: L10n.localize("Total"))
            Divider().overlay(Theme.Palette.hairline)
            fieldRow(.volume, label: ManualFillUpUnitCopy.volumeLabel(for: session.volumeUnit))
            Divider().overlay(Theme.Palette.hairline)
            fieldRow(.unitPrice, label: ManualFillUpUnitCopy.priceLabel(for: session.volumeUnit))
        }
        .background(Theme.Palette.dash)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card).stroke(Theme.Palette.hairline, lineWidth: 1))
        .padding(.horizontal, Theme.Spacing.screenMargin)
        .padding(.top, 12)
    }

    private func fieldRow(_ field: ManualFillUpMath.Field, label: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(Theme.Palette.inkSoft)
                .fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: 8)
            TextField("", text: Binding(get: { session.form.text(field) },
                                        set: { session.form.set(field, to: $0) }))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.custom(AppFonts.dinAlternateBold, size: 24))
                .monospacedDigit()
                .foregroundStyle(Theme.Palette.ink)
                .focused($focus, equals: field)
                .fieldUnderline(isFocused: focus == field, warn: false)
                .overlay(alignment: .trailing) {
                    // Where the number will land, so the wait reads as "this field is coming".
                    if session.reading, session.form.text(field).isEmpty {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel(Text("Reading"))
                    }
                }
                .accessibilityIdentifier(identifier(field))
        }
        .padding(.horizontal, Theme.Spacing.cardPadding)
        .padding(.vertical, 8)
    }

    private func identifier(_ field: ManualFillUpMath.Field) -> String {
        switch field {
        case .total: "captureVerifyTotalField"
        case .volume: "captureVerifyVolumeField"
        case .unitPrice: "captureVerifyPriceField"
        }
    }

    // MARK: Actions

    private var actions: some View {
        VStack(spacing: 10) {
            Button { session.afterRecognition(onContinue) } label: {
                HStack(spacing: 8) {
                    if session.continuePending { ProgressView().controlSize(.small) }
                    Text("Continue")
                }
                    .font(.body.weight(.bold))
                    .foregroundStyle(Theme.Palette.midnight)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Theme.Palette.taillight)
                    .clipShape(RoundedRectangle(cornerRadius: 15))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("captureVerifyContinueButton")
            secondary("Re-take", identifier: "captureVerifyRetakeButton", action: onRetake)
        }
        .padding(.horizontal, Theme.Spacing.screenMargin)
        .padding(.top, 12)
        .padding(.bottom, 16)
    }

    private func secondary(_ label: LocalizedStringKey, identifier: String,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.Palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(Theme.Palette.dash)
                .clipShape(RoundedRectangle(cornerRadius: 15))
                .overlay(RoundedRectangle(cornerRadius: 15).stroke(Theme.Palette.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }
}

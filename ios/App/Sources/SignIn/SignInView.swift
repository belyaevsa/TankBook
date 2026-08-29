import SwiftUI
import TankbookCore

/// The sign-in sheet's root: owns the `SignInFlow` and switches between the
/// choose-provider, wrong-provider and restoring phases within the one sheet
/// presentation (no nested presentations, no dead ends - SCREENMAP rule zero).
struct SignInFlowHost: View {
    @State private var flow = SignInFlow.makeDefault()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            switch flow.phase {
            case .choosing, .signingIn:
                SignInView(flow: flow)
            case .wrongProvider(let provider):
                WrongProviderView(flow: flow, provider: provider)
            case .restoring(let snapshot):
                RestoringView(flow: flow, snapshot: snapshot)
            case .emptyRestore:
                EmptyRestoreView(flow: flow)
            case .restoreUnreachable:
                RestoreUnreachableView(flow: flow)
            case .uploading:
                // Transient - `onFinished` dismisses immediately (the push itself
                // is P4.5; nothing blocks the user here, hard rule 1).
                Color.clear
            }
        }
        .background(Theme.Palette.midnight)
        // The artboard has no navigation bar - just "Not now" top-right - so the
        // sheet chrome (the "Sign in" inline title and the X close button that
        // `SheetDestinationView`/`DiscardAwareSheet` add) is hidden. "Not now"
        // and swipe-down are the dismiss paths, exactly as the artboard shows.
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            flow.onFinished = { dismiss() }
            flow.applyScenarioIfRequested()
        }
    }
}

/// The Sign in sheet (design/screens/SignIn.dc.html): two providers, three
/// privacy reassurances, and the warn-amber "pick one and keep it" notice at the
/// decision moment (docs/JOURNEYS.md J11a -> the wrong-provider trap). A "Not
/// now" escape and the footer state the hard rule 1 guarantee - the app works
/// fully without an account.
struct SignInView: View {
    let flow: SignInFlow
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 24) {
                    iconRow
                    titleBlock
                    providerButtons
                    reassurances
                    amberNotice
                }
                .padding(.horizontal, 30)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            footer
        }
        .background(Theme.Palette.midnight)
    }

    private var header: some View {
        HStack {
            Spacer()
            Button {
                dismiss()
            } label: {
                Text("Not now")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.Palette.inkSoft)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("signInNotNowButton")
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    private var iconRow: some View {
        HStack(spacing: 18) {
            gaugeBox
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.Palette.inkSoft)
            gaugeBox
                .frame(width: 70, height: 52)
        }
    }

    private var gaugeBox: some View {
        Image(systemName: "fuelpump.fill")
            .font(.system(size: 20))
            .foregroundStyle(Theme.Palette.taillight)
            .frame(width: 54, height: 88)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Theme.Palette.dash)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Theme.Palette.hairline, lineWidth: 2)
            )
    }

    private var titleBlock: some View {
        VStack(spacing: 8) {
            Text("One garage, every device")
                .font(.title.bold())
                .foregroundStyle(Theme.Palette.ink)
                .multilineTextAlignment(.center)
            Text("Sign in and your cars, history and photos follow you – to a new phone, an iPad, or Android one day.")
                .font(.subheadline)
                .foregroundStyle(Theme.Palette.inkSoft)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
        }
    }

    private var providerButtons: some View {
        VStack(spacing: 11) {
            providerButton(provider: .apple, identifier: "signInAppleButton")
            providerButton(provider: .google, identifier: "signInGoogleButton")
        }
    }

    private func providerButton(provider: AuthProvider, identifier: String) -> some View {
        let isSigningIn = flow.phase == .signingIn(provider)
        return Button {
            flow.startSignIn(provider: provider)
        } label: {
            HStack(spacing: 9) {
                if isSigningIn {
                    ProgressView()
                        .controlSize(.small)
                        .tint(provider == .apple ? Theme.Palette.midnight : Theme.Palette.ink)
                } else {
                    providerMark(provider)
                }
                Text(provider == .apple ? "Sign in with Apple" : "Continue with Google")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(provider == .apple ? Theme.Palette.midnight : Theme.Palette.ink)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(provider == .apple ? Color.white : Theme.Palette.dash)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(provider == .apple ? Color.clear : Theme.Palette.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isSigningIn || isOtherProviderSigningIn(provider))
        .accessibilityIdentifier(identifier)
    }

    private func isOtherProviderSigningIn(_ provider: AuthProvider) -> Bool {
        if case .signingIn(let signing) = flow.phase { return signing != provider }
        return false
    }

    @ViewBuilder
    private func providerMark(_ provider: AuthProvider) -> some View {
        if provider == .apple {
            Image(systemName: "apple.logo")
                .font(.system(size: 17))
                .foregroundStyle(Theme.Palette.midnight)
        } else {
            Text(verbatim: "G")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Theme.Palette.ink)
        }
    }

    private var reassurances: some View {
        VStack(alignment: .leading, spacing: 12) {
            reassurance("Your log so far comes with you – nothing on this phone is lost or replaced.")
            reassurance("We store your email and your synced entries – no ads, no analytics on your data, delete everything anytime.")
            reassurance("With Apple you can hide your email – the private relay address works fine as your account.")
        }
    }

    private func reassurance(_ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.Palette.inkSoft)
                .padding(.top, 2)
            Text(text)
                .font(.caption)
                .foregroundStyle(Theme.Palette.inkSoft)
                .lineSpacing(1.5)
        }
    }

    private var amberNotice: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 15))
                .foregroundStyle(Theme.Palette.warn)
                .padding(.top, 1)
            (Text("Pick one and keep it.").bold()
                + Text(verbatim: " ")
                + Text("Apple and Google create separate accounts – use the same one on every device to see the same garage."))
                .font(.caption)
                .foregroundStyle(Theme.Palette.ink)
                .lineSpacing(1.5)
        }
        .padding(14)
        .background(Theme.Palette.warn.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 13))
        .overlay(
            RoundedRectangle(cornerRadius: 13)
                .stroke(Theme.Palette.warn.opacity(0.3), lineWidth: 1)
        )
        .accessibilityIdentifier("signInAmberNotice")
    }

    private var footer: some View {
        VStack(spacing: 8) {
            if let error = flow.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.warn)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("signInErrorText")
            }
            Text("The app works fully without an account – this only adds sync.")
                .font(.caption2)
                .foregroundStyle(Theme.Palette.inkSoft.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 30)
        .padding(.bottom, 24)
    }
}

/// The J11a wrong-provider state (docs/JOURNEYS.md J11a -> "never show an empty
/// garage as if their data were gone"): the honest question with a one-tap
/// provider switch, and a sign-out escape that leaves the local app intact.
struct WrongProviderView: View {
    let flow: SignInFlow
    let provider: AuthProvider
    @Environment(\.dismiss) private var dismiss

    private var otherProvider: AuthProvider { provider == .apple ? .google : .apple }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Text("Not now")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.Palette.inkSoft)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("signInNotNowButton")
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)

            Spacer()

            VStack(spacing: 18) {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 44))
                    .foregroundStyle(Theme.Palette.warn)

                Text(L10n.wrongProviderQuestion(signedInWith: provider, switchTo: otherProvider))
                    .font(.body)
                    .foregroundStyle(Theme.Palette.ink)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .accessibilityIdentifier("wrongProviderQuestion")

                Button {
                    flow.switchProvider(from: provider)
                } label: {
                    Text(L10n.switchProvider(otherProvider))
                        .font(.body.weight(.bold))
                        .foregroundStyle(Theme.Palette.midnight)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(Theme.Palette.taillight)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("wrongProviderSwitchButton")

                Button {
                    flow.signOutLocally()
                    dismiss()
                } label: {
                    Text("Sign out")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.Palette.inkSoft)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("wrongProviderSignOutButton")
            }
            .padding(.horizontal, 30)

            Spacer()
            Spacer()
        }
        .background(Theme.Palette.midnight)
    }
}

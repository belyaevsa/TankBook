import SwiftUI
import TankbookCore

/// The Welcome root (design/screens/Welcome.dc.html + LightWelcome.dc.html):
/// the first-launch screen shown only with no vehicle AND no session
/// (docs/SCREENMAP.md -> Welcome). One screen, skippable in the sense that its
/// three paths are the whole screen - add a car, import history, or restore an
/// existing account - and it never reappears once a car exists.
///
/// Hard rule 15 applies: two of the three paths are entry doors (Add your car,
/// Import from another app). Neither is framed as the lesser one - both are
/// full-width one-tap buttons of equal standing, and the taillight fill on
/// "Add your car" is the artboard's hierarchy, not a claim that the other door
/// is a fallback. A reinstall or an Android migrant is never funnelled into
/// "Add your car" as if they were new: the restore line offers their account.
///
/// RV.23 re-argued the screen without adding one (docs/JOURNEYS.md J1 - "every
/// extra onboarding screen loses users"). Three things changed:
/// - the third promise no longer argues AGAINST an account ("No account needed")
///   before the user knows what one costs them. It is two-sided now: the data
///   stays on the phone (hard rule 1, still true and still a reason people pick
///   this app) AND an account adds something.
/// - sign-in is a **peer door** - a full-width button beside the other two, with
///   the benefit that is hardest to guess right under it. Cloud receipt reading
///   leads because it changes what the app can *do*: `/extract` is bearer-only,
///   so a guest gets on-device Vision (38.3% of receipts) and a signed-in user
///   gets the cloud model (84/96, P4.12). All four benefits are free (RV.4);
///   nothing here is monetization copy (hard rule 7).
/// - "Add your car" stays the peer it was: it continues with no account, first
///   in the stack and in taillight. A user who never signs in has chosen
///   correctly, so nothing on this screen calls that the lesser path.
///
/// The restore line is a **separate** door from the peer sign-in button, and
/// that separation is load-bearing: it is the only thing that still says "I am
/// returning", and it is what carries `arrivedViaRestore` into the sign-in
/// sheet (docs/JOURNEYS.md J11a). The peer button must NOT carry it - a brand
/// new account is empty because it is new, and asking that user "did you sign
/// in with Google last time?" is confusing and faintly alarming.
struct WelcomeView: View {
    let onAddCar: () -> Void
    let onImport: () -> Void
    /// The general-purpose door: no restore intent (docs/JOURNEYS.md J11a).
    let onSignIn: () -> Void
    /// The returning user's door: carries the restore intent.
    let onRestore: () -> Void

    var body: some View {
        ZStack {
            Theme.Palette.midnight.ignoresSafeArea()
            glow
            VStack(spacing: 0) {
                heroSection
                    .frame(maxHeight: .infinity)
                featuresSection
                    .frame(maxHeight: .infinity)
                actionsSection
                    .padding(.horizontal, 26)
                    .padding(.bottom, 40)
            }
        }
    }

    /// The taillight radial glow the artboard draws behind the logo block - the
    /// app's one moment of accent light on the brand screen.
    private var glow: some View {
        GeometryReader { geometry in
            Circle()
                .fill(RadialGradient(
                    colors: [Theme.Palette.taillight.opacity(0.14), .clear],
                    center: .center, startRadius: 0, endRadius: 210))
                .frame(width: 420, height: 420)
                .position(x: geometry.size.width / 2, y: -40)
        }
        .allowsHitTesting(false)
    }

    // MARK: - Hero (logo + wordmark)

    private var heroSection: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            VStack(spacing: 18) {
                WelcomeLogoMark()
                VStack(spacing: 6) {
                    Text("Tankbook")
                        .font(.system(size: 40, weight: .heavy))
                        .tracking(-0.4)
                        .foregroundStyle(Theme.Palette.ink)
                    Text("Fuel, charging and service – one log")
                        .font(.system(size: 16))
                        .tracking(0.3)
                        .foregroundStyle(Theme.Palette.inkSoft)
                }
            }
            .padding(.horizontal, 32)
        }
    }

    // MARK: - The three promises

    private var featuresSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            featureRow("camera", "Scan receipts and pump displays")
            featureRow("keyboard", "Type it or scan it – seconds either way")
            featureRow("checkmark.shield", "Your data stays on your phone – an account adds cloud features")
        }
        .padding(.horizontal, 44)
    }

    private func featureRow(_ systemImage: String, _ text: LocalizedStringKey) -> some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 20))
                .foregroundStyle(Theme.Palette.inkSoft)
                .frame(width: 24)
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(Theme.Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - The doors (three peers + the returning user's line)

    private var actionsSection: some View {
        VStack(spacing: 12) {
            Button(action: onAddCar) {
                Text("Add your car")
                    .font(.system(size: 16, weight: .bold))
                    // `midnight`, not white: the P6.19 guards (enforced by
                    // `PaletteAccentGuardTests`) require 4.5:1 on every accent
                    // fill in both themes, and white on taillight measures 3.47:1
                    // in dark. `midnight` is the app's primary-CTA text token
                    // everywhere else (Add car save, Restoring open garage).
                    .foregroundStyle(Theme.Palette.midnight)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 17)
                    .background(Theme.Palette.taillight)
                    .clipShape(RoundedRectangle(cornerRadius: 15))
                    .shadow(color: Theme.Palette.taillight.opacity(0.3), radius: 18, y: 4)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("welcomeAddCarButton")

            Button(action: onImport) {
                Text("Import from another app")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.Palette.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Theme.Palette.dash)
                    .clipShape(RoundedRectangle(cornerRadius: 15))
                    .overlay(
                        RoundedRectangle(cornerRadius: 15)
                            .stroke(Theme.Palette.ink.opacity(0.18), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("welcomeImportButton")

            Button(action: onSignIn) {
                VStack(spacing: 3) {
                    Text("Sign in to Tankbook")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.Palette.ink)
                    // The benefit right at the decision, in the user's terms.
                    // Cloud receipt reading first (it changes what the app can
                    // do, not where the data lives); all of it is free.
                    Text("Smart receipt scanning, backups and sync with your other devices")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.Palette.inkSoft)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Theme.Palette.dash)
                .clipShape(RoundedRectangle(cornerRadius: 15))
                .overlay(
                    RoundedRectangle(cornerRadius: 15)
                        .stroke(Theme.Palette.ink.opacity(0.18), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("welcomeSignInButton")

            // The returning user's door (docs/JOURNEYS.md J11): one full
            // localised phrase per language, never concatenated - the P1.4 bug
            // rendered this line's RU as the noun "Вход" standing where a verb
            // belongs (hard rule 10).
            Button(action: onRestore) {
                Text("Already use Tankbook? Restore your garage.")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.Palette.action)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("welcomeRestoreButton")
        }
    }
}

/// The brand mark (Welcome.dc.html's 92x92 tile): the pump outline in
/// taillight with the scan-succeeded checkmark in `action`. The artboard drew
/// the checkmark in the pre-action-token cyan (headlight); the design rule that
/// `headlight` means *electric* (docs/DESIGN.md, enforced by
/// `PaletteAccentGuardTests`) makes `action` the legal interactive colour, and
/// the checkmark is a "done" mark, not an electric charge.

/// The brand mark: the app icon itself (`design/brand/README.md` - a fuel nozzle
/// and a charging plug face to face, framed), as the light/dark `BrandMark`
/// image set. Welcome shows the same picture the user tapped on the home
/// screen; nothing here is drawn by hand any more (P6.22, 2026-08-30).
private struct WelcomeLogoMark: View {
    var body: some View {
        Image("BrandMark")
            .resizable()
            .interpolation(.high)
            .frame(width: 92, height: 92)
            .clipShape(RoundedRectangle(cornerRadius: 21, style: .continuous))
            .shadow(color: .black.opacity(0.4), radius: 20, y: 8)
            .accessibilityHidden(true)
    }
}

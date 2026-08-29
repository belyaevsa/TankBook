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
/// "Add your car" as if they were new: the third path offers their account.
struct WelcomeView: View {
    let onAddCar: () -> Void
    let onImport: () -> Void
    let onSignIn: () -> Void

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
                    Text("Point. Scan. Done.")
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
            featureRow("camera", "Scan receipts, pump displays and QR codes")
            featureRow("fuelpump", "Fuel, charging and service in one history")
            featureRow("checkmark.shield", "No account needed – your data stays yours")
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

    // MARK: - The three paths

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
                (Text("Already use Tankbook? ")
                    + Text("Sign in").bold().foregroundStyle(Theme.Palette.action)
                    + Text(" – your garage follows you."))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.Palette.inkSoft)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("welcomeSignInButton")
        }
    }
}

/// The brand mark (Welcome.dc.html's 92x92 tile): the pump outline in
/// taillight with the scan-succeeded checkmark in `action`. The artboard drew
/// the checkmark in the pre-action-token cyan (headlight); the design rule that
/// `headlight` means *electric* (docs/DESIGN.md, enforced by
/// `PaletteAccentGuardTests`) makes `action` the legal interactive colour, and
/// the checkmark is a "done" mark, not an electric charge.
private struct WelcomeLogoMark: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 26)
                .fill(Theme.Palette.dash)
                .overlay(
                    RoundedRectangle(cornerRadius: 26)
                        .stroke(Theme.Palette.ink.opacity(0.18), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.4), radius: 20, y: 8)
            pumpPaths
                .frame(width: 52, height: 52)
        }
        .frame(width: 92, height: 92)
    }

    private var pumpPaths: some View {
        ZStack {
            // The pump body outline (Welcome.dc.html's logo SVG, viewBox 52x52).
            Path { path in
                path.move(to: CGPoint(x: 14, y: 42))
                path.addLine(to: CGPoint(x: 14, y: 18))
                path.addQuadCurve(to: CGPoint(x: 18, y: 14), control: CGPoint(x: 14, y: 14))
                path.addLine(to: CGPoint(x: 28, y: 14))
                path.addQuadCurve(to: CGPoint(x: 32, y: 18), control: CGPoint(x: 32, y: 14))
                path.addLine(to: CGPoint(x: 32, y: 42))
            }
            .stroke(Theme.Palette.taillight,
                    style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            // The nozzle.
            Path { path in
                path.move(to: CGPoint(x: 32, y: 20))
                path.addLine(to: CGPoint(x: 36, y: 20))
                path.addQuadCurve(to: CGPoint(x: 39, y: 23), control: CGPoint(x: 39, y: 20))
                path.addLine(to: CGPoint(x: 39, y: 33))
                path.addQuadCurve(to: CGPoint(x: 44, y: 33), control: CGPoint(x: 41.5, y: 35.5))
                path.addLine(to: CGPoint(x: 44, y: 24))
            }
            .stroke(Theme.Palette.taillight,
                    style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            // The pump base line.
            Path { path in
                path.move(to: CGPoint(x: 10, y: 42))
                path.addLine(to: CGPoint(x: 36, y: 42))
            }
            .stroke(Theme.Palette.taillight,
                    style: StrokeStyle(lineWidth: 3, lineCap: .round))
            // The window.
            Path { path in
                path.addRect(CGRect(x: 18, y: 16, width: 10, height: 8))
            }
            .stroke(Theme.Palette.taillight,
                    style: StrokeStyle(lineWidth: 2.4, lineJoin: .round))
            // The "done" checkmark.
            Path { path in
                path.move(to: CGPoint(x: 41, y: 17))
                path.addLine(to: CGPoint(x: 44, y: 20))
                path.addLine(to: CGPoint(x: 50, y: 13))
            }
            .stroke(Theme.Palette.action,
                    style: StrokeStyle(lineWidth: 2.8, lineCap: .round, lineJoin: .round))
        }
    }
}

import SwiftUI
import TankbookCore
import UIKit

/// RV.5 - the capture review step: what was shot, shown before anything is
/// read from it.
///
/// Reported from a device walk: the shutter fired and the flow moved straight
/// on with nothing shown, so the user could neither see the frame nor refuse
/// it. This screen is the missing beat between the shutter (or the Photos
/// pick) and the Confirm sheet, and it answers exactly one question: **can you
/// read the total on this photo?** Everything else - cropping, rotation,
/// filters, multi-page - is deliberately absent; one image, accept or shoot
/// again.
///
/// **Why a `fullScreenCover` and not a `.sheet`** (the one design note the
/// brief asks for): a page sheet on an iPhone loses the top of the screen to
/// the presenting card and to its own grabber, and a thermal receipt is a tall
/// narrow strip - the very shape that suffers most from a shortened frame. The
/// question this screen exists to answer is legibility, so it takes the whole
/// screen.
///
/// **Why the pipeline has not run yet.** `CapturePipeline.process` is Vision
/// OCR plus QR detection over a full-resolution image - cheap-ish, not free.
/// The review is therefore shown on the RAW image the moment it exists and the
/// pipeline runs only when the user taps "Use this", so a re-take costs no OCR
/// at all and the photo appears with no wait.
///
/// Hard rule 15: the three actions are **peers**. "Use this" is the primary
/// because it is the one the user came for, but "Type it" sits beside
/// "Re-take" at equal weight and its copy never says typing is what you do
/// when the photo is bad.
struct CaptureReviewView: View {
    let image: UIImage
    let onUse: () -> Void
    let onRetake: () -> Void
    let onTypeIt: () -> Void

    var body: some View {
        ZStack {
            Theme.Palette.midnight.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                photo
                actions
            }
        }
        // NOT an `.accessibilityIdentifier` on the container: an identifier on
        // a plain container propagates to every descendant and OVERRIDES the
        // children's own, so each button came back as "captureReviewScreen"
        // and no query for a specific action could match. `children: .contain`
        // keeps the children addressable.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("captureReviewScreen")
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text("Check the photo")
                .font(.headline)
                .foregroundStyle(Theme.Palette.ink)
            Text("Can you read the total on it?")
                .font(.subheadline)
                .foregroundStyle(Theme.Palette.inkSoft)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, Theme.Spacing.screenMargin)
        .padding(.top, 18)
        .padding(.bottom, 14)
        .accessibilityIdentifier("captureReviewHeader")
    }

    /// Fitted, never cropped: a crop to a tidy card would hide the corner the
    /// total is printed in, which is the one thing the user is here to check.
    private var photo: some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card)
                    .stroke(Theme.Palette.hairline, lineWidth: 1)
            )
            .padding(.horizontal, Theme.Spacing.screenMargin)
            .accessibilityLabel("The photo to check")
            .accessibilityIdentifier("captureReviewImage")
    }

    private var actions: some View {
        VStack(spacing: 12) {
            Button(action: onUse) {
                Text("Use this")
                    .font(.body.weight(.bold))
                    .foregroundStyle(Theme.Palette.midnight)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Theme.Palette.taillight)
                    .clipShape(RoundedRectangle(cornerRadius: 15))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("captureReviewUseButton")

            // Two peers on one row, each half the width: neither is the
            // consolation prize for the other (hard rule 15).
            HStack(spacing: 12) {
                secondary("Re-take",
                          identifier: "captureReviewRetakeButton",
                          action: onRetake)
                secondary("Type it",
                          identifier: "captureReviewTypeItButton",
                          action: onTypeIt)
            }
        }
        .padding(.horizontal, Theme.Spacing.screenMargin)
        .padding(.top, 18)
        .padding(.bottom, 24)
    }

    private func secondary(_ label: LocalizedStringKey,
                           identifier: String,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.Palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(Theme.Palette.dash)
                .clipShape(RoundedRectangle(cornerRadius: 15))
                .overlay(
                    RoundedRectangle(cornerRadius: 15)
                        .stroke(Theme.Palette.hairline, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }
}

/// The image under review, wrapped so `.fullScreenCover(item:)` can drive it.
/// `UIImage` is neither `Identifiable` nor `Equatable`, and a fresh id per
/// capture is exactly right: shooting again is a new review, not the same one.
struct CaptureReviewSubject: Identifiable {
    let id = UUID()
    let image: UIImage
}

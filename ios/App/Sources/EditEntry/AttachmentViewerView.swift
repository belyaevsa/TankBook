import PDFKit
import SwiftUI
import TankbookCore
import UIKit

/// The attachment viewer (RV.9) - the full-size look at the receipt the entry
/// exists to evidence. Reached by tapping the receipt strip's photo chip in
/// Edit entry, presented as a sheet so it carries BOTH dismissal paths the
/// docs/SCREENMAP.md convention asks for: swipe-down with a drag indicator and
/// a visible Close control.
///
/// Four states, and the last three are the whole point (docs/ERRORS.md ->
/// Edit entry):
/// 1. the full rendition is on this device - zoomable, pannable, fitted on
///    entry (`ZoomableImageView`);
/// 2. it is not local but a fetch is possible - the inline thumbnail renders
///    from the first frame while `LazyBlobFetcher` downloads and verifies it;
/// 3. it is not local and no fetch is possible (signed out, offline, the fetch
///    failed) - the thumbnail stays, the copy says so plainly and names the
///    next step (hard rule 7). Nothing here gates the entry (hard rule 1);
/// 4. the attachment is a PDF - rendered by PDFKit, which brings its own zoom
///    and paging. Unreadable bytes get an explicit state, never a blank frame.
///
/// Never logs a byte, a station or an amount - ids and operation names only
/// (hard rule 12).
struct AttachmentViewerView: View {
    let attachment: Attachment

    @Environment(\.dismiss) private var dismiss
    @State private var state: ViewerState = .loading

    /// What the viewer is showing right now.
    enum ViewerState: Equatable {
        /// Reading the local cache; the thumbnail is already on screen.
        case loading
        /// Downloading the full rendition; the thumbnail is on screen.
        case fetching
        /// The verified full rendition.
        case full(Data)
        /// No full rendition, and none is coming right now.
        case unavailable(AttachmentUnavailableReason)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Palette.midnight.ignoresSafeArea()
                content
            }
            .navigationTitle(Text("Receipt photo"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(Theme.Palette.action)
                        .accessibilityIdentifier("attachmentViewerCloseButton")
                }
            }
        }
        .presentationDragIndicator(.visible)
        .task { await load() }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .full(let data):
            fullRendition(data)
        case .loading, .fetching:
            pendingContent(message: nil)
        case .unavailable(let reason):
            pendingContent(message: reason)
        }
    }

    /// State 1 and 4: the verified bytes. A photo goes into the zoomable scroll
    /// view; a PDF goes into `PDFView`, which handles zoom and paging itself.
    /// Bytes that are neither render the honest unreadable state rather than an
    /// empty frame.
    @ViewBuilder
    private func fullRendition(_ data: Data) -> some View {
        if attachment.kind == .pdf {
            if let document = PDFDocument(data: data) {
                AttachmentPDFView(document: document)
                    .ignoresSafeArea(edges: .bottom)
                    .accessibilityIdentifier("attachmentViewerPDF")
            } else {
                pendingContent(message: .unreadable)
            }
        } else if let image = UIImage(data: data) {
            VStack(spacing: 0) {
                ZoomableImageView(image: image)
                    .accessibilityIdentifier("attachmentViewerImage")
                zoomHint
            }
        } else {
            pendingContent(message: .unreadable)
        }
    }

    /// States 2 and 3: the inline thumbnail (already in the payload, so
    /// something is on screen from the first frame) with, once the fetch has
    /// settled, the line that says what happened and what to do next.
    private func pendingContent(message: AttachmentUnavailableReason?) -> some View {
        VStack(spacing: 20) {
            Spacer(minLength: 0)
            thumbnailPreview
            if let message {
                unavailableCard(message)
            } else {
                ProgressView()
                    .controlSize(.regular)
                    .tint(Theme.Palette.inkSoft)
                    .accessibilityIdentifier("attachmentViewerProgress")
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Spacing.screenMargin)
    }

    /// The blown-up inline thumbnail. It is small and soft - honestly so: this
    /// is the low-resolution copy that travels inside the record payload, and
    /// pretending otherwise would be the lie the "not downloaded" copy exists
    /// to avoid.
    @ViewBuilder
    private var thumbnailPreview: some View {
        if let image = thumbnailImage {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 240, maxHeight: 320)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
                .accessibilityIdentifier("attachmentViewerThumbnail")
        } else {
            RoundedRectangle(cornerRadius: Theme.Radius.card)
                .fill(Theme.Palette.dash)
                .frame(width: 180, height: 240)
                .overlay(
                    Image(systemName: attachment.kind == .pdf ? "doc.text" : "photo")
                        .font(.title)
                        .foregroundStyle(Theme.Palette.inkSoft)
                )
                .accessibilityIdentifier("attachmentViewerThumbnail")
        }
    }

    /// State 3's card: what is missing, and the next step (hard rule 7). Each
    /// language carries a full phrase - never a composed one (the P1.4 bug).
    private func unavailableCard(_ reason: AttachmentUnavailableReason) -> some View {
        VStack(spacing: 8) {
            Text(Self.headline(for: reason))
                .accessibilityIdentifier("attachmentViewerHeadline")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.Palette.ink)
                .multilineTextAlignment(.center)
            Text(Self.nextStep(for: reason))
                .accessibilityIdentifier("attachmentViewerNextStep")
                .font(.footnote)
                .foregroundStyle(Theme.Palette.inkSoft)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if reason == .failed {
                Button("Try again") { Task { await load(force: true) } }
                    .buttonStyle(.plain)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.Palette.action)
                    .accessibilityIdentifier("attachmentViewerRetryButton")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(Theme.Palette.dash.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card)
                .stroke(Theme.Palette.hairline, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("attachmentViewerUnavailable")
    }

    private var zoomHint: some View {
        Text("Pinch or double-tap to zoom")
            .font(.caption)
            .foregroundStyle(Theme.Palette.inkSoft)
            .padding(.vertical, 10)
            .accessibilityIdentifier("attachmentViewerZoomHint")
    }

    private static func headline(for reason: AttachmentUnavailableReason) -> String {
        switch reason {
        case .signedOut, .failed: L10n.localize("The full photo is not on this device yet")
        case .unreadable: L10n.localize("This file could not be opened")
        }
    }

    private static func nextStep(for reason: AttachmentUnavailableReason) -> String {
        switch reason {
        case .signedOut:
            L10n.localize("Sign in from Settings to download the original. This preview came with the entry.")
        case .failed:
            L10n.localize("Check your connection and tap Try again. This preview came with the entry.")
        case .unreadable:
            L10n.localize("Attach the receipt again from the entry to replace it.")
        }
    }

    private var thumbnailImage: UIImage? {
        guard let base64 = attachment.thumbnailBase64,
              let data = Data(base64Encoded: base64) else { return nil }
        return UIImage(data: data)
    }

    // MARK: - Loading

    /// Local first (`BlobService.localData`) - network-free and synchronous, so
    /// the on-device case never shows a spinner. Otherwise the shared
    /// `LazyBlobFetcher` does the fetch, with its verify-on-download: unverified
    /// bytes are never cached and never displayed (docs/SYNC.md -> Delivery).
    /// A guest has no fetcher at all, which is state 3, not a crash.
    private func load(force: Bool = false) async {
        if !force, case .full = state { return }
        if let local = BlobService.localData(for: attachment) {
            state = .full(local)
            return
        }
        guard let fetcher = SyncService.makeBlobFetcher(sessionStore: KeychainSessionStore()) else {
            state = .unavailable(.signedOut)
            return
        }
        state = .fetching
        do {
            let data = try await fetcher.fetch(sha256: attachment.file.sha256)
            state = .full(data)
        } catch {
            // Shape only: the operation and the error - never the sha256, the
            // bytes or anything visible in the photo (hard rule 12).
            AppLog.error(operation: "attachmentViewer.fetch", category: .ui, error: error)
            state = .unavailable(.failed)
        }
    }
}

/// A `UIScrollView` around the photo: pinch to zoom, drag to pan, double-tap to
/// toggle between fitted and 3x. Fitted on entry, which is what "open the
/// receipt" means before the user asks for more.
struct ZoomableImageView: UIViewRepresentable {
    let image: UIImage

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 6
        scrollView.bouncesZoom = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.backgroundColor = .clear

        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: scrollView.frameLayoutGuide.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: scrollView.frameLayoutGuide.bottomAnchor),
            imageView.widthAnchor.constraint(equalTo: scrollView.contentLayoutGuide.widthAnchor),
            imageView.heightAnchor.constraint(equalTo: scrollView.contentLayoutGuide.heightAnchor)
        ])
        context.coordinator.imageView = imageView

        let doubleTap = UITapGestureRecognizer(target: context.coordinator,
                                               action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)
        return scrollView
    }

    func updateUIView(_ uiView: UIScrollView, context: Context) {
        context.coordinator.imageView?.image = image
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var imageView: UIImageView?

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

        @objc func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
            guard let scrollView = recognizer.view as? UIScrollView else { return }
            if scrollView.zoomScale > scrollView.minimumZoomScale {
                scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
            } else {
                let point = recognizer.location(in: imageView)
                let size = scrollView.bounds.size
                let side = CGSize(width: size.width / 3, height: size.height / 3)
                scrollView.zoom(to: CGRect(x: point.x - side.width / 2,
                                           y: point.y - side.height / 2,
                                           width: side.width, height: side.height),
                                animated: true)
            }
        }
    }
}

/// PDFKit's own viewer. Service invoices are stored as PDFs byte-identical
/// (docs/SCHEMA.md), and an image view handed PDF bytes shows nothing - so the
/// PDF gets the renderer that reads it, with zoom and paging included.
struct AttachmentPDFView: UIViewRepresentable {
    let document: PDFDocument

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.document = document
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        if uiView.document !== document { uiView.document = document }
    }
}

/// Why the full rendition is not on screen (docs/ERRORS.md -> Edit entry, the
/// RV.9 rows). Each case owns a headline and a next step - never a dead end.
enum AttachmentUnavailableReason: Equatable {
    /// No account on this device, so there is nothing to fetch from.
    case signedOut
    /// The fetch failed - offline, or the bytes did not verify.
    case failed
    /// The bytes are here but are not a photo / not a readable PDF.
    case unreadable
}

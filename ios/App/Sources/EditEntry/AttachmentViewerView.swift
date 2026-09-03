import PDFKit
import SwiftUI
import TankbookCore
import UIKit

/// The attachment viewer (RV.9, extended by RV.17) - the full-size look at the
/// receipt the entry exists to evidence. Reached by tapping the receipt strip's
/// photo chip in Edit entry, presented as a sheet so it carries BOTH dismissal
/// paths the docs/SCREENMAP.md convention asks for: swipe-down with a drag
/// indicator and a visible Close control.
///
/// Four rendition states, and the last three are the whole point
/// (docs/ERRORS.md -> Edit entry):
/// 1. the full rendition is on this device - zoomable, pannable, fitted on
///    entry (`ZoomableImageView`);
/// 2. it is not local but a fetch is possible - the inline thumbnail renders
///    from the first frame while `LazyBlobFetcher` downloads and verifies it
///    (RV.17: the wait is a visible `ProgressView`, degrading to a static
///    hourglass under Reduce Motion - RV.8's precedent);
/// 3. it is not local and no fetch is possible (signed out, offline, the fetch
///    failed) - the thumbnail stays, the copy says so plainly and names the
///    next step (hard rule 7). Nothing here gates the entry (hard rule 1);
/// 4. the attachment is a PDF - rendered by PDFKit, which brings its own zoom
///    and paging. Unreadable bytes get an explicit state, never a blank frame.
///
/// RV.17 adds two surfaces on top of RV.9:
/// - the recognised data (`Attachment.ocrText`, `extractedTimestamp`) as a
///   second page beside the photo, reachable by swiping - present only when the
///   attachment carries anything, absent rather than empty otherwise. This is
///   presentation of stored data; the viewer never re-runs OCR (hard rule 13).
/// - a Share affordance that hands the FULL rendition to the system share sheet
///   (save-to-Photos, share, save-to-Files), offered only once `.full` is
///   reached - a share sheet over a 44 pt thumbnail is worse than none.
///
/// Never logs a byte, a station or an amount - ids and operation names only;
/// the share is logged shape-only (that it happened and its outcome, never what
/// was shared, its hash or its size) (hard rule 12).
///
/// RV.37 adds the two mutating surfaces on top: Delete (tombstone + unlink,
/// system-confirmed) and Replace (a new attachment plus a tombstone for the old,
/// never an in-place mutation). Replace then ASKS whether to re-read the new
/// photo and update the entry - "Leave it as it is" is the default, and even an
/// accepted re-read fills blank fields only (hard rule 13). The entry is passed
/// in so the viewer can unlink/relink it, and the parent is told through
/// `onAttachmentChanged` so it can refresh the receipt strip and, on an accepted
/// re-read, apply the blank-field suggestions to the form.
struct AttachmentViewerView: View {
    let attachment: Attachment
    let entry: any Entry
    var onAttachmentChanged: (FuelExtraction?) -> Void = { _ in }

    @Environment(\.dismiss) var dismiss
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @State private var state: ViewerState = .loading
    @State private var shareable: AttachmentShareable?
    @State private var page = 0

    // RV.37: the attachment the entry links RIGHT NOW. It starts at the one the
    // viewer opened and advances to each replacement, so "Use a different
    // receipt" replaces the fresh attachment - never the already-tombstoned
    // original. Internal (not private) so AttachmentViewerActions.swift, the
    // extension that holds the delete/replace handlers, can reach them.
    @State var currentID: AttachmentID?
    @State var showDeleteConfirm = false
    @State var showReplaceSource = false
    @State var showReplaceAsk = false
    @State var replaceExtraction: FuelExtraction?
    @State var replaceFailed = false
    @State var replaceProcessing = false

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
            .safeAreaInset(edge: .bottom) { actionBar }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 20) {
                        // Share is offered only once the full rendition is
                        // local: a share sheet over the 44 pt thumbnail is worse
                        // than no share sheet. The on-demand fetch that makes it
                        // local is `load()` below (docs/SYNC.md -> Delivery).
                        if fullData != nil {
                            Button("Share") { presentShare() }
                                .foregroundStyle(Theme.Palette.action)
                                .accessibilityIdentifier("attachmentViewerShareButton")
                        }
                        Button("Close") { dismiss() }
                            .foregroundStyle(Theme.Palette.action)
                            .accessibilityIdentifier("attachmentViewerCloseButton")
                    }
                }
            }
        }
        .presentationDragIndicator(.visible)
        .task { await load() }
        .onAppear {
            #if DEBUG
            // Screenshot seam: simctl cannot swipe, so the recognised-page
            // capture opens the pager on the second page directly.
            if ProcessInfo.processInfo.arguments.contains("-openAttachmentViewerRecognised") {
                page = 1
            }
            #endif
        }
        .task {
            #if DEBUG
            // Screenshot seam: simctl cannot drive the replace flow (source
            // chooser, then OCR), so the RV.37 ask capture opens the ask
            // directly over the viewer. Delayed a beat so the sheet is fully
            // presented before the dialog tries to present over it.
            if ProcessInfo.processInfo.arguments.contains("-openAttachmentViewerReplaceAsk") {
                try? await Task.sleep(nanoseconds: 600_000_000)
                showReplaceAsk = true
            }
            #endif
        }
        .sheet(item: $shareable) { item in
            ActivityView(items: item.items) { completed in
                // Shape only: that the share ended and how - never what was
                // shared, its hash or its size (hard rule 12).
                AppLog.info(operation: "attachmentViewer.share", category: .ui,
                            outcome: completed ? "completed" : "cancelled")
            }
        }
        .alert("Delete this receipt?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) { performDelete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The receipt is removed from this entry.")
        }
        .confirmationDialog("Re-read this and update the entry?",
                            isPresented: $showReplaceAsk,
                            titleVisibility: .visible) {
            // "Leave it as it is" is the DEFAULT answer (hard rule 13): the
            // photo is swapped either way, but the entry's values change only
            // if the user actively picks "Update entry" - and even then, blank
            // fields only. It is a plain button, not `.cancel`, because SwiftUI
            // drops a `.cancel`-role button from a titled confirmationDialog on
            // iOS (leaving the ask with no visible default) - and tapping
            // outside the dialog still dismisses it, which is the same no-op.
            Button("Leave it as it is") {
                onAttachmentChanged(nil)
                dismiss()
            }
            Button("Update entry") {
                onAttachmentChanged(replaceExtraction)
                dismiss()
            }
            Button("Use a different receipt") {
                showReplaceSource = true
            }
        }
        // Without this the dialog inherits TabRoots' ambient taillight tint and
        // reads as a destructive action sheet, though nothing here destroys data.
        .tint(Theme.Palette.action)
        .receiptAttachSource(isPresented: $showReplaceSource,
                             title: "Replace photo") { image in
            handleReplace(image)
        }
    }

    /// The photo (or PDF) page, plus - when the attachment carries recognised
    /// data - a second page beside it (the product owner's "just an additional
    /// photo"). The pager exists only when there is something to page to, so
    /// the recognised surface is absent rather than empty when there is nothing
    /// (hard rule 13, and the RV.17 check).
    @ViewBuilder
    private var content: some View {
        if hasRecognisedData {
            TabView(selection: $page) {
                photoContent
                    .tag(0)
                AttachmentRecognisedView(ocrText: attachment.ocrText,
                                         extractedTimestamp: attachment.extractedTimestamp)
                    .tag(1)
            }
            .tabViewStyle(.page(indexDisplayMode: .automatic))
        } else {
            photoContent
        }
    }

    @ViewBuilder
    private var photoContent: some View {
        switch state {
        case .full(let data):
            fullRendition(data)
        case .loading:
            pendingContent(message: nil, downloading: false)
        case .fetching:
            pendingContent(message: nil, downloading: true)
        case .unavailable(let reason):
            pendingContent(message: reason, downloading: false)
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
                    .accessibilityIdentifier("attachmentViewerPDF")
            } else {
                pendingContent(message: .unreadable, downloading: false)
            }
        } else if let image = UIImage(data: data) {
            VStack(spacing: 0) {
                ZoomableImageView(image: image)
                    .accessibilityIdentifier("attachmentViewerImage")
                zoomHint
            }
        } else {
            pendingContent(message: .unreadable, downloading: false)
        }
    }

    /// States 2 and 3: the inline thumbnail (already in the payload, so
    /// something is on screen from the first frame) with, once the fetch has
    /// settled, the line that says what happened and what to do next. While the
    /// fetch runs the indicator is a system `ProgressView` - the wait must look
    /// like work (RV.8's reasoning, unchanged) - degrading to a static hourglass
    /// under Reduce Motion.
    private func pendingContent(message: AttachmentUnavailableReason?, downloading: Bool) -> some View {
        VStack(spacing: 20) {
            Spacer(minLength: 0)
            thumbnailPreview
            if let message {
                unavailableCard(message)
            } else {
                downloadIndicator
                if downloading {
                    Text("Downloading the full photo…")
                        .font(.footnote)
                        .foregroundStyle(Theme.Palette.inkSoft)
                        .accessibilityIdentifier("attachmentViewerDownloading")
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Spacing.screenMargin)
    }

    /// The moving part of the fetch. A system `ProgressView` (the same small
    /// spinner the rest of the app uses); under Reduce Motion it degrades to a
    /// static hourglass, matching `GatewayReadingBanner` (RV.8) - the
    /// accessibility floor is non-negotiable and the "Downloading..." line
    /// carries the meaning on its own.
    @ViewBuilder
    private var downloadIndicator: some View {
        if reduceMotion {
            Image(systemName: "hourglass.bottomhalf.filled")
                .font(.title3)
                .foregroundStyle(Theme.Palette.inkSoft)
                .accessibilityIdentifier("attachmentViewerProgress")
        } else {
            ProgressView()
                .controlSize(.regular)
                .tint(Theme.Palette.inkSoft)
                .accessibilityIdentifier("attachmentViewerProgress")
        }
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
            // RV.17: with a recognised-data page the system page dots sit at the
            // bottom and would cover this hint; lift it clear of them. The
            // non-paged viewer is unchanged.
            .padding(.bottom, hasRecognisedData ? 24 : 0)
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

    // MARK: - Recognised data (RV.17)

    /// Whether the attachment carries anything recognised to show. Both signals
    /// are stored fields (`ocrText`, `extractedTimestamp`); neither requires a
    /// fetch, so the recognised page is reachable while the photo is still
    /// downloading.
    private var hasRecognisedData: Bool {
        if let ocr = attachment.ocrText,
           !ocr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        return attachment.extractedTimestamp != nil
    }

    // MARK: - Share (RV.17)

    /// The verified full rendition's bytes, or nil until the fetch lands. The
    /// share affordance keys off this - `nil` means the thumbnail is all there
    /// is, and a share sheet over a thumbnail is a bug that looks like a feature.
    private var fullData: Data? {
        if case .full(let data) = state { return data }
        return nil
    }

    private var reduceMotion: Bool {
        accessibilityReduceMotion || ProcessInfo.processInfo.arguments.contains("-forceReduceMotion")
    }

    /// Hands the full rendition to the system share sheet. The share itself is
    /// the user's deliberate act (docs/SECURITY.md's signed-off line: sharing
    /// exports a domain value by choice, which is fine) - the log records only
    /// that it happened and its outcome, never what was shared.
    private func presentShare() {
        guard let data = fullData else { return }
        AppLog.info(operation: "attachmentViewer.share", category: .ui, outcome: "presented")
        shareable = AttachmentShareable(items: shareItems(from: data))
    }

    /// The share-sheet payload. A photo shares the `UIImage` (so "Save Image"
    /// and the usual image targets appear); a PDF shares a temporary file with
    /// the right extension. A photo that will not decode falls back to its
    /// bytes rather than a dead sheet.
    private func shareItems(from data: Data) -> [Any] {
        if attachment.kind == .pdf {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("receipt-\(attachment.id.uuidString).pdf")
            try? data.write(to: url, options: .atomic)
            return [url]
        }
        if let image = UIImage(data: data) { return [image] }
        return [data]
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

/// The share-sheet payload, wrapped so the `.sheet(item:)` that presents it has
/// a stable identity (the items themselves are not Identifiable). RV.17.
private struct AttachmentShareable: Identifiable {
    let id = UUID()
    let items: [Any]
}

import PDFKit
import SwiftUI
import UIKit

/// The UIKit-bridged renderers the attachment viewer (RV.9) uses to draw the
/// full rendition. Split from `AttachmentViewerView.swift` at the real seam -
/// these are presentation-only representables, free of the viewer's state.

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
        // RV.17: bounces off. When the image is fitted (zoomScale 1) there is
        // nothing to scroll, and an elastic scroll view would consume the
        // horizontal pan the pager needs to reach the recognised-data page -
        // so a bouncy fitted photo would make "swipe to the next page" a dead
        // gesture. Zooming in restores panning, which is unaffected.
        scrollView.bounces = false
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

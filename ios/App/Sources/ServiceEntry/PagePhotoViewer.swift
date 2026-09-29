import SwiftUI
import TankbookCore
import UIKit

/// A page the form holds, full size, before the entry is saved (RV.332,
/// RV.333): the service form's invoice pages and the expense form's receipt.
/// Zoom, pan and turn come from `ZoomablePhoto`; "‹ ›" step between pages the
/// same way the saved entry's viewer does (`AttachmentViewerView`). Read-only -
/// a page is removed from the strip, where it was added.
struct PagePhotoViewer: View {
    let images: [UIImage]
    @State var index: Int
    @State private var turns = 0
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let page = images[min(index, images.count - 1)]
        NavigationStack {
            ZStack {
                Theme.Palette.midnight.ignoresSafeArea()
                ZoomablePhoto(image: page, rotationDegrees: Double((turns % 4) * 90),
                              onTurn: { turns += 1 })
                    .id(index)
                    .padding(Theme.Spacing.screenMargin)
            }
            .navigationTitle(images.count > 1 ? Text(L10n.pageOf(current: index + 1, total: images.count))
                                              : Text("Receipt photo"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if images.count > 1 {
                    ToolbarItem(placement: .topBarLeading) {
                        HStack(spacing: 18) {
                            Button {
                                turns = 0
                                index -= 1
                            } label: {
                                Image(systemName: "chevron.left")
                            }
                            .disabled(index == 0)
                            .accessibilityLabel(Text("Previous page"))
                            .accessibilityIdentifier("pageViewerPrevious")
                            Button {
                                turns = 0
                                index += 1
                            } label: {
                                Image(systemName: "chevron.right")
                            }
                            .disabled(index >= images.count - 1)
                            .accessibilityLabel(Text("Next page"))
                            .accessibilityIdentifier("pageViewerNext")
                        }
                        .foregroundStyle(Theme.Palette.action)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(Theme.Palette.action)
                        .accessibilityIdentifier("pageViewerClose")
                }
            }
        }
        .presentationDragIndicator(.visible)
        .accessibilityIdentifier("pageViewer")
    }
}

/// Which page a strip opened in `PagePhotoViewer`.
struct PageViewerTarget: Identifiable {
    let index: Int
    var id: Int { index }
}

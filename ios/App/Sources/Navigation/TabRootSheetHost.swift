import SwiftUI
import TankbookCore

/// One tab root's modal presentation host. Owning the route sheet, the capture
/// full-screen cover and the RV.77 reminder-offer sheet in ONE ZStack keeps the
/// presentations on a single view (no ancestor/descendant sheet races) and lets
/// the offer appear over whatever surface the user returned to once the entry
/// sheet is gone.
///
/// The offer is staged by a service/expense save (`ReminderOfferSession`) and
/// promoted here in the route sheet's `onDismiss` - only ever after the sheet
/// that saved is fully gone, never mid-save, never over the sheet that saved.
struct TabRootSheetHost<Root: View, SheetContent: View>: View {
    @Binding var sheet: SheetRoute?
    @Binding var modal: ModalRoute?
    @Environment(ReminderOfferSession.self) private var offerSession
    @ViewBuilder var root: () -> Root
    @ViewBuilder var sheetContent: (SheetRoute) -> SheetContent

    var body: some View {
        ZStack {
            root()
                .sheet(item: $sheet,
                       onDismiss: { offerSession.promote() },
                       content: { route in
                    // Clear a stale staged offer the moment a NEW sheet is
                    // presented: an offer is only the successor of the save
                    // that staged it (RV.77).
                    sheetContent(route)
                        .onAppear { offerSession.clearStale() }
                })
                .fullScreenCover(item: $modal,
                                 onDismiss: { offerSession.promote() },
                                 content: { route in
                    ModalDestinationView(route: route) {
                        modal = nil
                        sheet = .serviceEntry
                    }
                })
        }
        .sheet(item: offerBinding) { target in
            ServiceReminderOfferSheet(proposal: target.proposal)
        }
    }

    /// Binds the presented offer onto the session, so a Create / Not-this-time /
    /// swipe dismissal clears it for the next save.
    private var offerBinding: Binding<ServiceReminderOfferTarget?> {
        Binding(get: { offerSession.presented },
                set: { offerSession.presented = $0 })
    }
}

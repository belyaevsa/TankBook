import Foundation
import Observation
import TankbookCore

/// Carries the just-scanned invoice pre-fill from the Capture flow into the
/// ServiceEntry sheet (P3.1b). Capture processes the scanned pages and writes
/// the result here; ServiceEntry reads it on load. A single in-memory hand-off
/// - the pre-fill is default input the user edits (hard rule 13), never a
/// second screen, so nothing is persisted until the user saves.
@MainActor
@Observable
final class ServiceInvoiceSession {
    var pendingPrefill: ServiceEntryPrefill?
}

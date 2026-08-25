import SwiftUI

/// The typed navigation graph (docs/SCREENMAP.md). Adding a screen means adding
/// a case here and filling the corresponding placeholder body - no rewiring.
/// The presentation kind is encoded in the type: `Route` is pushed onto a
/// tab's `NavigationStack`, `SheetRoute` is presented as a sheet, `ModalRoute`
/// as a full-screen cover.

/// A destination pushed onto a tab's own navigation stack (back chevron +
/// edge-swipe; back never discards saved data).
enum Route: Hashable {
    case settings
    case about
    case reminders
    /// The reminder form. `nil` = create a new reminder (the list's "New
    /// reminder"); otherwise the reminder being edited/rescheduled.
    case reminderForm(UUID?)
    case recentlyDeleted
    /// The entry being edited. `nil` = "no specific entry" (a placeholder link
    /// or a debug-launch screenshot): the screen falls back to the most recent
    /// entry of the default vehicle.
    case editEntry(UUID?)
    /// The vehicle being edited. `nil` = "the selected car" (a placeholder link
    /// or a debug-launch screenshot): the screen falls back to the selected
    /// vehicle. Reached from Garage, the Car switcher's archived row and the
    /// limit sheet's "Archive a car".
    case vehicleDetail(UUID?)
    case addVehicle
    case accountDevices
    case paywall
    case importWizard

    /// Navigation title, resolved through the String Catalog (EN + RU).
    var title: LocalizedStringKey {
        switch self {
        case .settings: "Settings"
        case .about: "About"
        case .reminders: "Reminders"
        case .reminderForm: "Reminder form"
        case .recentlyDeleted: "Recently deleted"
        case .editEntry: "Edit entry"
        case .vehicleDetail: "Vehicle"
        case .addVehicle: "Add car"
        case .accountDevices: "Account & devices"
        case .paywall: "Tankbook Pro"
        case .importWizard: "Import"
        }
    }
}

/// A destination presented as a sheet (drag handle, swipe-down, explicit close).
enum SheetRoute: String, Identifiable {
    case carSwitcher
    case tankLevel
    case reminderComplete
    case signIn
    case confirmManual
    case serviceEntry
    case expenseEntry
    case partsShelf

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .carSwitcher: "My garage"
        case .tankLevel: "Tank level"
        case .reminderComplete: "Reminder complete"
        case .signIn: "Sign in"
        case .confirmManual: "Manual fill-up"
        case .serviceEntry: "Service & expenses"
        case .expenseEntry: "Expense"
        case .partsShelf: "Parts shelf"
        }
    }

    /// SCREENMAP navigation rule 1: a sheet with unsaved typed input asks
    /// before discarding; a sheet with only scanned data discards silently.
    var discardPolicy: DiscardPolicy {
        switch self {
        case .confirmManual, .serviceEntry, .expenseEntry: .askBeforeDiscarding
        case .carSwitcher, .tankLevel, .reminderComplete, .signIn, .partsShelf: .discardSilently
        }
    }
}

/// A full-screen modal destination (capture/camera; P2.1).
enum ModalRoute: String, Identifiable {
    case capture

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .capture: "Capture"
        }
    }
}

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
    /// RV.75: the merged "all cars" Reminders screen
    /// (design/screens/RemindersAll.dc.html) - every active car's live
    /// reminders in one list, each row naming its car. Reached today only by
    /// the DEBUG `-presentScreen remindersAll` hook; its permanent entry points
    /// are RV.76's Home row, RV.79's Garage count and RV.74's notification deep
    /// link (docs/SCREENMAP.md -> "Reminders across cars").
    case remindersAll
    /// PJ.5: the notification-tap deep link - Reminders with the tapped
    /// reminder's completion sheet surfaced. Distinct from `.reminders` (which
    /// is the plain list from the Home banner / Vehicle detail) so a tap's
    /// destination cannot be confused with a navigation link's. RV.74 will move
    /// this landing to `.remindersAll` where a deep link cannot be the wrong car.
    case reminderDeepLink(UUID)
    /// The reminder form. `reminderID != nil` = the reminder being
    /// edited/rescheduled. `reminderID == nil` = create; `vehicleID` is then the
    /// car the opener named ("New reminder" on a car's own Reminders list),
    /// or `nil` when no car was named - the merged list's "New reminder" opens
    /// with the car field EMPTY and Save inert until one is picked (hard rule
    /// 13, docs/SCREENMAP.md: "the car as its first field").
    case reminderForm(reminderID: UUID?, vehicleID: UUID?)
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
    /// The selected car's tire sets (P3.3), reached from Vehicle detail.
    case tireSets
    /// The tire-set name form. `nil` = create a new set (the list's "New tire
    /// set"); otherwise the set being renamed.
    case tireSetForm(UUID?)
    case addVehicle
    case accountDevices
    case paywall
    case importWizard
    /// The Log filtered to flagged entries (docs/SYNC.md -> Settings shows a
    /// count and a link only; resolution lives where the data lives). Reached
    /// from Settings' flagged row and, since RV.66, from the sync chip's whole
    /// body whenever the account-wide flagged count is non-zero.
    case flaggedEntries
    /// RV.38: the in-app notification inbox (the bell on the tab-root header) -
    /// work that finished after the user moved on, plus later reminders.
    case inbox

    /// Navigation title, resolved through the String Catalog (EN + RU).
    var title: LocalizedStringKey {
        switch self {
        case .settings: "Settings"
        case .about: "About"
        case .reminders: "Reminders"
        case .remindersAll: "Reminders"
        case .reminderDeepLink: "Reminders"
        case .reminderForm: "Reminder form"
        case .recentlyDeleted: "Recently deleted"
        case .editEntry: "Edit entry"
        case .vehicleDetail: "Vehicle"
        case .tireSets: "Tire sets"
        case .tireSetForm: "Tire set"
        case .addVehicle: "Add car"
        case .accountDevices: "Account & devices"
        case .paywall: "Tankbook Pro"
        case .importWizard: "Import"
        case .flaggedEntries: "Needs a look"
        case .inbox: "Inbox"
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

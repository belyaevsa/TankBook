import SwiftUI

/// Maps a pushed `Route` to its screen. Today every case renders a placeholder;
/// P1.2-P1.11 replace the placeholder bodies, not this wiring.
struct DestinationView: View {
    let route: Route

    var body: some View {
        content
            .navigationTitle(route.title)
            .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var content: some View {
        switch route {
        case .settings: SettingsContent()
        case .about: LeafContent()
        case .reminders: RemindersContent()
        case .reminderForm: LeafContent()
        case .recentlyDeleted: RecentlyDeletedContent()
        case .editEntry: LeafContent()
        case .vehicleDetail: VehicleDetailContent()
        case .addVehicle: AddVehicleView()
        case .accountDevices: LeafContent()
        case .paywall: LeafContent()
        case .importWizard: LeafContent()
        }
    }
}

/// Maps a `SheetRoute` to its sheet, wrapped in the discard-aware chrome.
struct SheetDestinationView: View {
    let route: SheetRoute
    @State private var hasUnsavedChanges = false

    var body: some View {
        DiscardAwareSheet(policy: route.discardPolicy, hasUnsavedChanges: $hasUnsavedChanges) {
            sheetContent
                .navigationTitle(route.title)
                .navigationBarTitleDisplayMode(.inline)
        }
    }

    @ViewBuilder
    private var sheetContent: some View {
        switch route {
        case .confirmManual: ManualFillUpView(hasUnsavedChanges: $hasUnsavedChanges)
        case .carSwitcher, .tankLevel, .reminderComplete, .signIn: SheetPlaceholderContent()
        case .serviceEntry: ServiceEntryContent(hasUnsavedChanges: $hasUnsavedChanges)
        }
    }
}

/// Maps a `ModalRoute` to its full-screen cover. Capture arrives with P2.1.
struct ModalDestinationView: View {
    let route: ModalRoute
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Color.clear
                .navigationTitle(route.title)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .accessibilityLabel("Close")
                        .accessibilityIdentifier("captureCloseButton")
                    }
                }
        }
    }
}

// MARK: - Placeholder content (P1.2-P1.11 replace these)

/// A placeholder leaf: a titled screen with no forward exit yet (its forward
/// exits - Save, Delete, rate, send feedback - arrive with its real screen).
/// Every pushed screen still has a back path, so it is never a dead end.
struct LeafContent: View {
    var body: some View {
        Color.clear
    }
}

private struct SettingsContent: View {
    var body: some View {
        List {
            NavigationLink("About", value: Route.about)
                .accessibilityIdentifier("aboutButton")

            NavigationLink("Recently deleted", value: Route.recentlyDeleted)
                .accessibilityIdentifier("recentlyDeletedButton")
        }
    }
}

private struct RecentlyDeletedContent: View {
    var body: some View {
        List {
            NavigationLink("Compare / Restore", value: Route.editEntry)
                .accessibilityIdentifier("compareRestoreButton")
        }
    }
}

private struct VehicleDetailContent: View {
    var body: some View {
        List {
            NavigationLink("Reminders", value: Route.reminders)
                .accessibilityIdentifier("remindersButton")
        }
    }
}

private struct RemindersContent: View {
    var body: some View {
        List {
            NavigationLink("New reminder", value: Route.reminderForm)
                .accessibilityIdentifier("newReminderButton")
        }
    }
}

private struct SheetPlaceholderContent: View {
    var body: some View {
        Color.clear
    }
}

/// Service & expenses placeholder (P3.1) - typed input, same dirty rule.
private struct ServiceEntryContent: View {
    @Binding var hasUnsavedChanges: Bool
    @State private var note = ""

    var body: some View {
        Form {
            TextField("Amount", text: $note)
                .accessibilityIdentifier("serviceNoteField")
                .onChange(of: note) { _, newValue in
                    hasUnsavedChanges = !newValue.isEmpty
                }
        }
    }
}

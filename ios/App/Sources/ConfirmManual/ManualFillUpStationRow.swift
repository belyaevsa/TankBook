import SwiftUI
import TankbookCore

// MARK: - Station row (shared by ConfirmManual and Edit entry)

/// The entry's Station row (docs/JOURNEYS.md -> J4). Shared by the ConfirmManual
/// sheet (ManualFillUpView) and Edit entry (EditEntryView), so the field behaves
/// identically in both - one order across both screens, P1.6's muscle-memory
/// rule. The row is a default input (hard rule 13): the suggestion picks a
/// station, the user changes it in one tap, and a picked station is theirs.
///
/// RV.156: the row is interactive in BOTH states - a station set is
/// user-creatable, so an empty set is a "nothing picked yet", never a "nothing
/// possible". With stations it is the pick menu plus an "Add station" entry at
/// its end (a user with one station must be able to add a second); with none it
/// offers the add door directly, never the dead `Not set` label that promised
/// nothing while PJ.19's location suggestion - which RANKS existing stations and
/// creates none - was the only door planned (docs/JOURNEYS.md -> J4). Creating a
/// station goes through `TankbookRepository.createStation`, the shared
/// deterministic minting rule, and the created station is selected on this entry
/// (the add is never a dead end in slow motion).
struct ManualFillUpStationRow: View {
    /// The account's live stations. A binding so a station created from this
    /// row joins the list the menu shows without a reload (both owners hold the
    /// array in `@State`).
    @Binding var stations: [Station]
    @Binding var selection: Station?
    /// PJ.19: called when the USER picks a station - the moment that makes the
    /// pick theirs (hard rule 13), so no later suggestion pass may move it.
    var onChose: () -> Void = {}

    @State private var isAddingStation = false
    @State private var newStationName = ""

    /// A chosen station's name is runtime data; the placeholder is copy.
    /// Coalescing them into one `String` sends the literal through
    /// `Text(_: String)`, which does not localise - see the note atop `L10n.swift`.
    @ViewBuilder
    private func stationLabel(_ selection: Station?) -> some View {
        if let name = selection?.name {
            Text(name)
        } else {
            Text("Choose station")
        }
    }

    var body: some View {
        HStack {
            Text("Station")
                .font(.subheadline)
                .foregroundStyle(Theme.Palette.inkSoft)
            Spacer(minLength: 8)
            if stations.isEmpty {
                addStationButton
            } else {
                stationMenu
            }
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 4)
        .alert("Add station", isPresented: $isAddingStation) {
            TextField("Station name", text: $newStationName)
                .accessibilityIdentifier("addStationNameField")
            Button("Cancel", role: .cancel) { newStationName = "" }
            Button("Add") { submitNewStation() }
        }
    }

    /// The add door for an empty set: one direct action in the action colour,
    /// since there is no menu to hang the same affordance on - the empty row is
    /// never the dead label it used to be (RV.156).
    private var addStationButton: some View {
        Button {
            beginAddingStation()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "plus")
                    .font(.caption.weight(.bold))
                Text("Add station")
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(Theme.Palette.action)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("manualFillUpAddStationButton")
    }

    /// The populated-set control: the pick menu, with "Add station" as its last
    /// entry - a user with one station can always add a second (RV.156's named
    /// trap is offering the door only in the empty state).
    private var stationMenu: some View {
        Menu {
            ForEach(stations, id: \.id) { station in
                Button {
                    selection = station
                    onChose()
                } label: {
                    Text(station.name)
                }
            }
            Divider()
            Button {
                beginAddingStation()
            } label: {
                Label("Add station", systemImage: "plus")
            }
            .accessibilityIdentifier("manualFillUpAddStationMenuItem")
        } label: {
            HStack(spacing: 4) {
                // Same coalesced-String trap: a station's name is runtime data,
                // the fallback is copy. Coalescing makes the whole expression a
                // String and the fallback renders its English key. Split so the
                // literal reaches the LocalizedStringKey overload.
                stationLabel(selection)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.Palette.action)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(Theme.Palette.inkSoft)
            }
        }
        .accessibilityIdentifier("manualFillUpStationButton")
    }

    private func beginAddingStation() {
        newStationName = ""
        isAddingStation = true
    }

    /// Creates the named station through the repository's shared deterministic
    /// rule and selects it on the entry (RV.156: a created station is selected
    /// on the entry that created it - having to pick it again would be the add
    /// as a dead end in slow motion).
    ///
    /// An empty or whitespace-only name is a cancel: a station's row and its
    /// Log title live on the name, so an unnamed station is not creatable. A
    /// name that exactly matches an existing station resolves to THAT station -
    /// the shared rule never mints a second record (its `favorite`, `defaults`
    /// and `lastUsedAt` stay the existing row's), so the UI selecting it never
    /// looks like it created a duplicate (RV.115's merge is not forked here).
    private func submitNewStation() {
        let trimmed = newStationName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            isAddingStation = false
            return
        }
        do {
            let repository = try AppStore.repository()
            guard let station = try repository.createStation(named: trimmed) else {
                isAddingStation = false
                return
            }
            selection = station
            if !stations.contains(where: { $0.id == station.id }) {
                stations.append(station)
            }
            // The add selected a station: it is the user's own pick, so PJ.19's
            // ranking - which may still be resolving its location read - cannot
            // move it (hard rule 13).
            onChose()
            newStationName = ""
            isAddingStation = false
        } catch {
            // A failed local write keeps the dialog open with the name intact -
            // the user can retry or cancel (hard rule 7).
            AppLog.error(operation: "station.create", category: .ui, error: error)
        }
    }
}

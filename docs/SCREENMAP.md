# Tankbook – Screen Map

*The navigation graph: every screen, how it's reached, how it exits, and how you get back. Companion to `design/screens/` (the artboards), `JOURNEYS.md` (why each path exists), and `DESIGN.md` (layout rules). Rule zero: **no dead ends** – every screen has a back path and at least one forward exit; the audit at the bottom proves it.*

## Navigation conventions

0. **Version scope**: nodes and sections without a marker are v1; **[v2]** marks screens v1 does not ship (the Ask tab and its sheets, the Paywall). `CLAUDE.md` → Version scope.

1. **Three navigation kinds, three gestures:**
   - **Tab roots** (Log/Home, Trends, Garage) – no back button; switching tabs preserves each tab's stack. The three share ONE header treatment (RV.21): a one-row custom header – screen title + the Settings gear on the same line – drawn by the shared `TabRootHeader` (docs/DESIGN.md). RV.22 added the sync state chip beside the gear; **RV.38 added the inbox bell** between them, so the trailing corner now holds three 44 pt circular controls (chip · bell · gear) in one family – `dash` fill, hairline stroke, `.title3` glyph. Each root's gear pushes Settings onto that root's OWN stack, so back returns to the root that pushed it, never to a hardcoded tab.
   - **Tab roots reload on signals, not on reappearance.** The roots stay mounted across a switch (only visibility changes, `AppRootView`), so a root's `.task` fires once and never again for a tab the user returns to. Each root therefore reloads on the same three triggers – its first `.task`, a change to `carSelection.selectedID`, and a bump of `toastCenter.revision` – and every save that changes a tab root's data raises `noteEntryChanged()` (RV.25: a car added from the picker showed in Garage only after a relaunch because Add car raised no signal and Garage listened to none; a root with a `.task`-only load is a stale-list bug).
   - **Pushed screens** (Settings, About, Reminders, Recently deleted, Edit entry) – back chevron top-left + iOS edge-swipe. Back never discards saved data.
   - **Re-tapping the active tab returns that tab to its root** (RV.31): the standard iOS escape when the back chevron is not where the thumb is. It pops that tab's OWN `NavigationStack` path – immediate when the pushed top screen holds nothing unsaved; through the SAME "Keep editing / Discard" confirmation a sheet uses when a pushed Edit entry has unsaved edits, and Cancel leaves the entry open and unchanged (hard rule 8). A tap on a DIFFERENT tab is an ordinary switch and never pops. Each tab's dirty signal is its own, so a half-typed entry left open on one tab never makes re-tapping ANOTHER tab ask.
   - **Sheets** (Confirm variants, Car switcher, Tank level, Reminder complete, Sign in) – drag handle, swipe-down to dismiss, plus an explicit close/"Not now". A sheet with unsaved *typed* input asks before discarding ("Keep editing / Discard"); a sheet with only scanned data discards silently – the photo is never lost, it re-offers from the camera roll.
2. **Capture is modal full-screen** (camera): X closes back to wherever it was opened from, and so does a **successful save** – see "Saving inside capture" below. A save inside capture tears the modal down (RV.12); it does **not** switch tabs, so it lands wherever capture was opened from, with the new entry visible there (Home reloads on `noteEntryChanged`). The earlier wording here promised the **Log tab regardless of where capture started**; that cross-tab jump was never built, and RV.12 deliberately did not add it – a save that moves the user to a tab they did not choose is a second surprise on top of the one it fixes. Recorded here as the shape that ships; changing it is a product decision, not a bug fix.
3. **System surfaces** (photo viewer, share sheet for export, App Store rating, system delete-confirmation alerts) are leaves that return automatically – listed once here, not repeated below.

## The map

```mermaid
flowchart TD
    subgraph Onboarding
        Welcome -->|Add your car| AddVehicle
        Welcome -->|Import from another app| ImportWizard
        Welcome -->|Sign in to Tankbook| SignIn
        Welcome -->|Already use Tankbook? Restore your garage| SignIn
        SignIn -->|existing account| Restoring
        SignIn -->|new account, local log uploads| Home
        SignIn -.->|Not now| Welcome
        Restoring -->|Open my garage| Home
        Restoring -.->|Cancel = sign out| Welcome
        AddVehicle -->|Save first car| GuestHome
        AddVehicle -.->|X| Welcome
        ImportWizard -->|done| Home
        GuestHome -->|first capture| Capture
    end

    subgraph Tabs["Tab roots (no back)"]
        Home
        Trends
        Ask["Ask [v2] (Pro – docs/AGENT.md)"]
        Garage
    end

    Ask -->|draft reminder| ReminderForm
    Ask -->|draft service entry / invoice| ServiceEntry
    Ask -->|draft fill-up| ConfirmManual
    Ask -->|card: Open in Trends| Trends
    Ask -->|card: service row| EditEntry
    Ask -->|camera in composer| Capture
    Ask -.->|not Pro: example question| Trends
    Ask -.->|not Pro: Pro card| Paywall

    Home <-->|tab switch| Trends
    Home <-->|tab switch| Garage

    Home -->|gear| Settings
    Trends -->|gear| Settings
    Garage -->|gear| Settings
    Home -->|bell| Inbox
    Trends -->|bell| Inbox
    Garage -->|bell| Inbox
    Inbox -->|item → entry| EditEntry
    Inbox -.->|reminders (planned)| Reminders
    Home -->|car card / chip| CarSwitcher
    Home -->|reminder banner| Reminders
    Home -->|entry tap| EditEntry
    Home -->|duplicate / conflict card| EditEntry
    Home -->|"N entries excluded" footnote, N > 1| ExcludedEntries
    Trends -->|"N entries excluded" footnote, N > 1| ExcludedEntries
    ExcludedEntries -->|row| EditEntry

    subgraph CaptureFlow["Capture (modal)"]
        Capture -->|shutter / Photos| CaptureReview
        CaptureReview -.->|Re-take| Capture
        CaptureReview -->|Type it| ConfirmManual
        CaptureReview -->|Use this · auto: receipt| Confirm
        CaptureReview -->|Use this · auto: foreign currency| ConfirmForeign
        CaptureReview -->|Use this · auto: mixed receipt| ConfirmMixed
        CaptureReview -->|Use this · OCR declined to guess| ConfirmManual
        CaptureReview -->|Use this · Expense mode (RV.62)| ExpenseEntry
        Capture -->|Type it · Fill-up mode| ConfirmManual
        Capture -->|Type it · Service mode| ServiceEntry
        Capture -->|Type it · Expense mode| ExpenseEntry
        Capture -->|scan · Service mode| ServiceEntry
        Capture -.->|X| Back[return to opener]
        Confirm -->|tank row| TankLevel
        TankLevel -.->|Set / Skip| Confirm
        Confirm & ConfirmForeign & ConfirmMixed & ConfirmManual -->|Save| Home
        Confirm & ConfirmForeign & ConfirmMixed & ConfirmManual -.->|back| Capture
        ServiceEntry -->|Save| Home
        ServiceEntry -.->|X| Capture
        ExpenseEntry -->|Save| Home
        ExpenseEntry -.->|X| Capture
    end

    Home -->|capture button| Capture
    Trends -->|capture button| Capture
    Garage -->|capture button| Capture
    Home -->|"Type it" (primary, one tap)| ConfirmManual
    Home -->|"Type it" menu · Service| ServiceEntry
    Home -->|"Type it" menu · Expense| ExpenseEntry

    Garage -->|vehicle| VehicleDetail
    Garage -->|Add car| AddVehicle
    Garage -->|Stations door| Stations
    Stations -->|row| StationSettings
    Stations -.->|back| Garage
    StationSettings -.->|back| Stations
    StationSettings -->|Remove location (in place)| StationSettings
    VehicleDetail -.->|back| Garage
    VehicleDetail -->|Tire sets| TireSets
    VehicleDetail -->|Parts shelf [v1.x] PJ.25| PartsShelf
    VehicleDetail -->|Reminders| Reminders
    PartsShelf -.->|back| VehicleDetail
    ServiceEntry -->|View shelf| PartsShelf2[Parts shelf, nested sheet]
    TireSets -->|New tire set / row| TireSetForm
    TireSets -.->|back| VehicleDetail
    TireSetForm -->|Save| TireSets
    CarSwitcher -->|pick car| Home
    CarSwitcher -->|Add car| AddVehicle
    CarSwitcher -->|archived car| VehicleDetail
    CarSwitcher -.->|dismiss| Home
    AddVehicle -->|Save| Home
    AddVehicle -.->|X| Back2[return to opener]

    Home -->|"Reminders · N due" row [v1.1]| RemindersAll
    Garage -->|car row's attention count [v1.1]| RemindersAll
    RemindersAll -->|car chip: one car| Reminders
    RemindersAll -->|row| ReminderComplete
    RemindersAll -->|New reminder → pick a car| ReminderForm
    RemindersAll -.->|back| Back3b[return to opener]
    ServiceEntry -->|saved: offer the next one [v1.1]| ServiceReminderOffer
    ServiceReminderOffer -->|Create the reminder| Home
    ServiceReminderOffer -.->|Not this time| Home
    Notification3["Push action: Mark done [v1.1]"] --> ReminderComplete
    Notification4["Push action: Push a week [v1.1]"] --> Silent[no screen - rescheduled in place]
    Reminders -->|complete| ReminderComplete
    Reminders -->|New reminder| ReminderForm
    Reminders -.->|back| Back3[return to opener]
    ReminderComplete -->|Scan invoice / Type amount| ServiceEntry
    ReminderComplete -.->|Skip / dismiss| Reminders
    ReminderForm -->|Save| Reminders
    EditEntry -->|Save / Delete| Home
    EditEntry -.->|X| Back4[return to opener]
    EditEntry -->|receipt chip| AttachmentViewer
    AttachmentViewer -.->|Close / swipe-down| EditEntry

    Settings -->|account card, guest| SignIn
    Settings -->|account card, signed in| AccountDevices
    Settings -->|Language| LanguagePicker[Language picker (sheet)]
    Settings -->|Import| ImportWizard
    Settings -->|"2 entries need a look"| Log
    Settings -->|Recently deleted| RecentlyDeleted
    Settings -->|About| About
    Settings -.->|back| OpenerTabRoot[return to the tab root that pushed it]
    About -->|Attach diagnostics · opt-in on| DiagnosticsPreview[Diagnostics preview (sheet)]
    About -.->|back| Settings
    DiagnosticsPreview -.->|Close / swipe-down| About
    RecentlyDeleted -->|Restore| RecentlyDeleted   (row removed; an entry back in Log, a car row restoring the car and its entries)
    RecentlyDeleted -.->|back| Settings
    AccountDevices -.->|back| Settings
    ImportWizard -.->|back| Back5[return to opener]

    Notification[Push: reminder due] --> Reminders
    Notification2[Toast: synced, N need a look] --> Home
```

Dashed arrows = back/dismiss paths. `Back[return to opener]` = the screen is reachable from several places and back always returns to the specific opener (standard stack behavior), never to a hardcoded screen.

### The parts shelf door **[v1.x]** (PJ.25, 2026-09-09)

The shelf (P3.2, docs/JOURNEYS.md J7b) is **per-car**, decided here: the row lives on
Vehicle detail - a per-car screen - beside the other per-car rows (Tire sets, Reminders),
and the shelf's data is stored per-car (`partsOnShelf(forVehicle:)`, each part is an
`.parts` Expense with a `vehicleId`). An all-cars shelf would need a new query and a
screen that names every row's car; nothing in J7b or this map asks for one, and the
service-entry nested door is already per-car. So the pushed door carries the vehicle the
row belongs to, exactly as the row's siblings do.

**Two doors, one screen.** The nested "View shelf" sheet (P3.2, inside a service entry)
is unchanged; PJ.25 added the pushed row, and both render the SAME `PartsShelfView` -
never a second implementation. The Vehicle detail row is always present (like Tire sets,
unlike Reminders which RV.81 hides for an archived car): a car with nothing on the shelf
still reaches the shelf, whose own empty state says what the shelf is for and what to do
next (hard rule 7) instead of a blank list.

**Back path / discard conclusion.** The pushed door is a `Route.partsShelf` on the tab's
NavigationStack, so back = chevron + edge-swipe returning to the Vehicle detail that
pushed it - standard pushed-screen behaviour, never a discard. The `.discardSilently`
classification on `SheetRoute.partsShelf` (Routes.swift) was written for the NESTED
SHEET, and it is still right there: the shelf holds no typed input, so neither dismiss
path asks, and nothing is lost. The pushed screen does not consult a sheet discard policy
at all - it pops. Do not "fix" the classification because of the pushed door; it governs
the other presentation.

### The Stations door (RV.150, 2026-09-09)

The coordinate a fill-up save captures silently must be inspectable and removable where
per-station settings live - the Garage. The door and screens, decided here because nothing like
them existed:

- **The row lives on the Garage tab root, BELOW the vehicle grid** (between "Add car" and the
  footer), not above the cars: the rejection that kept reminders off a Garage row applies to the
  car-picking region - "Garage rows carry one-line vitals ... their job is picking a car" - and a
  stations door is a calm account-wide management row (map glyph + "Stations" + caption +
  chevron), the reminders-row vocabulary on Home. It is **always present**, count or no count,
  like Home's reminders row: a user who never logged at a named station reaches the list's own
  empty state ("No stations yet ... log a fill-up at one, or add one"), never a blank.
- **The Garage door navigates; the list creates.** The door itself only lists and opens. The
  Stations list it opens carries the add door (RV.156, the dashed "+ Add station" tile in both
  states - the same idiom as "Add car" on the Garage grid): a station can be named where stations
  are managed, not only mid-entry. Naming is the ONLY station creation - renaming, merging and
  brands stay RV.115's fence.
- **Two pushed screens, one vocabulary.** `Stations` (the account-wide list, every station ever
  logged at) rows push `Station settings` for that station, which shows the recorded location -
  in DIN, runtime data, POSIX-formatted so RU and EN render the same string - and, when one
  exists, **Remove location**. Clearing acts immediately with no confirmation because it is
  reversible: the coordinate is derived (a later save at the station with a fix re-adopts it),
  the asymmetry Vehicle detail's archive row already uses. Both screens have no artboard yet and
  follow the Vehicle-detail/Tire-sets card vocabulary; the screenshot pair for this task is the
  record.
- **Back paths.** Both are pushed `Route`s on the tab stack: chevron + edge-swipe back to the
  screen that pushed them. Nothing here holds typed input, so no door ever asks before leaving.

**The Welcome root (PJ.3, re-argued in RV.23).** One screen (`design/screens/Welcome.dc.html` / `LightWelcome.dc.html`), no tab bar, shown only while the log holds **no vehicle and no session** – decided at launch, never again once a car exists. Its three paths are equal doors (hard rule 15): Add your car, Import from another app, and "Sign in to Tankbook" – the last a full-width button like the other two, carrying the one benefit hardest to guess ("Cloud receipt reading, sync and backup"; `/extract` is bearer-only, so a guest never gets the cloud model). **Add your car stays a peer**: it continues with no account, first and in taillight, and nothing on the screen frames the user who never signs in as having chosen the lesser path (hard rule 1).

Beneath the three doors sits a fourth affordance that is **not** a peer door but a returning user's line: "Already use Tankbook? Restore your garage." It is the only thing on the screen that claims "I am coming back", so it – and only it – carries the restore intent into the sign-in sheet (`arrivedViaRestore: true`, RV.23). That split is the whole difference between a reinstall/Android migrant being offered their account and being funnelled into "Add your car" as if new, and in the other direction it keeps J11a's wrong-provider question away from a brand-new user whose account is empty because it is new. The **guest Home** is that Add-car path's landing state (`GuestHome`): the Home tab rendered for a session-less user, real since PJ.3 – no longer the `-forceGuestHome` presentation fixture.

## Per-screen index

| Screen | Reached from | Forward exits | Back path |
|---|---|---|---|
| Welcome | first launch only – shown while there is **no vehicle AND no session**; never again once a car exists | Add car → AddVehicle · Import from another app → ImportWizard · "Sign in to Tankbook" → SignIn with **no** restore intent (`arrivedViaRestore: false`) · "Already use Tankbook? Restore your garage." → SignIn with the restore intent (`arrivedViaRestore: true`) | none – it IS the root before data exists |
| Sign in | Welcome (the restore line carries the restore intent; the peer "Sign in to Tankbook" button does not), Settings (a running app – no restore intent) | provider → Restoring (existing) or Home (new, uploads local log) | "Not now" / swipe → opener |
| Restoring | successful sign-in with data | Open my garage → Home | Cancel = sign out → Welcome (never traps) |
| Add car | Welcome, Garage, Car switcher | Save → Home (guest: GuestHome) | X → opener |
| Home (incl. guest/empty state) | tab root | gear → Settings (the shared tab-root header), car card, banner, entries, capture · **the header "Type it" split (RV.61)**: the primary action is the fill-up door in one tap, its trailing chevron is a menu offering Service and Expense entry - the same peer manual doors the capture screen's mode row offers, with no camera required · the J9 anomaly insight card (amber, in the Log) expands in place to the evidence (chart + causes) and offers **Create reminder** (act) or **Dismiss with reason** → the dismissal sheet | tab root – no back |
| **Inbox** (RV.38, RV.45) | the bell on the shared tab-root header (Log, Trends and Garage alike) | an item → Edit entry (the entry the reading is about) · an item resolves in place with a **per-field comparison** – each field the receipt read that differs or fills a blank shows "yours vs the receipt" with a tick, then **update from the receipt** (takes the ticked fields only, disabled until one is ticked, hard rule 13), **leave it as it is**, **replace the receipt** (routes to Edit entry). **RV.64: the emphasis follows the tick count, the ORDER never moves** - with nothing ticked "leave it as it is" is the filled button, and from the first tick "update from the receipt" becomes it, so the loud default never contradicts what the user just did and nothing shifts under a finger already reaching for a button · a reading that would change nothing says so and offers no update · Reminders (planned, links, never replaces that screen) | back chevron + edge-swipe → the tab root that pushed it |
| Capture | the tab bar's centre capture button (any tab), GuestHome CTA, notification deep links | mode-dependent confirm sheets · "Type it" opens the form for the selected mode (PJ.6: Fill-up → ConfirmManual, Service → ServiceEntry, Expense → ExpenseEntry) · shutter / Photos → **Capture review** (RV.5) · scan → Confirm/ServiceEntry · **scan · Expense mode** (RV.62) → ExpenseEntry pre-filled with the recognised total/currency/date | X → opener |
| **Capture review** (RV.5, full-screen cover over Capture) | Capture's shutter · Capture's Photos pick – both doors, always; Service mode goes to the document camera instead and never passes through here | **Use this** → the pipeline runs, then Confirm/Foreign/Mixed/Manual, **pre-filled from the LOCAL read and opened immediately** (RV.57). The sheet carries a dismissible notice - "A more reliable reading may still arrive. You can proceed now." - because the cloud answer measured 12-36 s against a 3 s budget (RV.51), so waiting for it is not an option the user should be made to take. **A late answer never reaches the open editor**: within budget it fills blanks, past it the reading routes to the Inbox, where the per-field comparison is the place to accept it (hard rule 13 - nothing the user has typed is overwritten behind their back) · **Use this · Expense mode** (RV.62) → ExpenseEntry pre-filled with the recognised total/currency/date (never liters or fuel kind – a shop receipt has no fuel fields) · **Re-take** → Capture, nothing kept · **Type it** → the form for the selected mode (the same door the capture surface offers) | Re-take **is** the back path – it is the only way out other than a verdict, so the step can never be a dead end |
| Confirm / Foreign / Mixed / Manual | Capture review "Use this" · Capture "Type it" (Fill-up mode) | Save → the sheet AND the capture modal behind it close (RV.12) → the opener tab, entry visible + toast · tank row → TankLevel · the foreign-currency conversion card offers the manual-rate entry on the card itself when the rate is pending (F9, hard rule 7), and "Edit rate" on a feed conversion (hard rule 13) | back → Capture (photo kept) · swipe-down discards scan (photo re-offerable) |
| Tank level (sheet) | Confirm's tank row | Set / Skip → Confirm | swipe-down = Skip |
| Service & expenses | Capture (Service mode, scan) · Capture "Type it" (Service mode) · ReminderComplete · Home's "Type it" menu (RV.61, the no-camera door) | Save → Home · **Tires mode** (P3.3) mounts a set (a `ServiceRecord` carrying `tireSetId`) and makes the odometer required | X → opener (typed input asks first) |
| Expense entry (sheet, P3.2) | Capture "Type it" (Expense mode) · Capture review "Use this" in Expense mode (RV.62, pre-filled with the scan's total/currency/date, editable – hard rule 13) · ServiceEntry's Parts/Other mode row · Home's "Type it" menu (RV.61, the no-camera door) | Save → Home · category, title, money, date (PJ.6 wired the Capture door; `.parts` is an ordinary category, never a separate flow) | X → opener (typed input asks first) |
| Edit entry | Log entry, duplicate/conflict cards, RecentlyDeleted · the account-wide flagged list ("Needs a look") and the inbox's "use a different receipt", both of which pass an EXPLICIT entry id | Save / Delete → Home · photo → viewer · Restore my version · a foreign-currency entry renders the conversion card (resolved from the rate store) and its rate is editable there, including a rate the user set before (hard rule 13) | X → opener |
| **Excluded entries** (RV.141) | the Home Log's / Trends' "N entries excluded" footnote when MORE than one entry is out (N == 1 opens the excluded entry's own Edit screen directly and skips this list) | a row → Edit entry - the entry in front of the user. Each row states WHY it is out (docs/ERRORS.md -> Home, RV.141): a timeline conflict is fixed by editing the odometer or the date, an unresolved duplicate by Merge or Keep both on the Log. The list is CAR-scoped and counts exactly what the footnote counted - conflicts plus the non-counting members of unresolved duplicate pairs, one derivation (`ExcludedEntries.derive`) - never the account-wide "Needs a look" population, which filters to conflicts only | back chevron + edge-swipe → the tab root that pushed it |
| **Attachment viewer** (RV.9 + RV.17 + RV.37, sheet over Edit entry) | the receipt strip's photo chip on Edit entry – the fill-up form and the non-fill form alike; the chip is a control, not decoration | Share/save the full rendition via the system share sheet (RV.17, offered only once the rendition is local – never the 44 pt thumbnail) · swipe to the recognised-data page when the attachment carried any, absent rather than empty otherwise. **RV.48 changed what that page IS**: the headline is now the ASSIGNMENT the parse concluded - date, fuel kind, volume, price per litre, total, currency, each with the value it read - and the raw OCR lines are demoted behind a disclosure rather than being the page. An attachment whose parse assigned nothing SAYS SO instead of rendering an empty card. The page presents STORED data and never re-runs OCR: a fresh read could contradict a value the user has already confirmed (hard rule 13) · **Delete** (system-confirmed: tombstones the attachment and unlinks it from the entry, hard rule 8) · **Replace photo** (the same camera/Photos door as "Add receipt"; a new attachment plus a tombstone for the old, then the ask – "Re-read this and update the entry?" with "Leave it as it is" the default, hard rule 13). Rotate, crop and edit remain their own decisions | **Close and swipe-down, both** – a viewer that can only be left by a gesture traps the user who does not know the gesture |
| Trends | tab root | gear → Settings · insight cards → (chart detail, planned) · capture | tab root |
| Garage | tab root | gear → Settings · vehicle → VehicleDetail (per-car settings) · Add car (the ONE monetization surface - the free-tier cap shows the limit sheet) · **Stations (RV.150, below the grid - the account-wide Stations door)** · capture | tab root |
| Vehicle detail (P1.12) | Garage vehicle, Car switcher archived row, limit sheet "Archive a car" | Save changes → back · Archive/Unarchive (in place) · Delete → system confirm → Recently deleted (the car AND the entries that went down with it restorable, RV.98) · Tire sets → Tire sets · **Parts shelf → Parts shelf [v1.x]** (PJ.25 - the third per-car management row, always present like Tire sets: a car with nothing on the shelf still reaches the shelf, whose own empty state says so) · **Reminders → Reminders** (PJ.4 - the second door, present with nothing due; **hidden for an archived car**, RV.81). **RV.137 (2026-09-08): editing the Make · model row now offers the SAME bundled-catalog suggestions Add car does** (typing an edit mounts them; merely focusing the filled field does not). A pick fills make, model and year as text the user owns and records no catalogue id - preserving the screen's permanence decision (its own header: nothing here stores a catalog id for a later pack to rewrite); name, powertrain, fuel kinds, capacity and units are never rewritten by a pick. **The pinned Save bar steps aside while any field is focused** (RV.137, same report): a `safeAreaInset` bar floats above the keyboard over the one region that does not scroll, which hid the fuel chips mid-edit; with the keyboard up the form owns the whole space above it and the bar returns when focus leaves the field | back → Garage (or opener) |
| Tire sets (P3.3) | Vehicle detail | row → Tire set form (rename) · New tire set → form · Archive (row menu, in place) | back → Vehicle detail |
| Tire set form (P3.3) | Tire sets (New / row) | Save → Tire sets | back → Tire sets |
| **Stations** (RV.150) | the Garage tab root's Stations door | a row → Station settings · **Add station (RV.156)** - the dashed tile in both states, naming through the same deterministic rule the entry row uses | back → Garage |
| **Station settings** (RV.150) | the Stations list's row for that station | **Remove location** (in place; a later save with a fix re-adopts) · **Favourite** toggle (in place, PJ.55; reversible, persists as an ordinary station edit) | back → Stations |
| **Parts shelf** **[v1.x]** (P3.2 screen; PJ.25 gave it its second door) | Vehicle detail's "Parts shelf" row (**pushed**, PJ.25) · a service entry's "View shelf" button (**nested sheet**, P3.2 - unchanged) · `-presentScreen partsShelf` (nested-sheet pose) / `-presentScreen partsShelfPushed` (the pushed door's pose) | none - a read-only list (`.parts` expenses not yet installed in any service; derived, never stored) | **pushed**: back chevron + edge-swipe → the Vehicle detail that pushed it. **nested sheet**: swipe-down / close → the service entry. The shelf has no typed input, so neither door ever asks before leaving - nothing to lose (hard rule 8). The `SheetRoute.partsShelf` `.discardSilently` classification governs the SHEET presentation only; the pushed door is a stack pop, never a discard |

| Car switcher (sheet) | Home car card/chip | pick → Home · Add car · archived → VehicleDetail | swipe-down → Home |
| Reminders | Home banner, VehicleDetail | complete → ReminderComplete · New reminder → form | back → opener |
| **Reminders, all cars** **[v1.1]** (RV.75, `design/screens/RemindersAll.dc.html`) | the Home "Reminders" row and a Garage car's attention count (RV.76/RV.79), and every reminder notification (RV.74 - the deep link lands HERE, so it cannot land on the wrong car, and the reminder's own car is selected first, never an archived one) | a row → ReminderComplete · the car chip narrows to one car's Reminders · New reminder → form, **which asks which car** - defaulting silently to the selected one is the quiet guess hard rule 13 forbids | back → opener |
| **Service reminder offer** **[v1.1]** (RV.77, sheet, `design/screens/ServiceReminderOffer.dc.html`) | saving a ServiceRecord or Expense whose category has a curated interval, and no live reminder of that category exists on that car - the offer sheet is hosted by the tab root that presented the entry sheet, promoted in that sheet's `onDismiss` (never mid-save) | **Create the reminder** (anchored at the record's own date and odometer, never at today, `sourceEntryId` set, recurrence carried) · **Not this time** - a peer button, not a dismissal X | either exit returns to the opener; the record is already saved, so nothing here can lose it. *(Built - RV.77. The interval fields are editable in the same breath; the curated defaults live in `ReminderOffer` in core.)* |
| Reminder form (P3.4, artboard `design/screens/ReminderForm.dc.html` from **[v1.1]**) | Reminders and **Reminders, all cars** (New reminder / row edit, incl. reschedule) · ReminderComplete's "Reschedule instead" · **[v2]** the Ask tab's `draftReminder`, pre-filled | Save → the list it came from | back → opener |
| Reminder complete (sheet) | Reminders, push action | Scan invoice / Type → ServiceEntry · Skip | dismiss → Reminders |
| Anomaly dismiss (sheet, P6.1b) | the Log's anomaly card → **Dismiss with reason** (J9) | preset reasons / free text → records an `AnomalyDismissal` (the card leaves for that cause) | swipe-down / after recording → Log |
| Recently deleted | Settings (and Log overflow menu) | Restore (in place: tombstone cleared, entry back in Log). A tombstoned **car** (RV.98) is one row - "Volvo V60 and 512 entries" - covering every entry that went down with it at the same tombstone stamp; its Restore returns the car AND that group to the Garage and the Log, never a single entry that would be stranded on a deleted vehicle. Entries and reminders the user deleted individually list as their own rows exactly as before. · Compare (presentational until the merge log lands, P4) | back → Settings |
| Settings | any tab root's gear (Log, Trends, Garage) | account card (signed in → Account & devices) · **Sign out** (signed in, the mild account exit - revokes the refresh chain server-side and clears the local session, never touches the log) · language, import, export (system), recently deleted, About | back → the tab root that pushed it |
| Account & devices (P6.4) | Settings account card (signed in) | device list (revoke; **revoked rows stay listed, marked "Signed out"** – the Settings card's count counts the live ones only, RV.54) · Delete account (tombstone; the log on this phone is never touched) | back → Settings |
| About & feedback | Settings | identity header (icon, name, version) · the update row (`.recommended`, dismissible; App Store link only when a compiled-in app id exists) · feedback/rate/privacy (later tasks) · **Attach diagnostics** (OB.4): a once-asked consent, default OFF and persisted, whose "Preview what will be shared" opens the Diagnostics preview | back → Settings |
| **Diagnostics preview** (sheet, docs/LOGGING.md §5) | About -> Attach diagnostics (only reachable once the opt-in is on) | Share (system share sheet - the exact text shown) · read the full redacted bundle: 24 h log window, sync state (last success, dirty/flagged counts, last failure kind + code + traceId), per-table row counts | Close / swipe-down → About - nothing was sent |

### The capture review step (RV.5)

Between the shutter (or the Photos pick) and any Confirm sheet sits one screen with one
question: **can you read the total on this photo?** It is a full-screen cover over Capture -
a page sheet would crop the top of a tall thermal receipt, which is the shape that suffers
most - showing the image **fitted, never cropped**, and three actions: **Use this**, **Re-take**
and **Type it**.

- The **recognition pipeline has not run yet** when this screen appears. The raw image is shown
  the instant it exists and OCR runs only on *Use this*, so the photo is immediate and a re-take
  costs no recognition at all.
- **Re-take is the back path.** It returns to the live camera keeping nothing, so the step
  cannot strand anyone; there is no separate X, because a second dismissal control on a screen
  whose whole content is "keep or shoot again" is noise.
- **Type it is a peer, not a consolation** (hard rule 15): same row as Re-take, same height,
  same weight, and it opens the form for the selected mode - the identical door the capture
  surface offers. Its copy never says typing is what you do when the photo is bad.
- **Service mode does not pass through it**: that shutter opens the document camera, which
  carries Apple's own retake affordance (J7).
- It is **not an error surface**. Nothing on it is amber, and it carries no message about the
  scan having failed - at this point nothing has been read (`docs/ERRORS.md` → Capture).

### Reminders across cars **[v1.1]** (RV.74-RV.79)

Artboards: `RemindersAll.dc.html`, `RemindersEntry.dc.html`, `GarageReminderCounts.dc.html`,
`ServiceReminderOffer.dc.html`, `ReminderNotification.dc.html` (drawn 2026-09-05 from the
`Reminders.dc.html` vocabulary - same card metrics, eyebrows, amber attention border).

**One list, every car.** A reminder competes for the user's weekend, not for a car's attention, so
the merged list is the primary screen and the per-car one (reached from Vehicle detail, or by
narrowing with the car chip) is the special case. Every row **names its car** - a merged row that
does not is unreadable. Grouping and order are unchanged and come from the same core types:
**Needs attention** then **Scheduled**, sorted by `dueSortKey`, so a date reminder and an odometer
reminder interleave by urgency exactly as the Home banner already picks its one row.

**The merged list shows ACTIVE cars only** (RV.75 decision, recorded in the repository query's doc
comment): an archived car is a sold car (J13), out of active stats, never the default selection,
and its monthly summary is cancelled on archive - so its reminders are history, not work for the
coming weekend, and do not compete with live cars' rows. **RV.81 (product owner, 2026-09-06) went further: archiving STRIPS the
reminders** - every armed notification for that car is cancelled, and the per-car Reminders door is
hidden for an archived car, so a sold car neither fires nor offers to be managed. The rows are never
deleted, tombstoned or dismissed: they are put away, not lost (hard rule 8), they
return to the merged list the moment the car is unarchived, and unarchiving re-arms them; the exclusion is read-time
derivation, never a stored state.

**RV.75/RV.74/RV.76/RV.79 status:** the merged screen, its route (`Route.remindersAll`) and the
form's car-first field are built; **RV.74 wired the notification deep link into it** - a tapped
reminder lands on this list, never on a car-scoped one; **RV.76 built the permanent Home row**
(`design/screens/RemindersEntry.dc.html`), so the screen is no longer DEBUG-reached-only; and
**RV.79 built the last planned door** - the per-car attention count on a Garage / Car switcher row
navigates here, so the merged list is reachable from every surface that shows a car
(`design/screens/GarageReminderCounts.dc.html`).

**The Home row's placement was a decision, recorded here so it is not relitigated.** The row lives
on Home, directly UNDER the urgent banner strip in the content stack (`HomeView.fullLayout`,
rendered before the vehicle header row) - the calm path is always the next thing under the amber
one, beside the banner as `RemindersEntry.dc.html` draws it, and it never scrolls below the fold.
A Garage-level row above the cars was the alternative and was rejected for the doorway just as for
the create action (below): Garage rows carry one-line vitals and RV.79's per-car attention count,
and their job is picking a car, not a cross-car door - two reminders on two cars cannot be counted
on one garage row without re-architecting the surface. The tab bar stays decided (five slots, the
fifth reserved for Ask). **The row navigates and never creates** - a "+" there could only guess the
car (hard rule 13) or open the form car-empty one tap later than the merged list's own card.

**The count is the row's point and it is derived** (hard rule 2): the same live cross-car rows the
merged list groups (`liveRemindersAcrossVehicles` -> `ReminderListGroups`) are counted at read
time by `ReminderListGroups.attentionCount`, so the chip and the list's "Needs attention" group
can never disagree. It is never stored and never seeded as a number; the amber chip renders only
when the count is non-zero (amber is attention, hard rule 5 - a "0 due" chip would warn about
nothing), and the row itself is ALWAYS present, count or no count.

**Three consequences worth stating, because each one is a rule and not a preference:**

- **The notification deep link lands here** (RV.74). It used to push the per-car screen without
  switching the selected car, so a reminder on another car was simply absent and the app took its
  own "stale tap" branch. Now the tap resolves the reminder id first - the id is the fact, the
  selected car is not - and lands on this merged list, which cannot be the wrong car at all. The
  reminder's own live car is selected before the push (never an archived one): the app context
  follows the tap, and the completion sheet's "Type amount" logs the cost to the right car. A
  deleted reminder still lands on the plain list (hard rule 7); an archived car's reminder
  surfaces its completion flow over this list without making the sold car current again (J13).
  The switch lives in the router (`TabRoots.driveReminder`), the only place that can write the
  selection before the pushed screen loads.
- **The way in exists when nothing is due** (RV.76, built). The amber Home banner is the urgent
  path and stays; the "Reminders · N due" row is the calm one, always present, and it carries the
  count that makes it worth a tap. The count is derived at read time (hard rule 2) and never
  stored. A list with no reminders at all shows the empty state whose ONE action is the FILLED
  "New reminder" (`RemindersEmpty.dc.html`) - the discovery path for a driver who has never made a
  reminder; the dashed card stays the idiom for a list that has rows.
- **A count marks a car only when something needs attention** (RV.79, built). Scheduled work shows
  nothing: a badge that is always lit stops meaning anything. Amber is attention (hard rule 5) and
  the count reads as words for VoiceOver - colour is never the only channel. The count strip is
  derived at read time over the same live cross-car rows (hard rule 2), is its OWN tap target that
  navigates here, and never creates (the row's job is picking a car).

**Where a reminder is born: the form, with the car as its first field.** There is one creation
screen and it is reached from three places - the merged list, a car's own Reminders list, and (in
v2) the agent's `draftReminder`. The difference between them is only what arrives filled in:

| Opened from | Car field | Why |
|---|---|---|
| Reminders, all cars | **empty, and required** | The user may not have looked at a car at all; defaulting to the selected one is exactly the quiet guess hard rule 13 forbids |
| A car's Reminders list, or Vehicle detail | **filled in, still changeable** | The intent named a car, so pre-filling is a default input - not a fact, and not locked |
| **[v2]** `draftReminder` from Ask | **filled in from the ask, still changeable** | Same rule: the agent fills the form and the user saves it, never the other way round (`AGENT.md` - a chat bubble saying "reminder created" is a hard-rule-13 bug) |

The rest of the form is the shape the data already has: a title and a category; **a date, an
odometer, or both** - whichever comes first wins, which is the promise the list footer already
makes; and an optional repeat in kilometres or months, whose next occurrence is counted from the
**completion**, not the due date, so a schedule cannot drift. With one car in the garage the car
field still shows - it says which car this is about, and it is the only place that says so.

**The empty state is the discovery path, so its one action is loud** (`RemindersEmpty.dc.html`).
Reviewed 2026-09-05 by two models against the mocks and the code (`diagnostics/RESEARCH-reminder-entry-pro.md`,
`-qwen.md`); they converged on this independently, and **RV.76 built it** (both the merged and the
per-car list render the same filled-action empty state, `RemindersEmptyStateView`). The dashed card
is the app's idiom for "add one more" at the END of a populated list - Add car uses it in both
Garage and the Car switcher - and it is the wrong weight for the single thing a screen with nothing
on it can do, where it reads as an empty slot rather than an invitation. So: filled, accent, and
stated plainly ("Nothing to remember yet" plus what a reminder is for). The dashed card keeps its
job on a list that has rows - and is NOT rendered on an empty one, so the screen never offers two
weights for the same action.

**What the create action must NOT be attached to**, argued and rejected in the same review: the tab
bar (five decided slots, the fifth reserved for Ask); the Home header's "Type it" menu, whose items
come from `CaptureEntryForm.doorMenuForms` over an exhaustive enum of ENTRY forms - a reminder has
no amount, no receipt and nothing to scan, so it is not a peer of those doors, and putting it there
would also scope it silently to the selected car; the Home banner (amber is attention, and mixing
planning into triage is what hard rule 5 guards against); the Garage car row, whose count is a
diagnostic and whose job is picking a car; and a second "+" on Vehicle detail, one hop from a card
that already creates with the car filled in.

### The Log is Home: the whole-month reveal (RV.103)

**The Log tab is Home** (`AppTabBar.log = 0`), and Home's entry list is the ONLY stream surface -
the "full Log stream screen" that the old Home comment promised behind "All entries" was never
built. A user who imports a decade of history (J2) used to see its newest ~20 rows and nothing
else: the rows were in the database, counted in every derived figure, and impossible to look at
(RV.103, reported against the owner's own 513-row MFM import).

**The shape chosen is (a) load-more in whole-month pages, not (b) a full-stream screen.** The
preview opens with the newest whole months whose combined rows first reach ~20 rows; a
"Show N older entries" row sits at the seam - the last element of the visible log - and each tap
adds the next whole months. Two fences make the pages safe, and both are structural:

- **A month is atomic.** A page boundary never splits a month, so a divider is only ever rendered
  above a COMPLETE month and always sums exactly the rows shown beneath it - the divider-honesty
  fence (a row-cut preview used to end mid-month with its rows silently missing). A purchase group
  (one collapsed row inside one month) can therefore never straddle a page.
- **The reveal is preserved per car.** Revealing the whole log and then editing an entry reloads
  without collapsing back to the preview; switching cars starts the new car's preview afresh.

The affordance follows hard rule 7: it states the real remaining count ("Show 340 older entries"),
so an end of the visible log that is not the end of the data says so, and it retires itself when
nothing is hidden. No artboard exists for it; it is built from Home's own vocabulary (the caption
action row, chevron + `Theme.Palette.action`), the RV.86 precedent for an artboard-less member.
The year/period filter the owner also asked for (option (c)) is deliberately NOT built here - the
reveal removes the wall; a filter is a separate affordance and a separate row.

### Saving inside capture (RV.12)

Capture is a modal presented over the current tab, not a tab root, so the Confirm sheet's own
dismissal only uncovers the camera. Until RV.12 that is exactly what a device walk saw: capture a
receipt, Save, and the camera is on screen again – a completed entry looking like a failed one,
and a second tap starting a second entry.

- **A successful save closes both**: the entry sheet dismisses as it always did, and the capture
  modal is torn down a beat later, so the user lands back on the tab they started from. Nothing
  navigates and no tab is switched; `toastCenter.noteEntryChanged()` already makes Home reload,
  so the new entry is simply there.
- **Only a success.** A cancel, a swipe-down, or a save that throws leaves the capture modal
  exactly where it is, with the photo and the typing intact (hard rule 8). The discard guard on
  the sheet is unchanged.
- **Both doors, and every mode.** The scan door (review → Use this → Confirm) and the typed door
  ("Type it" → ConfirmManual / ServiceEntry / ExpenseEntry) behave identically – manual entry is
  a peer path, so it cannot be the one that still strands (hard rule 15).
- **The signal is opt-in from the presenter.** Capture hands the sheet a closure to call after a
  successful save; the entry forms know nothing about tabs, covers or the navigation graph, and
  reached from anywhere else they behave exactly as before.

### The Capture surface's alpha notice (P6.10)

Capture carries one non-navigational element: the alpha-testing disclosure
(`docs/ERRORS.md` -> Capture -> The alpha-testing disclosure). It is a **passive
part of the capture surface, not a screen and not a destination** - it has no
forward exit and changes no path. It renders on the live camera layout only,
directly above the shutter, is dismissable per day (persisted in UserDefaults),
and **retires permanently at 3 captures or 3 dismissals** - so it does not
appear in the graph because it cannot trap anyone and eventually stops rendering
altogether. It is never present on any Confirm sheet and never appears between
the shutter and a result.

### Ask **[v2]** (Pro)

Tab root, no back. Header: `Ask` + the car chip (same control as Home; switching car switches
the thread's context). Body: the thread – user turns, the car **context card** on every
diagnosis turn, answer **cards** rendered from tool results (spend, service row, station table,
reminder draft, invoice items, diagnosis with its urgency row), the model's narration beneath
each. Composer: text field, mic, camera. States (`ERRORS.md` → Ask): offline, not Pro, quota
spent, gateway down – the tab and thread stay, the composer explains, the examples become taps
to the ordinary screens. Forward exits: every draft opens its ordinary screen (Reminder form,
Service entry, Confirm manual), every card opens where the data lives (Trends, Edit entry). Back:
none – it is a tab root; sheets it opens dismiss to it. Artboards (`design/screens/v2/`): `AgentChat`, `AgentDiagnosis`,
`AgentInvoice`, `AgentReminderDraft`, `AgentAsk` (states), `AgentHome` (the bar).

## Screens referenced but not yet drawn

The map names screens that exist as nodes but have no artboard yet – listed so they're planned, not forgotten: **Paywall** (**[v2]**, Pro – the tier journey is not yet written; see the note under AG.12 in `docs/TASKS.md`. **RV.70 (2026-09-05): the Settings → Paywall entry points were removed** – the Settings root's "Tankbook Pro" card and the quota card's Pro button both pushed `Route.paywall`, which resolved to a blank `LeafContent` (a guideline-2.1 placeholder, contradicting the no-IAP listing, `docs/STORE.md` §6). Nothing on Settings reaches the Paywall node in v1 now; its only v1-present door is the free-tier car-limit sheet's "Pro" (the sanctioned monetization surface, `docs/ERRORS.md` → Car switcher / Garage) and its [v2] door is the Ask tab's not-Pro card). Each already has its journey and schema defined; only pixels are missing. (**Garage tab root** and **Account & devices** left this list on 2026-08-29: P6.4 built both. The Garage tab root has no artboard, so it follows the Car switcher sheet's vehicle-card language (42pt tile, name + selected dot, one-line vitals in the car's own units, dashed Add car tile, footer invariant) as a full tab root with each card leading to Vehicle detail. Account & devices has no artboard either, so it follows the Settings card conventions - identity header, a devices card with one row per server device, a delete-account row whose confirmation states the tombstone truth from `site/delete-account.md` (server copy removed after the grace period; the log on this phone is never touched).) (**Import wizard** left this list on 2026-08-27: it is drawn as three artboards - `ImportSource.dc.html` (which app is this file from, with the **server-driven** supported list), `ImportPreview.dc.html` (the F6a gate: figures the user can check from memory, target car, duplicate count, and nothing written until confirm) and `ImportReview.dc.html` (the F6 rows that need a look). **RV.86 (2026-09-06) added a fourth, conditional step with no artboard of its own** - `ImportCars.dc.html` does not exist; the `.cars` mapping gate was built from the wizard's own vocabulary (the preview's figures row, the target sheet's destination rows). A file the parse groups into **more than one source car** lands on it after the source picker: each car is listed with its own row count, odometer span and date range, and an explicit destination (leave out / a new car / an existing garage car); Continue stays disabled until every car is decided, and the gate carries the summary bar and the commit. A single-car file never sees the step. **RV.93 (2026-09-07): the source picker accepts a whole export at once** (`allowsMultipleSelection`), one staged copy and one `/import/parse` call per file; the wizard's steps are unchanged (a multi-file pick still lands on source -> cars/preview -> review -> commit), the car mapping is asked once per **distinct** source car across all the picked files (the union of the `Vehicle name` column), and a per-file failure keeps the source step with the file named and the survivors one tap away. The flow stays **source -> file -> preview -> [rows to fix] -> commit** for a single-car file (unchanged, byte-for-byte); a multi-car file takes **source -> file -> cars (the mapping gate) -> [rows to fix] -> commit**, where the mapping screen IS the F6a gate. Every step backs out to the one before it; **Cancel** from any gate returns to Settings having written nothing and deleted the stored parse. (The `Import wizard` left the no-artboard list on 2026-08-27; the conditional `.cars` step is its only artboard-less member, built from the wizard's own vocabulary rather than new pixels.) (**Vehicle detail** was in this list until P1.12 made it real: per-car settings, archive/unarchive (J13) and delete now live there; it has no separate artboard yet, so it follows the shared Add-car layout and the DESIGN.md one-row header. **RV.137 (2026-09-08)** added the last Add-car affordance it lacked - the catalogue suggestion list under the Make · model row, drawn from the SAME shared component (`Shared/VehicleCatalogSuggestionsArea.swift`) - and pinned the Save-bar-behaviour decision above in row 184: the bar steps aside while a field is focused so the fuel chips are never trapped under a non-scrolling inset. **Reminder form** was in this list until **P3.4** drew it from the DESIGN.md tokens and the ServiceEntry form it sits beside; it now HAS an artboard - `design/screens/ReminderForm.dc.html`, drawn 2026-09-05 with the [v1.1] set, which adds the car field the merged list requires. **Tire sets** was added in **P3.3** – no artboard, so the list and its name form follow the Reminder list/form's card metrics, eyebrows and underlines.)

## Dead-end audit

- Every sheet dismisses (swipe + explicit control); every pushed screen has chevron + edge-swipe; tab roots are roots by definition. ✓
- **Restoring** was the one screen that could trap (mid-restore, wrong account): it gets an explicit *Cancel = sign out → Welcome*. ✓
- **Save never strands**: every save leaves its sheet, and a save reached through capture leaves the capture modal with it (RV.12), landing on the tab capture was opened from with the entry visible. Capture opened from Trends returns to Trends – it does not jump to the Log; the entry is there when the user next opens it. ✓
- **Failure states are forks, not ends** (JOURNEYS F-series): OCR failure → ConfirmManual is the same sheet, same back paths; denied camera → Capture's "Type it" path still works. ✓
- **Manual entry is a peer path, not a failure branch** (hard rule 15). "Type it" is offered
  next to capture at every entry point - Home's header, both empty states, the guest layout,
  the Capture screen itself and the **capture review step** (RV.5), where it sits on the same
  row as Re-take at the same size - and reaching it never requires first attempting a scan. Outside
  Capture it is the `ConfirmManual` sheet; **inside Capture it opens the form for the selected
  mode** (PJ.6): Fill-up → `ConfirmManual`, Service → ServiceEntry, Expense → ExpenseEntry. A
  user who starts manually and one whose scan came back thin end up in the identical screen for
  their kind of entry, editing the same fields.
  **RV.61 (hard rule 15, the two doors at every entry point):** Home's header "Type it" is a
  **split** - the primary action is the fill-up form in one tap (the commonest entry never gets
  slower), and its trailing chevron is a menu offering **Service** and **Expense** entry. This is
  the no-camera manual door for the two entry types that previously existed only behind the capture
  screen's mode row; a fourth entry form appears in that menu the moment it exists
  (`CaptureEntryForm.doorMenuForms` derives from `allCases`, and `sheetRoute` is an exhaustive
  switch, so it cannot silently lack a door).
- **Confirm takes a `ConfirmPrefill` (P2.3)**: the extraction pre-fills present fields, nil
  fields stay blank and focusable, and an all-nil extraction IS the ordinary manual form -
  never an error, never a "scan failed" banner (the two doors stay equal). **PJ.17: when that
  all-nil scan carried a photo** (F1 - "recognized nothing"), the sheet stays the same ordinary
  form and adds the ONE quiet trace of the failed scan: an `inkSoft` caption "Couldn't read this
  one – type it, the photo stays attached." (a caption, never a banner, never amber - hard rule
  5 - and the typed path shows no caption at all), with Total focused on appear. Resolved-but-
  unconfirmed fields render at 60% opacity (docs/DESIGN.md) and remain fully editable
  (hard rule 13); the magnifier on such a field opens the source-image crop it came from
  (tap-to-verify), degrading to a no-op when no crop is attached. A fiscal QR anchor
  outranks the OCR total (docs/SCHEMA.md -> FISCAL QR): `.disagrees` fills the QR total,
  a mixed receipt keeps the fuel line (hard rule 4), and the difference is P2.4's job.
- **A reminder notification is actionable from the banner** (RV.78, `design/screens/ReminderNotification.dc.html`): **Mark done** opens the app on the completion sheet rather than completing silently - declining the cost log is first-class but it stays the user's choice (J7c) - and **Push a week** defers the reminder by seven days and re-arms, the one action that needs no screen. Both route through the same lifecycle the Reminders screen uses, never a second implementation. What "a week" defers and how an odometer-only reminder behaves: `docs/NOTIFICATIONS.md` -> the actions. ✓
- **Stations and Station settings (RV.150) are pushed screens** (chevron + edge-swipe back to the Garage / Stations that pushed them); their in-place actions, **Remove location** and (PJ.55) the **Favourite** toggle, are reversible - the coordinate re-adopts on a later save with a fix, and the favourite can be turned off again - so neither strands and neither needs a system confirm. ✓
- **Notifications deep-link** into Reminders/Trends – both roots with full navigation, never into a bare sheet with no context. ✓ **(PJ.5):** the tap routes by the identifier's family - `reminder.<uuid>.<kind>` switches to Log, pushes Reminders and surfaces that reminder's completion sheet; `monthly-summary.*` switches to the Trends tab. An unknown or malformed identifier (a stale notification for a reminder deleted since it was scheduled) is inert: the app opens normally and routes nowhere (hard rule 7). The mapping is a pure value type in core (`NotificationRoute`, `NotificationRouteParser`); `didReceive` resolves through it and hands the route to the `NotificationRouter`, which `AppRootView` drives.
- Welcome is unreachable after onboarding except via Restoring's cancel (over an empty garage) – a full sign-out with a car lands on the **guest Home**, not Welcome, because Welcome shows only with *no vehicle* AND *no session* (PJ.3); intentional, it is not part of the daily graph. ✓

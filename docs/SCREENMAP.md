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
    Home -->|All entries → entry| EditEntry

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
    VehicleDetail -.->|back| Garage
    VehicleDetail -->|Tire sets| TireSets
    VehicleDetail -->|Reminders| Reminders
    TireSets -->|New tire set / row| TireSetForm
    TireSets -.->|back| VehicleDetail
    TireSetForm -->|Save| TireSets
    CarSwitcher -->|pick car| Home
    CarSwitcher -->|Add car| AddVehicle
    CarSwitcher -->|archived car| VehicleDetail
    CarSwitcher -.->|dismiss| Home
    AddVehicle -->|Save| Home
    AddVehicle -.->|X| Back2[return to opener]

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
    About -.->|back| Settings
    RecentlyDeleted -->|Restore| RecentlyDeleted   (row removed; entry back in Log)
    RecentlyDeleted -.->|back| Settings
    AccountDevices -.->|back| Settings
    ImportWizard -.->|back| Back5[return to opener]

    Notification[Push: reminder due] --> Reminders
    Notification2[Toast: synced, N need a look] --> Home
```

Dashed arrows = back/dismiss paths. `Back[return to opener]` = the screen is reachable from several places and back always returns to the specific opener (standard stack behavior), never to a hardcoded screen.

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
| Edit entry | Log entry, duplicate/conflict cards, RecentlyDeleted | Save / Delete → Home · photo → viewer · Restore my version · a foreign-currency entry renders the conversion card (resolved from the rate store) and its rate is editable there, including a rate the user set before (hard rule 13) | X → opener |
| **Attachment viewer** (RV.9 + RV.17 + RV.37, sheet over Edit entry) | the receipt strip's photo chip on Edit entry – the fill-up form and the non-fill form alike; the chip is a control, not decoration | Share/save the full rendition via the system share sheet (RV.17, offered only once the rendition is local – never the 44 pt thumbnail) · swipe to the recognised-data page when the attachment carried any, absent rather than empty otherwise. **RV.48 changed what that page IS**: the headline is now the ASSIGNMENT the parse concluded - date, fuel kind, volume, price per litre, total, currency, each with the value it read - and the raw OCR lines are demoted behind a disclosure rather than being the page. An attachment whose parse assigned nothing SAYS SO instead of rendering an empty card. The page presents STORED data and never re-runs OCR: a fresh read could contradict a value the user has already confirmed (hard rule 13) · **Delete** (system-confirmed: tombstones the attachment and unlinks it from the entry, hard rule 8) · **Replace photo** (the same camera/Photos door as "Add receipt"; a new attachment plus a tombstone for the old, then the ask – "Re-read this and update the entry?" with "Leave it as it is" the default, hard rule 13). Rotate, crop and edit remain their own decisions | **Close and swipe-down, both** – a viewer that can only be left by a gesture traps the user who does not know the gesture |
| Trends | tab root | gear → Settings · insight cards → (chart detail, planned) · capture | tab root |
| Garage | tab root | gear → Settings · vehicle → VehicleDetail (per-car settings) · Add car (the ONE monetization surface - the free-tier cap shows the limit sheet) · capture | tab root |
| Vehicle detail (P1.12) | Garage vehicle, Car switcher archived row, limit sheet "Archive a car" | Save changes → back · Archive/Unarchive (in place) · Delete → system confirm → Recently deleted (entries restorable) · Tire sets → Tire sets · **Reminders → Reminders** (PJ.4 - the second door, present with nothing due) | back → Garage (or opener) |
| Tire sets (P3.3) | Vehicle detail | row → Tire set form (rename) · New tire set → form · Archive (row menu, in place) | back → Vehicle detail |
| Tire set form (P3.3) | Tire sets (New / row) | Save → Tire sets | back → Tire sets |
| Car switcher (sheet) | Home car card/chip | pick → Home · Add car · archived → VehicleDetail | swipe-down → Home |
| Reminders | Home banner, VehicleDetail, push notification (a tapped reminder also surfaces that reminder's completion sheet, PJ.5) | complete → ReminderComplete · New reminder → form | back → opener |
| Reminder form (P3.4) | Reminders (New reminder / row edit, incl. reschedule) | Save → Reminders | back → Reminders |
| Reminder complete (sheet) | Reminders, push action | Scan invoice / Type → ServiceEntry · Skip | dismiss → Reminders |
| Anomaly dismiss (sheet, P6.1b) | the Log's anomaly card → **Dismiss with reason** (J9) | preset reasons / free text → records an `AnomalyDismissal` (the card leaves for that cause) | swipe-down / after recording → Log |
| Recently deleted | Settings (and Log overflow menu) | Restore (in place: tombstone cleared, entry back in Log) · Compare (presentational until the merge log lands, P4) | back → Settings |
| Settings | any tab root's gear (Log, Trends, Garage) | account card (signed in → Account & devices) · **Sign out** (signed in, the mild account exit - revokes the refresh chain server-side and clears the local session, never touches the log) · language, import, export (system), recently deleted, About | back → the tab root that pushed it |
| Account & devices (P6.4) | Settings account card (signed in) | device list (revoke; **revoked rows stay listed, marked "Signed out"** – the Settings card's count counts the live ones only, RV.54) · Delete account (tombstone; the log on this phone is never touched) | back → Settings |
| About & feedback | Settings | identity header (icon, name, version) · the update row (`.recommended`, dismissible; App Store link only when a compiled-in app id exists) · feedback/rate/privacy (later tasks) | back → Settings |

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

The map names screens that exist as nodes but have no artboard yet – listed so they're planned, not forgotten: **Paywall** (**[v2]**, Pro – the tier journey is not yet written; see the note under AG.12 in `docs/TASKS.md`. **RV.70 (2026-09-05): the Settings → Paywall entry points were removed** – the Settings root's "Tankbook Pro" card and the quota card's Pro button both pushed `Route.paywall`, which resolved to a blank `LeafContent` (a guideline-2.1 placeholder, contradicting the no-IAP listing, `docs/STORE.md` §6). Nothing on Settings reaches the Paywall node in v1 now; its only v1-present door is the free-tier car-limit sheet's "Pro" (the sanctioned monetization surface, `docs/ERRORS.md` → Car switcher / Garage) and its [v2] door is the Ask tab's not-Pro card). Each already has its journey and schema defined; only pixels are missing. (**Garage tab root** and **Account & devices** left this list on 2026-08-29: P6.4 built both. The Garage tab root has no artboard, so it follows the Car switcher sheet's vehicle-card language (42pt tile, name + selected dot, one-line vitals in the car's own units, dashed Add car tile, footer invariant) as a full tab root with each card leading to Vehicle detail. Account & devices has no artboard either, so it follows the Settings card conventions - identity header, a devices card with one row per server device, a delete-account row whose confirmation states the tombstone truth from `site/delete-account.md` (server copy removed after the grace period; the log on this phone is never touched).) (**Import wizard** left this list on 2026-08-27: it is drawn as three artboards - `ImportSource.dc.html` (which app is this file from, with the **server-driven** supported list), `ImportPreview.dc.html` (the F6a gate: figures the user can check from memory, target car, duplicate count, and nothing written until confirm) and `ImportReview.dc.html` (the F6 rows that need a look). The flow is **Settings -> Import -> source -> file -> preview -> [rows to fix] -> commit**, and every step backs out to the one before it; **Cancel** from the preview returns to Settings having written nothing and deleted the stored parse.) (**Vehicle detail** was in this list until P1.12 made it real: per-car settings, archive/unarchive (J13) and delete now live there; it has no separate artboard yet, so it follows the shared Add-car layout and the DESIGN.md one-row header. **Reminder form** was in this list until **P3.4** drew it from the DESIGN.md tokens and the ServiceEntry form it sits beside – it has no dedicated artboard and follows that form's card metrics, eyebrow labels and field underlines. **Tire sets** was added in **P3.3** – no artboard, so the list and its name form follow the Reminder list/form's card metrics, eyebrows and underlines.)

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
- **Notifications deep-link** into Reminders/Trends – both roots with full navigation, never into a bare sheet with no context. ✓ **(PJ.5):** the tap routes by the identifier's family - `reminder.<uuid>.<kind>` switches to Log, pushes Reminders and surfaces that reminder's completion sheet; `monthly-summary.*` switches to the Trends tab. An unknown or malformed identifier (a stale notification for a reminder deleted since it was scheduled) is inert: the app opens normally and routes nowhere (hard rule 7). The mapping is a pure value type in core (`NotificationRoute`, `NotificationRouteParser`); `didReceive` resolves through it and hands the route to the `NotificationRouter`, which `AppRootView` drives.
- Welcome is unreachable after onboarding except via Restoring's cancel (over an empty garage) – a full sign-out with a car lands on the **guest Home**, not Welcome, because Welcome shows only with *no vehicle* AND *no session* (PJ.3); intentional, it is not part of the daily graph. ✓

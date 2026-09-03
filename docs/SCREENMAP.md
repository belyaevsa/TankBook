# Tankbook – Screen Map

*The navigation graph: every screen, how it's reached, how it exits, and how you get back. Companion to `design/screens/` (the artboards), `JOURNEYS.md` (why each path exists), and `DESIGN.md` (layout rules). Rule zero: **no dead ends** – every screen has a back path and at least one forward exit; the audit at the bottom proves it.*

## Navigation conventions

0. **Version scope**: nodes and sections without a marker are v1; **[v2]** marks screens v1 does not ship (the Ask tab and its sheets, the Paywall). `CLAUDE.md` → Version scope.

1. **Three navigation kinds, three gestures:**
   - **Tab roots** (Log/Home, Trends, Garage) – no back button; switching tabs preserves each tab's stack.
   - **Pushed screens** (Settings, About, Reminders, Recently deleted, Edit entry) – back chevron top-left + iOS edge-swipe. Back never discards saved data.
   - **Sheets** (Confirm variants, Car switcher, Tank level, Reminder complete, Sign in) – drag handle, swipe-down to dismiss, plus an explicit close/"Not now". A sheet with unsaved *typed* input asks before discarding ("Keep editing / Discard"); a sheet with only scanned data discards silently – the photo is never lost, it re-offers from the camera roll.
2. **Capture is modal full-screen** (camera): X closes back to wherever it was opened from, and so does a **successful save** – see "Saving inside capture" below. A save inside capture tears the modal down (RV.12); it does **not** switch tabs, so it lands wherever capture was opened from, with the new entry visible there (Home reloads on `noteEntryChanged`). The earlier wording here promised the **Log tab regardless of where capture started**; that cross-tab jump was never built, and RV.12 deliberately did not add it – a save that moves the user to a tab they did not choose is a second surprise on top of the one it fixes. Recorded here as the shape that ships; changing it is a product decision, not a bug fix.
3. **System surfaces** (photo viewer, share sheet for export, App Store rating, system delete-confirmation alerts) are leaves that return automatically – listed once here, not repeated below.

## The map

```mermaid
flowchart TD
    subgraph Onboarding
        Welcome -->|Add your car| AddVehicle
        Welcome -->|Import from another app| ImportWizard
        Welcome -->|Already use Tankbook? Sign in| SignIn
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

    Settings -->|account card, guest| SignIn
    Settings -->|account card, signed in| AccountDevices
    Settings -->|Import| ImportWizard
    Settings -->|"2 entries need a look"| Log
    Settings -->|Recently deleted| RecentlyDeleted
    Settings -->|Pro| Paywall
    Settings -->|About| About
    Settings -.->|back| Home
    About -.->|back| Settings
    RecentlyDeleted -->|Restore| RecentlyDeleted   (row removed; entry back in Log)
    RecentlyDeleted -.->|back| Settings
    AccountDevices -.->|back| Settings
    Paywall -.->|close| Settings
    ImportWizard -.->|back| Back5[return to opener]

    Notification[Push: reminder due] --> Reminders
    Notification2[Toast: synced, N need a look] --> Home
```

Dashed arrows = back/dismiss paths. `Back[return to opener]` = the screen is reachable from several places and back always returns to the specific opener (standard stack behavior), never to a hardcoded screen.

**The Welcome root (PJ.3).** One screen (`design/screens/Welcome.dc.html` / `LightWelcome.dc.html`), no tab bar, shown only while the log holds **no vehicle and no session** – decided at launch, never again once a car exists. Its three paths are equal doors (hard rule 15): Add your car, Import from another app, and "Already use Tankbook? Sign in" – the last carrying the restore intent, which is the whole difference between a reinstall/Android migrant being offered their account and being funnelled into "Add your car" as if new. The **guest Home** is that Add-car path's landing state (`GuestHome`): the Home tab rendered for a session-less user, real since PJ.3 – no longer the `-forceGuestHome` presentation fixture.

## Per-screen index

| Screen | Reached from | Forward exits | Back path |
|---|---|---|---|
| Welcome | first launch only – shown while there is **no vehicle AND no session**; never again once a car exists | Add car → AddVehicle · Import from another app → ImportWizard · "Already use Tankbook? Sign in" → SignIn with the restore intent (`arrivedViaRestore: true`) | none – it IS the root before data exists |
| Sign in | Welcome (the third path carries the restore intent), Settings (a running app – no restore intent) | provider → Restoring (existing) or Home (new, uploads local log) | "Not now" / swipe → opener |
| Restoring | successful sign-in with data | Open my garage → Home | Cancel = sign out → Welcome (never traps) |
| Add car | Welcome, Garage, Car switcher | Save → Home (guest: GuestHome) | X → opener |
| Home (incl. guest/empty state) | tab root | gear, car card, banner, entries, capture · the J9 anomaly insight card (amber, in the Log) expands in place to the evidence (chart + causes) and offers **Create reminder** (act) or **Dismiss with reason** → the dismissal sheet | tab root – no back |
| Capture | the tab bar's centre capture button (any tab), GuestHome CTA, notification deep links | mode-dependent confirm sheets · "Type it" opens the form for the selected mode (PJ.6: Fill-up → ConfirmManual, Service → ServiceEntry, Expense → ExpenseEntry) · shutter / Photos → **Capture review** (RV.5) · scan → Confirm/ServiceEntry | X → opener |
| **Capture review** (RV.5, full-screen cover over Capture) | Capture's shutter · Capture's Photos pick – both doors, always; Service mode goes to the document camera instead and never passes through here | **Use this** → the pipeline runs, then Confirm/Foreign/Mixed/Manual · **Re-take** → Capture, nothing kept · **Type it** → the form for the selected mode (the same door the capture surface offers) | Re-take **is** the back path – it is the only way out other than a verdict, so the step can never be a dead end |
| Confirm / Foreign / Mixed / Manual | Capture review "Use this" · Capture "Type it" (Fill-up mode) | Save → the sheet AND the capture modal behind it close (RV.12) → the opener tab, entry visible + toast · tank row → TankLevel · the foreign-currency conversion card offers the manual-rate entry on the card itself when the rate is pending (F9, hard rule 7), and "Edit rate" on a feed conversion (hard rule 13) | back → Capture (photo kept) · swipe-down discards scan (photo re-offerable) |
| Tank level (sheet) | Confirm's tank row | Set / Skip → Confirm | swipe-down = Skip |
| Service & expenses | Capture (Service mode, scan) · Capture "Type it" (Service mode) · ReminderComplete | Save → Home · **Tires mode** (P3.3) mounts a set (a `ServiceRecord` carrying `tireSetId`) and makes the odometer required | X → opener (typed input asks first) |
| Expense entry (sheet, P3.2) | Capture "Type it" (Expense mode) · ServiceEntry's Parts/Other mode row | Save → Home · category, title, money, date (PJ.6 wired the Capture door; `.parts` is an ordinary category, never a separate flow) | X → opener (typed input asks first) |
| Edit entry | Log entry, duplicate/conflict cards, RecentlyDeleted | Save / Delete → Home · photo → viewer · Restore my version · a foreign-currency entry renders the conversion card (resolved from the rate store) and its rate is editable there, including a rate the user set before (hard rule 13) | X → opener |
| Trends | tab root | insight cards → (chart detail, planned) · capture | tab root |
| Garage | tab root | vehicle → VehicleDetail (per-car settings) · Add car (the ONE monetization surface - the free-tier cap shows the limit sheet) · capture | tab root |
| Vehicle detail (P1.12) | Garage vehicle, Car switcher archived row, limit sheet "Archive a car" | Save changes → back · Archive/Unarchive (in place) · Delete → system confirm → Recently deleted (entries restorable) · Tire sets → Tire sets · **Reminders → Reminders** (PJ.4 - the second door, present with nothing due) | back → Garage (or opener) |
| Tire sets (P3.3) | Vehicle detail | row → Tire set form (rename) · New tire set → form · Archive (row menu, in place) | back → Vehicle detail |
| Tire set form (P3.3) | Tire sets (New / row) | Save → Tire sets | back → Tire sets |
| Car switcher (sheet) | Home car card/chip | pick → Home · Add car · archived → VehicleDetail | swipe-down → Home |
| Reminders | Home banner, VehicleDetail, push notification (a tapped reminder also surfaces that reminder's completion sheet, PJ.5) | complete → ReminderComplete · New reminder → form | back → opener |
| Reminder form (P3.4) | Reminders (New reminder / row edit, incl. reschedule) | Save → Reminders | back → Reminders |
| Reminder complete (sheet) | Reminders, push action | Scan invoice / Type → ServiceEntry · Skip | dismiss → Reminders |
| Anomaly dismiss (sheet, P6.1b) | the Log's anomaly card → **Dismiss with reason** (J9) | preset reasons / free text → records an `AnomalyDismissal` (the card leaves for that cause) | swipe-down / after recording → Log |
| Recently deleted | Settings (and Log overflow menu) | Restore (in place: tombstone cleared, entry back in Log) · Compare (presentational until the merge log lands, P4) | back → Settings |
| Settings | Home gear | account, import, export (system), recently deleted, Pro, About | back → Home |
| Account & devices (P6.4) | Settings account card (signed in) | device list (revoke) · Delete account (tombstone; the log on this phone is never touched) | back → Settings |
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

The map names screens that exist as nodes but have no artboard yet – listed so they're planned, not forgotten: **Paywall** (**[v2]**, Pro – the tier journey is not yet written; see the note under AG.12 in `docs/TASKS.md`). Each already has its journey and schema defined; only pixels are missing. (**Garage tab root** and **Account & devices** left this list on 2026-08-29: P6.4 built both. The Garage tab root has no artboard, so it follows the Car switcher sheet's vehicle-card language (42pt tile, name + selected dot, one-line vitals in the car's own units, dashed Add car tile, footer invariant) as a full tab root with each card leading to Vehicle detail. Account & devices has no artboard either, so it follows the Settings card conventions - identity header, a devices card with one row per server device, a delete-account row whose confirmation states the tombstone truth from `site/delete-account.md` (server copy removed after the grace period; the log on this phone is never touched).) (**Import wizard** left this list on 2026-08-27: it is drawn as three artboards - `ImportSource.dc.html` (which app is this file from, with the **server-driven** supported list), `ImportPreview.dc.html` (the F6a gate: figures the user can check from memory, target car, duplicate count, and nothing written until confirm) and `ImportReview.dc.html` (the F6 rows that need a look). The flow is **Settings -> Import -> source -> file -> preview -> [rows to fix] -> commit**, and every step backs out to the one before it; **Cancel** from the preview returns to Settings having written nothing and deleted the stored parse.) (**Vehicle detail** was in this list until P1.12 made it real: per-car settings, archive/unarchive (J13) and delete now live there; it has no separate artboard yet, so it follows the shared Add-car layout and the DESIGN.md one-row header. **Reminder form** was in this list until **P3.4** drew it from the DESIGN.md tokens and the ServiceEntry form it sits beside – it has no dedicated artboard and follows that form's card metrics, eyebrow labels and field underlines. **Tire sets** was added in **P3.3** – no artboard, so the list and its name form follow the Reminder list/form's card metrics, eyebrows and underlines.)

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

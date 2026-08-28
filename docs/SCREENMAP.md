# Tankbook – Screen Map

*The navigation graph: every screen, how it's reached, how it exits, and how you get back. Companion to `design/screens/` (the artboards), `JOURNEYS.md` (why each path exists), and `DESIGN.md` (layout rules). Rule zero: **no dead ends** – every screen has a back path and at least one forward exit; the audit at the bottom proves it.*

## Navigation conventions

1. **Three navigation kinds, three gestures:**
   - **Tab roots** (Log/Home, Trends, Garage) – no back button; switching tabs preserves each tab's stack.
   - **Pushed screens** (Settings, About, Reminders, Recently deleted, Edit entry) – back chevron top-left + iOS edge-swipe. Back never discards saved data.
   - **Sheets** (Confirm variants, Car switcher, Tank level, Reminder complete, Sign in) – drag handle, swipe-down to dismiss, plus an explicit close/"Not now". A sheet with unsaved *typed* input asks before discarding ("Keep editing / Discard"); a sheet with only scanned data discards silently – the photo is never lost, it re-offers from the camera roll.
2. **Capture is modal full-screen** (camera): X closes back to wherever it was opened from. Saving from any confirm sheet lands on the **Log tab** with the new entry visible (and the after-save toast) – regardless of where capture started. This is deliberate: save always shows its result.
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
        Garage
    end

    Home <-->|tab switch| Trends
    Home <-->|tab switch| Garage

    Home -->|gear| Settings
    Home -->|car card / chip| CarSwitcher
    Home -->|reminder banner| Reminders
    Home -->|entry tap| EditEntry
    Home -->|duplicate / conflict card| EditEntry
    Home -->|All entries → entry| EditEntry

    subgraph CaptureFlow["Capture (modal)"]
        Capture -->|auto: receipt| Confirm
        Capture -->|auto: foreign currency| ConfirmForeign
        Capture -->|auto: mixed receipt| ConfirmMixed
        Capture -->|Type it, or OCR declined to guess| ConfirmManual
        Capture -->|Service mode| ServiceEntry
        Capture -.->|X| Back[return to opener]
        Confirm -->|tank row| TankLevel
        TankLevel -.->|Set / Skip| Confirm
        Confirm & ConfirmForeign & ConfirmMixed & ConfirmManual -->|Save| Home
        Confirm & ConfirmForeign & ConfirmMixed & ConfirmManual -.->|back| Capture
        ServiceEntry -->|Save| Home
        ServiceEntry -.->|X| Capture
    end

    Home -->|capture button| Capture
    Trends -->|capture button| Capture
    Garage -->|capture button| Capture

    Garage -->|vehicle| VehicleDetail
    Garage -->|Add car| AddVehicle
    VehicleDetail -.->|back| Garage
    VehicleDetail -->|Tire sets| TireSets
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

## Per-screen index

| Screen | Reached from | Forward exits | Back path |
|---|---|---|---|
| Welcome | first launch only | Add car → AddVehicle · Import · Sign in | none – it IS the root before data exists |
| Sign in | Welcome, Settings | provider → Restoring (existing) or Home (new, uploads local log) | "Not now" / swipe → opener |
| Restoring | successful sign-in with data | Open my garage → Home | Cancel = sign out → Welcome (never traps) |
| Add car | Welcome, Garage, Car switcher | Save → Home (guest: GuestHome) | X → opener |
| Home (incl. guest/empty state) | tab root | gear, car card, banner, entries, capture · the J9 anomaly insight card (amber, in the Log) expands in place to the evidence (chart + causes) and offers **Create reminder** (act) or **Dismiss with reason** → the dismissal sheet | tab root – no back |
| Capture | the tab bar's centre capture button (any tab), GuestHome CTA, notification deep links | mode-dependent confirm sheets | X → opener |
| Confirm / Foreign / Mixed / Manual | Capture result | Save → Home + toast · tank row → TankLevel · the foreign-currency conversion card offers the manual-rate entry on the card itself when the rate is pending (F9, hard rule 7), and "Edit rate" on a feed conversion (hard rule 13) | back → Capture (photo kept) · swipe-down discards scan (photo re-offerable) |
| Tank level (sheet) | Confirm's tank row | Set / Skip → Confirm | swipe-down = Skip |
| Service & expenses | Capture (Service mode), ReminderComplete | Save → Home · **Tires mode** (P3.3) mounts a set (a `ServiceRecord` carrying `tireSetId`) and makes the odometer required | X → opener (typed input asks first) |
| Edit entry | Log entry, duplicate/conflict cards, RecentlyDeleted | Save / Delete → Home · photo → viewer · Restore my version · a foreign-currency entry renders the conversion card (resolved from the rate store) and its rate is editable there, including a rate the user set before (hard rule 13) | X → opener |
| Trends | tab root | insight cards → (chart detail, planned) · capture | tab root |
| Garage | tab root | vehicle → VehicleDetail (per-car settings) · Add car (the ONE monetization surface - the free-tier cap shows the limit sheet) · capture | tab root |
| Vehicle detail (P1.12) | Garage vehicle, Car switcher archived row, limit sheet "Archive a car" | Save changes → back · Archive/Unarchive (in place) · Delete → system confirm → Recently deleted (entries restorable) · Tire sets → Tire sets | back → Garage (or opener) |
| Tire sets (P3.3) | Vehicle detail | row → Tire set form (rename) · New tire set → form · Archive (row menu, in place) | back → Vehicle detail |
| Tire set form (P3.3) | Tire sets (New / row) | Save → Tire sets | back → Tire sets |
| Car switcher (sheet) | Home car card/chip | pick → Home · Add car · archived → VehicleDetail | swipe-down → Home |
| Reminders | Home banner, VehicleDetail, push notification | complete → ReminderComplete · New reminder → form | back → opener |
| Reminder form (P3.4) | Reminders (New reminder / row edit, incl. reschedule) | Save → Reminders | back → Reminders |
| Reminder complete (sheet) | Reminders, push action | Scan invoice / Type → ServiceEntry · Skip | dismiss → Reminders |
| Anomaly dismiss (sheet, P6.1b) | the Log's anomaly card → **Dismiss with reason** (J9) | preset reasons / free text → records an `AnomalyDismissal` (the card leaves for that cause) | swipe-down / after recording → Log |
| Recently deleted | Settings (and Log overflow menu) | Restore (in place: tombstone cleared, entry back in Log) · Compare (presentational until the merge log lands, P4) | back → Settings |
| Settings | Home gear | account, import, export (system), recently deleted, Pro, About | back → Home |
| Account & devices (P6.4) | Settings account card (signed in) | device list (revoke) · Delete account (tombstone; the log on this phone is never touched) | back → Settings |
| About & feedback | Settings | identity header (icon, name, version) · the update row (`.recommended`, dismissible; App Store link only when a compiled-in app id exists) · feedback/rate/privacy (later tasks) | back → Settings |

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

## Screens referenced but not yet drawn

The map names screens that exist as nodes but have no artboard yet – listed so they're planned, not forgotten: **Paywall** (Pro). Each already has its journey and schema defined; only pixels are missing. (**Garage tab root** and **Account & devices** left this list on 2026-08-29: P6.4 built both. The Garage tab root has no artboard, so it follows the Car switcher sheet's vehicle-card language (42pt tile, name + selected dot, one-line vitals in the car's own units, dashed Add car tile, footer invariant) as a full tab root with each card leading to Vehicle detail. Account & devices has no artboard either, so it follows the Settings card conventions - identity header, a devices card with one row per server device, a delete-account row whose confirmation states the tombstone truth from `site/delete-account.md` (server copy removed after the grace period; the log on this phone is never touched).) (**Import wizard** left this list on 2026-08-27: it is drawn as three artboards - `ImportSource.dc.html` (which app is this file from, with the **server-driven** supported list), `ImportPreview.dc.html` (the F6a gate: figures the user can check from memory, target car, duplicate count, and nothing written until confirm) and `ImportReview.dc.html` (the F6 rows that need a look). The flow is **Settings -> Import -> source -> file -> preview -> [rows to fix] -> commit**, and every step backs out to the one before it; **Cancel** from the preview returns to Settings having written nothing and deleted the stored parse.) (**Vehicle detail** was in this list until P1.12 made it real: per-car settings, archive/unarchive (J13) and delete now live there; it has no separate artboard yet, so it follows the shared Add-car layout and the DESIGN.md one-row header. **Reminder form** was in this list until **P3.4** drew it from the DESIGN.md tokens and the ServiceEntry form it sits beside – it has no dedicated artboard and follows that form's card metrics, eyebrow labels and field underlines. **Tire sets** was added in **P3.3** – no artboard, so the list and its name form follow the Reminder list/form's card metrics, eyebrows and underlines.)

## Dead-end audit

- Every sheet dismisses (swipe + explicit control); every pushed screen has chevron + edge-swipe; tab roots are roots by definition. ✓
- **Restoring** was the one screen that could trap (mid-restore, wrong account): it gets an explicit *Cancel = sign out → Welcome*. ✓
- **Save never strands**: all save actions land on Home/Log with the result visible – capture opened from Trends still exits to Log, showing what was created. ✓
- **Failure states are forks, not ends** (JOURNEYS F-series): OCR failure → ConfirmManual is the same sheet, same back paths; denied camera → Capture's "Type it" path still works. ✓
- **Manual entry is a peer path, not a failure branch** (hard rule 15). "Type it" is offered
  next to capture at every entry point - Home's header, both empty states, the guest layout and
  the Capture screen itself - and reaching it never requires first attempting a scan. It is the
  same `ConfirmManual` sheet either way, so a user who starts manually and one whose scan came
  back thin end up in the identical screen, editing the same fields.
- **Confirm takes a `ConfirmPrefill` (P2.3)**: the extraction pre-fills present fields, nil
  fields stay blank and focusable, and an all-nil extraction IS the ordinary manual form -
  never an error, never a "scan failed" banner (the two doors stay equal). Resolved-but-
  unconfirmed fields render at 60% opacity (docs/DESIGN.md) and remain fully editable
  (hard rule 13); the magnifier on such a field opens the source-image crop it came from
  (tap-to-verify), degrading to a no-op when no crop is attached. A fiscal QR anchor
  outranks the OCR total (docs/SCHEMA.md -> FISCAL QR): `.disagrees` fills the QR total,
  a mixed receipt keeps the fuel line (hard rule 4), and the difference is P2.4's job.
- **Notifications deep-link** into Reminders/Home – both roots with full navigation, never into a bare sheet with no context. ✓
- Welcome is unreachable after onboarding except via Restoring's cancel and full sign-out – intentional; it is not part of the daily graph. ✓

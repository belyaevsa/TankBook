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
| Home (incl. guest/empty state) | tab root | gear, car card, banner, entries, capture | tab root – no back |
| Capture | center button (any tab), GuestHome CTA, notification deep links | mode-dependent confirm sheets | X → opener |
| Confirm / Foreign / Mixed / Manual | Capture result | Save → Home + toast · tank row → TankLevel | back → Capture (photo kept) · swipe-down discards scan (photo re-offerable) |
| Tank level (sheet) | Confirm's tank row | Set / Skip → Confirm | swipe-down = Skip |
| Service & expenses | Capture (Service mode), ReminderComplete | Save → Home | X → opener (typed input asks first) |
| Edit entry | Log entry, duplicate/conflict cards, RecentlyDeleted | Save / Delete → Home · photo → viewer · Restore my version | X → opener |
| Trends | tab root | insight cards → (chart detail, planned) · capture | tab root |
| Garage | tab root | vehicle → VehicleDetail · Add car · capture | tab root |
| Vehicle detail (P1.12) | Garage vehicle, Car switcher archived row, limit sheet "Archive a car" | Save changes → back · Archive/Unarchive (in place) · Delete → system confirm → Recently deleted (entries restorable) | back → Garage (or opener) |
| Car switcher (sheet) | Home car card/chip | pick → Home · Add car · archived → VehicleDetail | swipe-down → Home |
| Reminders | Home banner, VehicleDetail, push notification | complete → ReminderComplete · New reminder → form | back → opener |
| Reminder complete (sheet) | Reminders, push action | Scan invoice / Type → ServiceEntry · Skip | dismiss → Reminders |
| Recently deleted | Settings (and Log overflow menu) | Restore (in place: tombstone cleared, entry back in Log) · Compare (presentational until the merge log lands, P4) | back → Settings |
| Settings | Home gear | account, import, export (system), recently deleted, Pro, About | back → Home |
| About & feedback | Settings | Send feedback (stays, toast) · rate/privacy links | back → Settings |

## Screens referenced but not yet drawn

The map names five screens that exist as nodes but have no artboard yet – listed so they're planned, not forgotten: **Garage tab root** (vehicle grid; today Car switcher covers quick switching, but the tab needs a real screen), **Import wizard** (J2/F6 – source picker, file, preview-verify, partial-import review), **Reminder form** (new/edit reminder), **Account & devices** (Settings' signed-in account target; device list + revoke + delete account), **Paywall** (Pro). Each already has its journey and schema defined; only pixels are missing. (**Vehicle detail** was in this list until P1.12 made it real: per-car settings, archive/unarchive (J13) and delete now live there; it has no separate artboard yet, so it follows the shared Add-car layout and the DESIGN.md one-row header.)

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
- **Notifications deep-link** into Reminders/Home – both roots with full navigation, never into a bare sheet with no context. ✓
- Welcome is unreachable after onboarding except via Restoring's cancel and full sign-out – intentional; it is not part of the daily graph. ✓

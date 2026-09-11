# RV.239 - the import rows on both restore-failure screens are dead links

**Scenarios: F7 · restore fails or comes back empty (source 3), J11 · new phone.** The only v1 row
holding F7 open. A **bug** on the screen that exists to prevent data loss.

`RestoreFailureViews.swift:72` (empty restore) and `:194` (backend unreachable) render
`NavigationLink(value: Route.importWizard)`. They live inside the sign-in **sheet**
(`SettingsView.swift:69`, `.sheet(isPresented: $showsSignIn`), and the app's only
`navigationDestination(for: Route.self)` is on the tab roots (`TabRoots.swift:577`). A
`NavigationLink(value:)` with no destination in its own stack does nothing on tap. Found by F7's
walk, verified by the orchestrator. `RV.164`'s guard did not see it: the route exists in
`SCREENMAP.md`; the link is unreachable from a sheet.

## Build

Make both rows open `ImportWizardView`. **One way, and say why**: present the wizard as a sheet
from the failure view; or give the sheet host (`SignInFlowHost`) a `NavigationStack` with the
Route destination; or route through the host's `onNavigate` callback if one exists. Check
`HomeGuestLayout.swift:220` and `SettingsView.swift:324` - the same link on screens that DO have
the destination - so the fix does not diverge the four.

Then add to `ErrorRouteScanner`'s notes (the `RV.164` guard) the stated blind spot: it proves a
named route exists, not that a link reaches it from where it is rendered. If a cheap check exists -
a `NavigationLink(value:)` inside a file that also declares `.sheet` and no `navigationDestination`
- add it; if not, say why.

## Tests

- **L4 `SignInUITests` EN + RU, FAILS TODAY**: seeded empty restore -> tap *Import a file you
  exported yourself* -> `ImportWizardView` is on screen. Same on the unreachable screen with
  *Import a file*. The identifiers exist; check `RestoreFailureViews` for them.
- Frames of the two failure screens are already committed under `P4`/`PJ` names - re-shoot only if
  layout changes.

## Mutation - named

Restore the bare `NavigationLink(value:)` on one screen; its L4 goes red. Verbatim, byte-identical.

## Vacuous trap

Asserting the row is hittable. It was hittable before; it did nothing.

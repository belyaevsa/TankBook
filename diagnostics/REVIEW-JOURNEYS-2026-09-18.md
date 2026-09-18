# REVIEW-JOURNEYS run, 2026-09-18 - Groups A, B, C, D (the rows since the 2026-09-13 walk)

**Walked by:** the orchestrator · **Tree:** `66576113` · **Since:** the 2026-09-13 walk (`c11f1099`); **55 commits, 17 rows shipped** in between - `RV.279`, `RV.280`, `RV.281`, `RV.282`, `RV.284`, `RV.285`, `RV.286`, `RV.291`, `PJ.29`, `PJ.29a`, `SH.1`, `P6.6` (the 09-13/15 session), `RV.293`, `RV.294` (the rejection and the machine), `PJ.15`, `PJ.30`, `PJ.35`, `PJ.24`, `PJ.21`, `PJ.31` (the 1.1 tranche). The walk is the re-run shape: each shipped row against the four event shapes, the ticked rows re-checked, then Pass 1 and Pass 2 over the six new surfaces.

## 1. Re-check of what the previous run left open

| Item | Then | Now |
|---|---|---|
| J4 without a status line (owner photographs `RV.114`, `RV.179`) | open | unchanged; `RV.288`-`RV.290` (the owner's pump photograph, 2026-09-16) added three rows to the same journey, all open |
| J8b / J13 held on `RV.181`'s device step | open | unchanged (the owner's second device report is in `RV.181`) |
| Tire-set creation at the purchase moment | owner question | unchanged |
| `PJ.300` (service line item's home money) | filed | open, owner decision |

## 2. Ticked rows whose behaviour the code does not have

**None.** Re-checked by grep today: `RV.281` (*затраты* - 12 catalogue hits, no *расход* for an expense), `RV.284` (migration 023 present, two files), `RV.285` (`HttpClientTimeouts.cs`, `LlmService.cs`), `PJ.29` (`CaptureExpenseScan.swift` reaches the gateway), `RV.293` (`AppleSignInButton` wraps the system control; the light captures exist), `RV.294` (`withSlot` is `async`, no synchronous `recognizeText` remains - grep: none). The six tranche rows were mutation-gated at ship and their captures opened the same day.

## 3. The four event shapes over the 17 rows

| Shape | Rows it applies to | Finding |
|---|---|---|
| 1 · a screen or route ships | `PJ.21` (a new **entry path**: the system share sheet → ImportWizard), `PJ.24` (a door on ReminderComplete), `PJ.31` (a card on Trends) | All three are production code, none under `#if DEBUG` (`sharedFileOpener`'s `onOpenURL` is unconditional; `-openFile` is the only DEBUG part). `SCREENMAP.md` had no edge for the share-sheet entry - **added in this walk** (`ShareSheet --> ImportWizard`). `ScreenRouteBindings` green |
| 2 · a reader of an entity ships | `PJ.31` reads `Station.brand`; `PJ.35` reads `Attachment` rows without a rendition; `PJ.30` reads `Segment`s | **`Station.brand` has no writer in production** - only test seeds and the schema; `StationSettingsView` displays it when present and `RV.115`/`RV.180` (`[v1.1]`) are the brand vocabulary and the brand/site split. `PJ.31` falls back to the station's name, by design, so in v1 "brand" is per-station and two Shell sites are two rows. **Cited, not filed** - it is `RV.115`'s deliverable; `PJ.31`'s row and J8's note now say so. Attachments and segments have their creators |
| 3 · copy naming a destination or outcome ships | `PJ.24` ("scan the invoice or type a total" → ServiceEntry, both doors exist), `PJ.15` (the toast's tap → Trends, `TabRoots.swift` `tabSelection = .trends`), `PJ.21` ("Choose a different file" → the picker), `PJ.35` (`SYNC.md`'s "the prefetch it starts on a WiFi change") | The first three name things that exist. `SYNC.md:596` named a **WiFi-change trigger the prefetch does not have** (it starts after a pull or a restore) - **fixed in this walk** |
| 4 · a row ships PARTIALLY | `PJ.24` (expense-kind reminders keep the typing door only), `PJ.21` (no `UTImportedTypeDeclarations`), `PJ.35` (no WiFi-change trigger) | `PJ.24`'s remainder is filed (`RV.298`); `PJ.21`'s omission is deliberate and explained in `project.yml` (system types need no declaration); `PJ.35`'s trigger set - after a pull, after a restore - is what J11 promises, and the doc sentence was the drift, not the code |

## 4. Pass 1 - reachability from a cold launch, no debug flag

- The share-sheet entry: `CFBundleDocumentTypes` is in the generated `Info.plist` (Release build green); `onOpenURL` on the root; a read failure opens nothing rather than a wizard with no file (`ImportShareInbox.receive` → false).
- The scan door: rendered for `.service` reminders by `ReminderCompletion.entryKind`, which is the same switch the typing door uses.
- The insight toast: posted from the one `ManualFillUpView.save()` both the typed and the scanned Confirm run (`RV.12`); the lost-photo notice still outranks it.
- The hero arrow and the brand card: derived on every Trends render from `TrendsStats`, no flag.
- The prefetch: started from `SignInFlow.makeDefault` (both the DEBUG and the release branch set `startPhotoPrefetch`) and from `AppSync.runCycle` after `pulled > 0`.

## 5. Pass 2 - sequence

| Chain | Status | Evidence |
|---|---|---|
| save → insight → edit → delta toast | MET | the two toasts are two derivations on the same engine; an edit that moves the headline posts `EditConsumptionDelta`, a save posts `AfterSaveInsight`; neither fabricates (both `nil` paths asserted at L1) |
| restore → prefetch → open an entry whose photo failed | MET | a failed blob stays pending (`BlobPrefetchOutcome.completed(fetched:failed:)`), and the entry's own `fetchPendingBlobs` retries on open (`EditEntryView+EntryResolution.swift:155`) |
| a tombstoned attachment | MET | `BlobPrefetchPlan.newestFirst` skips `deletedAt != nil` |
| a shared file, then Cancel | MET | the staged copy is disposed on "Choose a different file" and after the parse (`ImportFlowModel+Wizard.swift` `parseSharedFile`); a second wizard opening finds no file (`take()`) |
| a reminder completed through the scan door on a device with no camera | MET | `VNDocumentCameraViewController.isSupported` gates the presentation; the entry still opens pre-filled |
| a rate-pending fill in the brand comparison | MET | `HomeStats.unitPriceFigure` returns nil and the fill is left out, never counted at a guessed price (`BrandPricesTests`) |
| the MPG car through every new figure | **GAP, tracked** | `PJ.15`'s toast, `PJ.30`'s tile and `PJ.31`'s card all print `per100`/L-based figures under the car's unit label, exactly as Home and Trends already did - `RV.296`, filed during `PJ.15` |

## 6. Proposed rows

None new. Everything the walk found is either filed today (`RV.296`-`RV.299`), already a row (`RV.115`/`RV.180`, `PJ.300`, `RV.181`, `RV.114`/`RV.179`), or a doc drift fixed in this change (`SCREENMAP.md` edge, `SYNC.md:596`).

## 7. Cited, not re-filed

`RV.115`/`RV.180` `[v1.1]` (brand vocabulary - the reason PJ.31 is per-station today) · `RV.296` (units) · `RV.297` (price tile) · `RV.298` (expense scan door) · `RV.299` (a pre-existing Import test red on iOS 27) · `RV.181` [~] (J8b, J13) · `RV.114`, `RV.179`, `RV.288`-`RV.290` (J4) · `PJ.300` (owner) · `RV.295` (iOS 27 OCR measurement) · tire-set at purchase (owner).

## 8. Could not settle

- Whether `RV.296` should land before the next TestFlight build: every figure a miles/gallons car sees is wrong by a unit, and `RV.134`'s class was treated as a launch blocker. Owner's call on priority; the row is written.

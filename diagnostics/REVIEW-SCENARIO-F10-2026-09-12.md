# REVIEW-SCENARIO run: F10 – 2026-09-12 (first walk)

- **Scenario:** F10 – Sync conflicts surface after the fact (`docs/JOURNEYS.md`)
- **Run id:** REVIEW-SCENARIO-F10-2026-09-12
- **Read-only** except this report and, on IMPLEMENTED, the status line.

---

## Verdict

**IMPLEMENTED** – every v1 promise is MET, except the S5 "came back, stays archived" notice,
which is fixture-only and **reasoned N/A**: it is explicitly deferred to v1.1 by `PJ.40` and
`PJ.59`'s own closeout names it "the same fixture shape – [v1.1], its own decision"
(`docs/TASKS.md:858`).

## Ticked rows found to be untrue

None. Both rows closed today verify as real:

- **PJ.59** (`[x]` 2026-09-12): the "Overwritten by sync" section now reads the real
  `syncOverwrite` log. Writer `SyncEngine.applyPull`/`resolveConflict` →
  `recordSyncOverwrite` (`SyncEngine.swift:320,613`); reader `syncOverwrittenEntries()`
  (`Repository+Sync.swift:308-317`); render `RecentlyDeletedSyncOverwrites.rows`
  (`RecentlyDeletedSyncOverwrites.swift:30-39`) into `RecentlyDeletedView.swift:161-175`.
  The action is real: "Restore my version" → `restoreSyncOverwrite` (`Repository+Sync.swift:344-370`).
- **RV.253** (`[x]` 2026-09-12): quota card fed by the real 429 (`blob_quota_exceeded` body
  carries `quotaUsedPercent`), not `forcedQuotaPercent`. Out of F10's own promises (transport
  card, J11) – verified as context, no F10 clause depends on it.

Earlier rows named in the context are also true on re-walk: **PR.14** (the "Changed by sync"
row + the post-batch toast read real data – `EditEntryRows.swift:119-133`, `HomeView.swift:214-241`),
**RV.162** (ScreenRouteScanner; every SCREENMAP screen has a non-DEBUG door), **RV.70** (Pro
entry points removed). None is the subject of F10's promises; none is untrue.

## Promise-to-code map

Journey text (`docs/JOURNEYS.md:741-744`) walked clause by clause, then S1–S9 to the surface.

| Clause / scenario | Surface | Status | Citation |
|---|---|---|---|
| S3 amber timeline flag on entry | warn triangle + chevron badge on conflicted Log rows, driven by `entry.isConflicted` (a decoded `ConflictState`) | **MET** | `HomeSections.swift:471-480` (`conflictBadgeButton`), `:497-501`; `TimelineValidator.swift:12-64` |
| S2 "possible duplicate" combined card | one card showing both members + Merge / Keep both | **MET** | `HomeDuplicateCard.swift:16-90`; built from `LogStream.DuplicateGroup` (`LogStream.swift:137-145,350-369`) |
| S2 actions are real writers | Keep both → `upsertDuplicateResolution`; Merge → `DuplicateMerge.merge` + soft-delete loser | **MET** | `HomeView.swift:351-366` (resolve), `:371-385` (merge); `Repository.swift:495-520` |
| S5 quiet notice "came back… stays archived" | domain resurrect real; **notice is a fixture with dead buttons** | **N/A** (deferred v1.1) | domain: `SyncEngine.swift:400-405` + `Repository+Sync.swift:256-265`; fixture: `HomeBanners.swift:28-61` (buttons `{}` at `:47-48`), `HomePresentation.swift:27-36`. Owning row **PJ.40** `[v1.1]` (`docs/TASKS.md:825`) |
| Batch-after-outage summary toast | "Synced. N entries need a look" from the real `outcome.flaggedEntries`, tap → filtered Log | **MET** | `AppSync.swift:648`; `HomeView.swift:107-108,214-241`; `Route.flaggedEntries` → `FlaggedEntriesView` |
| Nothing lost silently: overwritten edits | 30-day `syncOverwrite` undo log, "Changed by sync" row + "Restore my version" on the entry's edit screen | **MET** | `Repository+Sync.swift:287-305,344-370`; `EditEntryRows.swift:119-133`; `EditEntryView.swift:491-505`; `EditEntryNonFillView.swift:87-89` |
| Nothing lost silently: deleted entries | tombstone + "Recently deleted" 30-day window, incl. the "Overwritten by sync" section | **MET** | `RecentlyDeletedView.swift:161-175`; `RecentlyDeletedSyncOverwrites.swift:30-39`; `TombstoneCountdown.daysRemaining` |
| Stats honest: duplicate counts once | counted/excluded member split, one derivation | **MET** | `HomeStats.swift:125-127`; `EntryExclusion.swift:46-67` |
| Stats honest: flagged entry excluded + Trends footnote | "N entries excluded" footnote, derived | **MET** | `TrendsView.swift:90-96`; `HomeStats.swift:92-98,153-156`; `EntryExclusion.swift:46-67` |
| Server down = non-event, passive row | Settings "Waiting to sync · N changes" (`inkSoft`, never amber) | **MET** | `SettingsView.swift:245-263`; `L10n.waitingToSync` |
| No sync-gated screen | every surface is passive/badge; no modal sync surface | **MET** | chip `SyncStateChip.swift`, Settings row, Home toast, badges – no modal anywhere |
| Settings "N entries need a look" count + link | derived, never stored, taps to filtered Log | **MET** | `SettingsView.swift:670-691`; `Repository+FlaggedEntries.swift:12-30`; `AppSync.swift:380` |

S1–S9 walk (the "surface the user actually sees" per `docs/SYNC.md`):

| S | Surface | Status | Citation |
|---|---|---|---|
| S1 (edit vs edit) | "Changed by sync · restore my version" row + Recently deleted section | **MET** | `EditEntryRows.swift:119-133`, `RecentlyDeletedSyncOverwrites.swift` |
| S2 (duplicate) | combined card, Merge/Keep both | **MET** | `HomeDuplicateCard.swift`, `HomeView.swift:351-385` |
| S3 (out-of-order) | amber badge + excluded footnote + F9a ranked fixes | **MET** | `HomeSections.swift:471-480`, `TrendsView.swift:90-96`, `F9aFixRow.swift` |
| S4 (edit vs delete) | resurrect is silent; delete → 30-day undo | **MET** | same `syncOverwrite` log as S1; `RecentlyDeletedView` |
| S5 (vehicle resurrect) | resurrect-as-archived real; notice fixture-only | **N/A** (PJ.40 v1.1) | `Repository+Sync.swift:256-265` vs `HomeBanners.swift:28-61` |
| S5a (delete cascade) | internal, no surface; RV.101 | **MET** | `SyncEngine.swift:400-405` (`remoteDeleted` guard) |
| S6 (transport conflict) | plumbing, nothing ever | **MET** (by absence) | `SyncEngine` re-merge/re-push |
| S7 (server down) | passive Settings row + recovery toast | **MET** | `SettingsView.swift:245-263`, `HomeView.swift:214-241` |
| S8 (currency backfill) | home amount appears, no toast | **MET** (by absence) | `MoneyBackfillService.demandDrain` |
| S9 (stale device) | nothing – the point | **MET** (by absence) | field-level `Vehicle` merge (`SYNC.md` S9) |

## Sequence trace

One user, two devices, server out, conflicts in a batch:

1. Server down → both devices keep writing; writes queue dirty. Settings shows "Waiting to
   sync · N changes" (`SettingsView.swift:252-257`). **Fact carried.**
2. Server recovers → pull → merge → push.
3. Merge overwrote a local edit (S1) → `recordSyncOverwrite` (`SyncEngine.swift:320`) → the
   edit screen shows "Changed by sync · Restore my version" and Recently deleted shows the
   "Overwritten by sync" section. **Fact carried.**
4. Two entries are one fill-up (S2) → combined card, Merge/Keep both write a real resolution.
   **Fact carried.**
5. Out-of-order odometer (S3) → `TimelineValidator` flags → amber badge → excluded footnote →
   F9a ranked fixes. **Fact carried.**
6. The last cycle's `outcome.flaggedEntries > 0` → Home toast "Synced. N entries need a look"
   (`AppSync.swift:648` → `HomeView.swift:107-108`) → tap → `Route.flaggedEntries` →
   `FlaggedEntriesView` (reads live `conflict != .none`, `FlaggedEntriesView.swift:286-306`).
   **Fact carried.**
7. **The one break:** archived car resurrected from a pull (S5) → `resurrectArchivedIfTombstoned`
   sets `archived=1` in the DB (`Repository+Sync.swift:256-265`) – but no production UI reads it.
   `HomePresentables.archivedReturned` is set only by `-forceArchivedReturned`
   (`HomePresentation.swift:35`), and the card's "Delete again"/"Keep" are empty closures
   (`HomeBanners.swift:47-48`). **The resurrection fact stops being carried to the user** – the
   car silently reappears archived with no "Delete again?" decision point. Owned by **PJ.40**
   `[v1.1]`; not re-filed.

## Proposed rows

None. The single non-MET surface (the S5 notice) is already owned by **PJ.40** (`[v1.1]`,
`docs/TASKS.md:825`), which names the exact fix: a device-local notice table written by
`resurrectArchivedIfTombstoned`, working "Delete again"/"Keep", delete the fixture. Re-filing it
would duplicate the row.

## Unsettled

- **`HomeSyncToast` (`HomeBanners.swift:214-233`) is now dead code in production.** It hardcodes
  "Synced. 2 entries need a look" and renders only when `-forceSyncToast` is passed AND no real
  batch flag exists (`HomeView.swift:109-110`). The real toast (`syncFlaggedToast`) superseded it.
  Harmless (never reachable without a DEBUG flag) and the boolean-fixture shape is deliberately
  outside `DebugFixtureSectionScanner`'s scope (`docs/TASKS.md:858`), so nothing fails on it. Not
  filed: no user-facing gap, and folding it into a PJ.40-style "delete the fixture" pass would be
  the natural home if one is wanted.
- **F10's S5 clause is unmarked (v1) in the journey text while PJ.40 defers the real notice to
  v1.1.** The journey promise and the row disagree about the version marker. This is the same
  tension the "journey completes without them" v1.1 tier resolves by convention, not a code gap.
  Left to the product owner: either the journey's S5 clause is accepted as a v1.1 deliverable
  (PJ.40), or the clause should read the v1.1 marker. I did not edit the journey text beyond the
  status line – that decision is a product call, not a review finding.

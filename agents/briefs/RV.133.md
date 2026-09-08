# RV.133 - swipe to accept or delete on "Needs a look"

You are working in `/Users/sbelyaev/repos/fuel-counter-ios`. **Write only inside that repo.**
Write code first, explore second. Do not commit; the orchestrator commits after verifying.

## What was asked

Product owner, 2026-09-07: *"let's add a swipe gesture that allows either to delete the entry or to
accept it. With no comments, actually. The user don't need to write it. Deletion must be confirmed."*

## Where it lands, measured

`ios/App/Sources/Settings/FlaggedEntriesView.swift` (246 lines). Today each row is:

```swift
HStack(spacing: 0) {
    NavigationLink(value: Route.editEntry(row.id)) { ... }   // :100 - the whole-row tap
        .accessibilityIdentifier("flaggedEntryRow")
    Button { pendingAccept = row } label: { Text("Accept") }  // :127-140
        .accessibilityIdentifier("flagAcceptButton")
}
```

and Accept opens an **alert** (`:76-79`) carrying an **optional** reason `TextField`. So clearing a
flag the user already understands costs tap, read a dialog, tap again. **Delete is not offered here
at all**, so an entry flagged *because it is junk* must be hunted down in the Log to remove.

## Three facts that decide the work. Confirm each, then act.

### 1. This is NOT a `List`, so `.swipeActions` is unavailable

The surface is `ScrollView -> VStack -> ForEach(rowCard)` with `formCard()` styling (`:47-58`), and
SwiftUI's `.swipeActions` exists **only inside a `List`**. **Nothing in the app uses `.swipeActions`
today** - there is no in-repo pattern to copy. Decide and state which you did:
- convert the surface to a `List` and re-match `docs/DESIGN.md`'s card treatment (which is *why* it
  is not a `List`), or
- implement the drag gesture directly.

### 2. A hand-written drag gesture here has a THREE-WAY conflict

The row wraps a `NavigationLink` (a tap), sits inside a vertical `ScrollView` (a vertical drag), and
you are adding a horizontal drag. Getting this wrong does not fail a test - it makes the list feel
broken: rows that navigate when you meant to swipe, or a list that will not scroll. If you write the
gesture, it must be a horizontal-biased drag that yields to vertical scrolling, and **the whole-row
tap into the editor must still work**. Assert both.

### 3. `Row` does not carry the entry's kind, and delete needs it

`Row` is `{ id, title, subtitle, date }` (`:37-44`). Deletion is per entity type -
`softDeleteFillUp(id:at:)`, `softDeleteChargeSession`, `softDeleteServiceRecord`, ... in
`Repository.swift`. So a delete action must resolve the entry's type first. Extend `Row`, or resolve
through the repository - say which and why.

## Design questions ALREADY CLOSED

1. **Accept needs NO confirmation and NO reason.** It is reversible: RV.104 records the acceptance
   per entry, it stays visible, and it is re-checked later (hard rule 8). A dialog on accept is the
   ceremony this row exists to remove.
2. **Delete IS confirmed, once**, and goes through the **soft-delete** path so it lands in
   Recently deleted with the 30-day undo (hard rule 8, `DeletedEntries.swift`). **A hard delete is a
   defect**, and it is the one a swipe path can most easily reach by accident.
3. **The existing Accept button and its optional reason STAY.** RV.104 chose to keep a reason
   deliberately (the `AnomalyDismissal` precedent). The swipe is a faster second door, not a
   replacement; removing the reason path would undo a decision for no reason.
4. **Both actions need accessibility actions.** A swipe-only affordance is unreachable for VoiceOver
   and Switch Control - `docs/DESIGN.md`'s accessibility floor is not optional, and nothing in this
   app uses `accessibilityAction` yet, so you are setting the precedent.
5. **No merge here, and this is a recorded decision, not an oversight.** Merge needs a PAIR; this
   surface shows single entries carrying timeline flags, and `Row` does not even carry the flag
   kind. Duplicate pairs live on Home as a `DuplicateGroup` card, which [RV.131] has just rebuilt.
   Do not add a third action whose meaning is undefined for most rows here.

## Copy

Any new string is **one full localised phrase per language**, EN + RU in `Localizable.xcstrings`,
never concatenation. The delete confirmation names what is being deleted and that it is
recoverable - hard rule 7 wants the next step, and "Recently deleted" IS the next step. Russian runs
20-30% longer and short strings expand worst; a two-action swipe tray is exactly where that bites.

## Explicitly out of scope

- The flag engine, `DuplicateDetector`, and which entries become flagged.
- The Log, Garage, and Recently deleted surfaces.
- Bulk accept or bulk delete - RV.104 states there is deliberately no bulk accept.

## Docs to read before writing (in order)

1. `CLAUDE.md` - hard rules 7, 8, 10, 13.
2. `docs/ERRORS.md` -> the flagged-entries surface (**the authority for the copy**).
3. `docs/DESIGN.md` -> the accessibility floor and the card treatment.
4. `docs/SYNC.md` -> tombstones and the 30-day undo.
5. `docs/SCREENMAP.md` -> where this screen sits and its back path.

## Checks

Baseline: `main` is green at **1645 tests / 184 suites**, **774** localization keys, `swift build`
0, `swiftlint` 0 errors **from the repo ROOT**. Rows are landing around you - **re-measure the
baseline yourself** and report what you observe, including any failure that is not yours.

1. `cd ios && swift build` - 0.
2. `swiftlint lint` from the **repo ROOT** - 0. Root-relative `excluded:` paths.
3. `cd ios && swift test` - full, never subsetted; report the number.
4. `xcodegen generate` + the UI suites you touched **by name**; report a non-zero observed count -
   a filter matching nothing prints "0 tests ... passed".
5. Localization gate - 0, 100% RU, report the key count.
6. Release build - required if you touch a `#if DEBUG` seam. Say which applies.

### Tests you must add

- **L4**: a swipe accepts with **no dialog**, and the row leaves the list.
- **L4**: a swipe to delete shows exactly **one** confirmation; **cancelling leaves the entry
  untouched and still flagged**.
- **L1**: a deleted entry is **tombstoned and recoverable** - assert it appears in Recently deleted,
  not merely that it vanished from this list. A hard delete passes the "it disappeared" test.
- **L4**: the whole-row tap still opens the editor, and the list still scrolls (fact 2).
- **L4**: both actions are reachable as **accessibility actions**.
- **L4**: the existing Accept button and its optional reason still work.

### Vacuous traps, named

- Asserting the gesture is attached rather than that the row was **accepted or deleted**.
- A delete that **hard-deletes** because the swipe path skipped the soft-delete call - the row
  vanishes and a naive test passes.
- Removing the reason field, which undoes RV.104 deliberately.
- Shipping swipe-only with no accessibility action.
- **A confirmation on ACCEPT** - that is the ceremony this row removes.
- Testing the gesture without testing that the row tap and the scroll still work.

## Screenshots

The flagged list with the swipe tray open, dark, EN and RU:
`design/screenshots/RV.133-flagged-swipe.png` and `-ru.png`. Pass the reset flag alongside the seed;
seeds are idempotent and silently do nothing on a populated database. RU:
`xcrun simctl launch <device> app.tankbook.Tankbook -AppleLanguages "(ru)" -AppleLocale ru_RU`.
Take them **outside** a test run, and **OCR your own capture and read the text back** - a committed
screenshot has twice shown the opposite of its row's claim. Both actions must be legible in RU
without truncation.

## Never `pgrep -f` for a build process

Your brief is part of your command line. Use `pgrep -x xcodebuild`. Never `pkill -f`.

## Report back

Every check with the **exit code you observed**, whether each test was **run or only written**,
which of the two implementations you chose for fact 1 and why, and how you resolved the entry type
for delete (fact 3). Name any closed decision you think is wrong and stop there rather than
absorbing it.

# RV.45 – show what the receipt read against what the user entered, and let them choose per field

The product owner, 2026-09-04: *"worth to show to a user recognized data (volume, price, date, gas
type) - what will be replaced and will it be replaced anything? The user should see what they have
entered and what will be updated after recognition to make a decision."*

## Where you may write

Only inside `/Users/sbelyaev/repos/fuel-counter-ios`. **Do not run `git add` or `git commit`.**
**Do not touch `docs/TASKS.md`.**

**Touch no `backend/`, `Auth/`, `SignIn/` or `Settings/` file** - another agent is working on the
account lifecycle (RV.40/39/41) in this same checkout right now. Your work is `ios/App/Sources/Inbox/`,
`ios/Sources/TankbookCore/Inbox/`, their tests, and docs.

**Use the `iPhone 17 Pro` simulator for every xcodebuild/xcrun step** - the other agent has
`iPhone 17`, and `simctl`/`xcodebuild` fight over a shared device.

## The defect under the request is worse than the missing display - verify it, then fix both

`ios/Sources/TankbookCore/Inbox/GatewayInboxPolicy.swift`:

- **`fillableFields` can only ever return `.unitPrice`.** On a SAVED `FillUp` the other fields are
  never blank - `volumeL`, `date`, `fuelKind` and `money` are non-nil by construction, and the
  function's own doc comment says exactly that.
- **`shouldOffer` fires on `fillableFields` OR `hasDifference`**, and `hasDifference` compares
  total, volume, unit price, fuel kind, currency and date.

**So the commonest inbox item is a disagreement, and for every one of those `merged()` changes
nothing at all.** The card offers "Update from the receipt" as a prominent action that is a
**guaranteed no-op**, showing the user nothing about what differs.

That is **hard rule 7** (an action must name what it actually does) stacked on the missing
information. And **the disagreement is the most valuable thing the scan produced** - a receipt
reading 47.30 L against a typed 42.30 L is precisely the typo the camera exists to catch. Today it
is computed, used to justify showing the card, and then thrown away unshown.

## What to build - decided 2026-09-04 by the product owner: PER-FIELD

The card lists every field the receipt read - **date, fuel kind, volume, unit price, total,
currency** - as **yours vs the receipt**, marks which differ, and lets the user tick **per field**
what to take.

**This is the only option compatible with hard rule 13, and it IS compatible.** Rule 13 forbids the
*app* overwriting a user's value (*"no catalog update, sync merge, re-scan or later curation may
overwrite it"*). A per-field tick is the **user** deciding - which the same rule explicitly requires
be possible (*"editable at the moment it is offered and again afterwards"*). Accept-all was
considered and **rejected**: one tap discarding typed entries is exactly what the pre-RV.38 drop
existed to prevent.

## The honesty requirements are the hard part, not the table

1. **A field that matches is not a decision.** Show it as agreement, or not at all - never as a
   choice the user must consider.
2. **If nothing would change, the card must say so**, and must **not** offer an action that does
   nothing. This is the no-op case above; it is the single most important line of this task.
3. **Filling a blank and replacing a typed value are different acts and must read differently.**
   Filling an empty price is not "replacing" anything; taking the receipt's volume over the user's
   is. The copy must not flatten them into one word.
4. **Values render per `docs/DESIGN.md`**: DIN numerals, `tabular-nums` so a comparison lines up
   column-wise, money **amount-then-symbol separated by U+00A0** (`68.46 €`, never `€68.46`), and
   the odometer/thousands separator rules if you show one. A comparison table is exactly where
   mis-aligned digits are most obvious.
5. **"Leave it as it is" stays the default and keeps its prominence** (RV.38, and the product
   owner's own correction to that card). Do not re-invert it.

## Explicitly out of scope

- The bell, the badge, the outbox and the drain (RV.38/RV.44) - all correct, leave them.
- Any `backend/` change. The extraction already arrives with everything you need.
- Re-running OCR. This presents stored data (hard rule 13: the viewer never re-reads).

## Read before writing

1. **`CLAUDE.md`** - hard rules 7 (an action names its next step), 8, 10 (whole localised phrases,
   never concatenation), 12, **13 (the whole basis of this design)**, 14.
2. `docs/DESIGN.md` - numerals, money rendering, the accessibility floor.
3. `docs/JOURNEYS.md` → **F4** (amended by RV.38), `docs/ERRORS.md` → the Inbox section.
4. `ios/Sources/TankbookCore/Inbox/GatewayInboxPolicy.swift` (`fillableFields`, `merged`,
   `hasDifference`, `shouldOffer`), `ios/App/Sources/Inbox/InboxView.swift`,
   `ios/App/Sources/Inbox/AppInbox.swift`, and `GatewayExtraction`'s field set.

## Tests

- `cd ios && swift build ; swift test` - **1228 today; must not fall.**
- **L1 in core for the per-field merge** - one policy, feeding both the in-process late answer and
  the outbox drain (RV.44 made that a single function; keep it single):
  - taking a **blank** field fills it and touches nothing else;
  - taking a **differing** field replaces exactly that field - assert **every other field is
    byte-identical**, not just that the target changed;
  - taking **nothing** leaves the entry byte-identical;
  - a field that matches is not offered as a choice at all.
- **L4**: a card with one differing field and one blank field offers exactly **two** ticks;
  **ticking only the blank one leaves the differing field byte-identical** (assert the VALUE);
  ticking the differing one replaces that field only; **with nothing to change, the card says so and
  offers no update action**.

**Vacuous-assertion traps, named:**
- Asserting the comparison row `.exists` rather than asserting the two values it shows.
- Asserting "the entry changed" instead of asserting which field changed and that the others did
  not - a merge that overwrote everything passes the loose check.
- Testing only the blank-fill path. The overwrite path is the new power this task grants and the one
  rule 13 cares about.
- A "nothing to change" test that only checks the card rendered.

**Mutation-check and report it**: make a per-field take apply *all* fields rather than the ticked
one, confirm the "every other field byte-identical" test goes red, restore byte-for-byte, confirm
green.

## The baseline gate (CLAUDE.md rule 14)

    cd ios && swift build ; echo "BUILD=$?"
    cd ios && swift test ; echo "IOSTEST=$?"
    swiftlint lint ; echo "LINT=$?"          # from the repo ROOT
    swift run --package-path ios localization-gate --sources ios/App/Sources \
      --catalogue ios/App/Sources/Localizable.xcstrings ; echo "L10N=$?"
    xcodegen generate && xcodebuild -project Tankbook.xcodeproj -scheme Tankbook \
      -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build ; echo "APPBUILD=$?"

**Echo the exit code from the COMMAND, never through a pipe** - `cmd | tail -2 ; echo $?` reports
`tail`'s status. Redirect to a file instead. Run swiftlint from the **repo root**; from `ios/` its
root-relative `excluded:` paths report thousands of phantom violations.

Match the process NAME (`pgrep -x xcodebuild`). **Never `pgrep -f` or `pkill -f`** on a build/test
pattern - an agent's brief is part of its command line, and that pattern killed a sibling agent on
2026-08-24. **A sibling agent is running right now**, so this matters today.

## Screenshots

`design/screenshots/RV.45-*.png` and `-ru.png`, dark, outside any test run, capture lines added to
`scripts/capture-screenshots.sh`. At minimum: **a card with both a differing field and a blank
field** (the interesting case), and **the nothing-to-change card**.

**RU is the real test**: a two-column comparison with Russian field labels is exactly where a table
overflows, and the fuel-kind and currency labels are long.

If the simulator has been driven hard, `xcrun simctl shutdown` + `erase` + `boot` on **iPhone 17
Pro** before capturing - a stale device silently shoots the wrong screen, which is worse than no
shot. You have no image input; say so plainly. The orchestrator opens every screenshot personally.

## Report back

- Exit codes (captured, not piped), test counts before/after, suites RUN, the mutation result.
- **What the card does when nothing would change** - quote the copy.
- **How filling a blank reads differently from replacing a typed value** - quote both.
- Confirmation that "Leave it as it is" is still the default and still prominent.
- Confirmation that the per-field merge is ONE function serving both the in-process and outbox
  paths.
- Files changed, docs extended (`ERRORS.md` Inbox rows, `JOURNEYS.md` F4 if the ask's shape
  changed), anything unfinished.

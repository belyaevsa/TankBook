# RV.38 – the notification bell: an inbox for work that finishes after the user moved on

Required by the product owner, 2026-09-03. The first case is concrete: a **cloud reading that lands
after the user typed the details and saved**. The system finds a difference and asks what to do -
*update from the receipt · leave it as it is · replace the receipt*. Plus a home for later delayed
results, and for reminders.

## Where you may write

Only inside `/Users/sbelyaev/repos/fuel-counter-ios`. **Do not run `git add` or `git commit`.**
**Do not touch `docs/TASKS.md`** - the orchestrator ticks the row after verifying; an agent editing
it silently un-ticks other rows when the conflict is resolved by side.

Use the **`iPhone 17`** simulator for every xcodebuild/xcrun step. No other agent is running right
now, so the device is yours - but say so in your report if that changes.

## This CHANGES A DOCUMENTED DECISION, and the change is only legitimate because of the ask

`docs/JOURNEYS.md` **F4** and `GatewayScanSession` are explicit today: *"once the entry is saved,
nothing arrives at all"* - implemented by `markSaved()` dropping the answer on the floor. **That was
deliberate**: a late answer silently rewriting a saved entry is exactly what hard rule 13 forbids.

What makes reversing it legitimate is that the app **asks**. So the ask is not a nicety, it is the
whole justification, and it has a required shape:

- **"Leave it as it is" is the DEFAULT.** The entry is not touched unless the user taps
  "update from the receipt".
- **Even an accepted update fills BLANK FIELDS ONLY** (hard rule 13, and the same
  `GatewaySuggestionPolicy` boundary the Confirm sheet already enforces). A user-typed value is
  theirs permanently; an accepted re-read never overwrites one.
- **Amend F4 in the same commit** with that reasoning, or the next reader will restore the drop and
  be right to.

## The hard part is DURABILITY, not the UI - and you must decide it explicitly

The extraction lives on the device (rule 9: the gateway holds no conversation), so **if the app is
killed mid-request the answer is simply gone**. Production already shows this: `POST /v1/extract ->
499` after 33 s. **A notification that only appears when the app happened to stay alive is worse
than none** - it teaches the user the feature is unreliable, which is harder to undo than not
shipping it.

**RV.33 landed today** (commit on `main`): every LLM call is now recorded server-side with its
response body, retained 30 days, keyed by account and device. So the durable option is genuinely
available now, and the choice is real:

- **Best-effort (device-only)**: simplest, no new endpoint, but the answer dies with the process.
  If you choose this, the UI must be **honest about it** - the inbox never promises an answer that
  can vanish.
- **Durable (re-read from the ledger on next launch)**: survives a kill. **But note what it costs**
  - reading the ledger back means a **read endpoint over RV.33's table, and RV.33's own amendment
  says the ledger is "written by the gateway and read by no endpoint"**. Adding one is a second
  reversal and needs its own written decision in `CLAUDE.md` rule 9 - do NOT slip it in. If you
  judge durability worth that, **stop and say so in your report instead of building it**; the
  product owner decides, not the agent.

**Recommended path**: build the inbox best-effort and device-local, structured so a durable source
can be added behind the same interface later, and report exactly what would be needed. That ships
the user-visible feature without a second rule-9 reversal made by an agent.

## Hard rule 8 governs the shape

Conflicts surface as badges **where the data lives**, never as a central modal at sync time.

- An inbox that **routes to the entry** is compatible.
- One that becomes the **only** place a problem is visible, or that resolves it centrally while the
  entry shows nothing, is **not**. The entry keeps its own badge; the bell is a *second route* to
  it, never the sole one.

## Placement - and the collision is REAL and already on screen

**RV.22 landed today and put a sync state chip beside the gear**, and RV.21 gave all three tab
roots one shared header (`TabRootHeader.swift`). The header's trailing corner now holds **two 44 pt
circular controls**: the sync chip and the Settings gear, identical in size and treatment, differing
only by glyph and colour (the product owner asked for icon-only, gear-sized, 2026-09-03).

**A third control in that corner needs a decision, not an accretion.** Three 44 pt circles plus a
large title will crowd the row, and RU titles ("Журнал", "Тренды", "Гараж") are wider than English.
Options, and you must pick one and justify it with a measurement, not a preference:

- a third circle in the same family (measure the row at the longest RU title and show it fits);
- the bell replaces the chip when there is something to act on (they are both "state you should
  know about" - but then the sync state is hidden exactly when things are busy, which is when it
  matters);
- the bell lives elsewhere entirely (and then say where, and why that is reachable).

**Whatever you choose, match the existing treatment exactly**: 44 pt frame, `dash` fill, hairline
stroke, `.title3` glyph. And read `SyncStateChip.swift`'s `indicator` comment before you add any
non-`Image` content to that row - a `ProgressView` there has no text baseline, drops ~10 pt below
the gear and grows the header, which is a defect that shipped in the first icon-only screenshots
and was invisible to the L4 tests.

## Reminders moving in is an IA change

Reminders have their own screen and their own local notifications today (`SCREENMAP.md` lines 11,
59, 95). Decide whether the inbox **replaces** that screen or **links to** it, and move
`SCREENMAP.md` accordingly. Do not leave two homes for the same thing with no stated relationship.

`docs/NOTIFICATIONS.md` is the authority for delivery and **must gain the in-app tier** beside local
and silent APNs.

## Read before writing

1. **`CLAUDE.md`** - hard rules 1, 7 (every error names its next step and survives being ignored),
   8 (badges where the data lives), 10 (String Catalogs, whole phrases per language), 12 (counts and
   codes are loggable, domain values never), 13 (the app suggests, the user decides), 14.
2. `docs/JOURNEYS.md` → **F4** (the journey you are amending), `docs/NOTIFICATIONS.md`,
   `docs/SCREENMAP.md` (the tab-root header conventions and the Reminders nodes), `docs/ERRORS.md`.
3. `ios/App/Sources/ConfirmManual/GatewayScanSession.swift` (`markSaved()`, the drop this reverses),
   `ios/App/Sources/Navigation/TabRootHeader.swift` and `SyncStateChip.swift` (the corner you are
   joining), the `GatewaySuggestionPolicy` blank-fields-only boundary.

## Tests

- `cd ios && swift build ; swift test` - **1215 today; must not fall.**
- **L1 in core for the decision**, not in a view: what makes an inbox item, when it clears, and the
  blank-fields-only merge. `SyncSurfaceTests`/`SyncChipTests` are the model for a pure-decision suite.
- **L4, and the assertions the row names**:
  - an item appears with its three actions;
  - **declining leaves every field byte-identical** - assert the VALUES (the blank total still
    blank, the typed litres unchanged), never that a dialog showed. *A dialog that overwrites anyway
    passes an existence check* - this exact trap is what RV.37's decline test was written against;
  - accepting fills from the receipt **and leaves a user-typed value alone**;
  - the item **clears and does not return**.
- EN + RU copy as whole localised phrases (hard rule 10), never concatenation.

**Vacuous-assertion traps, named:**
- Asserting the bell `.exists`. It exists in every state.
- Asserting a badge count is non-zero rather than asserting the number.
- Testing only the accept path - decline is the one that must not lose data.

**Mutation-check and report it**: make "leave it as it is" apply the update anyway, confirm the
decline test goes red, restore byte-for-byte and confirm green.

## The baseline gate (CLAUDE.md rule 14)

    cd ios && swift build ; echo "BUILD=$?"
    swiftlint lint ; echo "LINT=$?"          # from the repo ROOT
    swift run --package-path ios localization-gate --sources ios/App/Sources \
      --catalogue ios/App/Sources/Localizable.xcstrings ; echo "L10N=$?"
    xcodegen generate && xcodebuild -project Tankbook.xcodeproj -scheme Tankbook \
      -destination 'platform=iOS Simulator,name=iPhone 17' build ; echo "APPBUILD=$?"

**Judge by the exit code you echoed** - and echo it from the COMMAND, never through a pipe: `cmd |
tail -2 ; echo $?` reports `tail`'s status, not the command's. Redirect to a file instead. Zero lint
**errors**; run swiftlint from the **repo root** (from `ios/` its root-relative `excluded:` paths
report thousands of phantom violations).

Match the process NAME (`pgrep -x xcodebuild`). **Never `pgrep -f` or `pkill -f`** on a build/test
pattern - an agent's brief is part of its command line, and that pattern killed a sibling agent on
2026-08-24.

## Screenshots

`design/screenshots/RV.38-*.png` and `-ru.png`, dark, **outside** any test run (`simctl` and
`xcodebuild test` fight over the device), with the capture lines added to
`scripts/capture-screenshots.sh`. At minimum: the bell with something waiting, and the item with its
three actions. **RU is the real test** - the three action labels are long in Russian and this sits
in a crowded corner.

If the simulator has been driven hard, `xcrun simctl shutdown` + `erase` + `boot` before capturing:
a stale device silently produces shots of the wrong screen, which is worse than no shot.

You have no image input - say so plainly. The orchestrator opens every screenshot personally.

## Report back

- Exit codes (captured, not piped), test counts before/after, suites RUN, the mutation result.
- **Durability: which you chose, and what a durable version would require** - name the rule-9
  consequence explicitly rather than building it.
- **Placement: which option you took, and the measurement that justifies it** at the longest RU
  title.
- **Reminders: replaces or links**, and the `SCREENMAP.md` change you made.
- Confirmation that the entry keeps its own badge and the bell is a second route, never the only one.
- Files changed, docs extended (F4, NOTIFICATIONS.md, SCREENMAP.md, ERRORS.md), anything unfinished.

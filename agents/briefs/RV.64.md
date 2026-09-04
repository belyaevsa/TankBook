# RV.64 – the inbox card's loud default contradicts the user's ticks

Reported by the product owner 2026-09-04: *"if a user ticked already, the leave as it is button must
be dimmed and replace - highlighted"*. **Confirmed in code before filing** – confirm it still holds,
do not re-derive it.

## Where you may write

Only inside `/Users/sbelyaev/repos/fuel-counter-ios` – **`ios/` and `docs/` only.**
**Do not run `git add` or `git commit`. Do not touch `docs/TASKS.md`.** Touch no `backend/` file.
**Never move, rename or delete a file you did not create.** `.claude/worktrees/rv48` belongs to
another session and is not your gate.

**Use the `iPhone 17` simulator.**

## The defect, verified

`ios/App/Sources/Inbox/InboxView.swift:206-252`.

- `leaveAsIsAction` renders **bold on a filled `Theme.Palette.taillight`** and is **first** in the
  `actions` stack.
- `updateAction` is **always** the secondary treatment (`Theme.Palette.dash` + hairline stroke). Its
  foreground moves `inkSoft -> ink` and it becomes `.disabled(false)` once `ticked` is non-empty –
  so it becomes **enabled**, never **prominent**.

**The weighting never responds to state.** After the user ticks fields, the loudest control on the
card is still the one that throws those ticks away.

**Read the doc comment above `actions` before you change anything.** It states the intent:

> "Leave it as it is is the DEFAULT (hard rule 13), so it comes FIRST and carries the prominent
> filled treatment; the update is the secondary, taken only on an explicit tap"

**That reasoning is correct in one state and wrong in the other**, which is why this is a design fix
and not a bug in the ordinary sense. Rule 13 – *the app suggests, the user decides* – makes
leave-as-is the right default while nothing is ticked. **But a ticked field IS the user deciding**,
and the screen then loudly recommends discarding that decision. **Rewrite that comment** to say what
the rule actually implies in each state; leaving it as-is would make the next reader "fix" your work
back to the bug.

**Hard rule 8 also applies**: the ticks are user work, and today the most prominent control destroys
them with no confirmation and no undo. That is "lost silently".

## What to build

**Make the weight follow the state.**

- `ticked.isEmpty` – **today's treatment is correct and must not change.** Leave-as-is stays the
  prominent filled action.
- at least one tick – **the update becomes the prominent filled action**, and leave-as-is drops to
  the secondary/dimmed treatment.

**Keep the button ORDER stable.** Reordering controls under a finger already in motion is its own
hazard. **Swap emphasis, not position** – if you disagree, say why rather than doing it silently.

**Colours come from `docs/DESIGN.md` tokens only** (hard rule 5 – no ad-hoc hex, and `taillight` is
the primary/fuel accent). The emphasis must be **derived from the tick count in one place**, so the
two states cannot drift apart.

**Also review, and it may be a separate defect – say which.** The card offers BOTH "Update from
receipt" (`updateAction`, applies the ticks) and a "Replace receipt" `NavigationLink` to Edit entry.
The product owner referred to the tick-applying button as *"replace"*, which suggests the two names
are not distinguishable in use. Review the copy against `docs/ERRORS.md` and the glossary, **EN and
RU** (hard rule 10 – whole localised phrases, never concatenation). If you change a string, it goes
through the String Catalog.

## Read before writing

1. **`CLAUDE.md`** – hard rules 13, 8, 5, 10, 7, 14.
2. `docs/DESIGN.md` – the palette tokens and what "prominent" means in this design language;
   `docs/ERRORS.md` – the inbox rows; `docs/JOURNEYS.md` – the late-answer journey.
3. `ios/App/Sources/Inbox/InboxView.swift` (all of it – `actions`, `leaveAsIsAction`,
   `updateAction`, `replaceReceiptLink`, `tickButton`), `AppInbox.swift`
   (`.leaveAsIs` / `.update(fields:)` / `.replaceReceipt`), `InboxTestSeed.swift`.

## Tests

**iOS unit 1328 today; must not fall.** UI suite expected: `InboxUITests` (name it with
`-only-testing:`).

- **The headline L4: with ZERO ticks the leave-as-is button carries the prominent treatment; after
  ticking ONE field the UPDATE button carries it and leave-as-is does not.** Assert the treatment
  itself, not merely that both buttons exist.
- **L1: the emphasis is derived from the tick count**, so the two states cannot drift apart – a pure
  decision, testable without a view.
- L4: unticking the last field returns the prominence to leave-as-is (the state is symmetric).
- Existing inbox behaviour must not move: resolving as `.leaveAsIs` and as `.update(fields:)` still
  do what they did.

**Vacuous-assertion traps, named:**
- **Asserting the update button is ENABLED.** It already becomes enabled today – enabling is exactly
  what this row says is insufficient.
- Asserting both buttons are present. They both always were.
- Asserting a colour literal instead of the token (hard rule 5).
- Testing only the ticked state – the zero-tick state is a real requirement and must not regress.

**Mutation-check and report it**: pin the emphasis to leave-as-is regardless of ticks (i.e. restore
today's behaviour) and confirm the headline L4 goes red. Restore byte-for-byte, confirm green.

## The baseline gate (CLAUDE.md rule 14)

    cd ios && swift build ; echo "BUILD=$?"
    cd ios && swift test ; echo "IOSTEST=$?"
    swiftlint lint ; echo "LINT=$?"               # repo ROOT, root-relative excluded: paths
    swift run --package-path ios localization-gate --sources ios/App/Sources \
      --catalogue ios/App/Sources/Localizable.xcstrings ; echo "L10N=$?"   # from repo ROOT
    xcodegen generate && xcodebuild -project Tankbook.xcodeproj -scheme Tankbook \
      -destination 'platform=iOS Simulator,name=iPhone 17' build ; echo "APPBUILD=$?"

**Echo the exit code from the COMMAND, never through a pipe** (`cmd | tail -2 ; echo $?` reports
`tail`'s status); redirect to a file instead. **Never `pgrep -f`/`pkill -f`.**

## Screenshots

**Required, EN and RU, dark, in BOTH STATES – zero ticks and at least one tick.** The entire row is
about which button looks primary, so a single-state screenshot proves nothing. Save as
`design/screenshots/RV.64-inbox-noticks.png`, `RV.64-inbox-ticked.png` and the `-ru` pair, captured
OUTSIDE a test run (`simctl` and `xcodebuild test` fight over the device).
RU: `xcrun simctl launch <device> app.tankbook.Tankbook -AppleLanguages "(ru)" -AppleLocale ru_RU`.
**You have no image input** – say so, and say what you could not check.

## Report back

- Exit codes (captured, not piped), unit counts before/after, the UI suites you ran, mutation result.
- **Which treatment each button carries in each state**, named by DESIGN.md token.
- Confirmation you swapped emphasis and NOT order – or your reasoning if you disagreed.
- **What you concluded about "Update from receipt" vs "Replace receipt"** – same defect, or separate?
- The doc comment you rewrote above `actions`.
- Anything you noticed that is not RV.64 – named separately, not folded in.

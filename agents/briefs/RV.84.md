# RV.84 - two defects on the import source screen: the 422 card clips in RU, and an action line is missing in RU

**This row carries two separate defects.** Fix both, and **say which fix addressed which**. They live
on the same screen and are not the same bug.

---

## Defect A - the 422 card clips in Russian, and I have the mechanism

Residual from [RV.80], confirmed in its measurements: the 422 card is the tallest of the parse-error
cards (~150pt in RU - it carries the help link), and RU body content (479pt) plus that card plus the
primary bar exceed the fixed vertical budget by **13-30pt**. EN fits by luck, not by design.

**The mechanism, read from the source - do not re-derive it.** The screen's root
(`ios/App/Sources/Import/ImportSourceView.swift:20-52`) is a `ScrollView` **plus** a
`.safeAreaInset(edge: .bottom) { bottomBar }`, and `bottomBar` (`:356-361`) renders the parse-error
card **above** the primary bar:

```swift
private var bottomBar: some View {
    VStack(spacing: 0) {
        if let failure = model.parseFailure { parseErrorCard(failure) }   // <- here
        ImportPrimaryBar(...)
```

**A `safeAreaInset` is by definition the region that does not scroll.** Its height is subtracted from
the scroll view's budget, so a card whose height depends on the locale's content is the one thing
that must never live there: when RU makes it taller, there is nowhere for the overflow to go and it
clips. `[RV.80]` fixed the read-failed state by dropping a redundant notice; the 422 state has no
second notice to drop, which is why the same trick does not apply twice.

**The fix is structural, and the choice is yours to make and justify.** Move the parse-error card
**out of the inset and into the scroll content**, leaving `bottomBar` as the primary bar (plus the
parsing Cancel) only. My preference, and say why if you choose otherwise: render it as the **first**
child of the scroll content, directly under the title block - it is then visible without scrolling in
**both** locales, and the scroll owns any overflow. Placing it last would need a scroll-to-it on
appearance, which is a second mechanism to get wrong.

**Do NOT shorten the RU copy to fit.** The copy is correct and the layout is what is wrong - the P1.4
lesson: a phrase that fits only in English is a layout defect.

**Also check the other tall states** (`importOfflineCard` `:279-286`, the contract-break /
server-error cards `:109-123`, and the `inconsistentDates` card) and **report which fit by design and
which by luck.** Those three already live inside the ScrollView, so state whether that is enough.

### The test trap that is specific to this defect

**`isHittable` gave a FALSE POSITIVE here** - [RV.80] measured it reporting a **clipped** element as
hittable. An assertion built on it **passes against the live bug**. Assert visibility by **frame**:
compare the element's frame against the window's, the way `PR.6b` asserts the parsing Cancel
(`ImportSourceView.swift:383-384` names the technique).

---

## Defect B - "Send us the file" does not render in Russian

Found 2026-09-05 by the orchestrator **re-capturing the RU screen personally** - by no test, and not
by an agent, which has no image input. `notSupportedCard`
(`ios/App/Sources/Import/ImportSourceView.swift:230-258`) renders three `Text` views
unconditionally - heading, body, and the action line **"Send us the file"** (`:240-243`). In EN all
three appear; in RU the card is visibly **shorter** and the action line is **absent**.

**I have already eliminated the row's own suggested culprit - do not spend the run there.** I read
`ios/App/Sources/Localizable.xcstrings` directly: the key `Send us the file` exists **once**, with
`"ru": "Отправить файл"`, state `translated`. There is **no duplicate key** and **no missing
translation**. The catalogue is not the bug.

**So reproduce it on a device first and find the real mechanism.** Two hypotheses worth separating
before you change anything, and there may be a third:

1. **It is genuinely not rendering** - then find why a translated key produces no view, and check
   whether the shape is general (any other multi-`Text` card whose action line is a plain `Text`).
2. **It is below the fold** - the card is the **last** child of the scroll content (`:29-34`), and RU
   content above it is ~479pt taller. If the line is merely off-screen and the screen scrolls to it,
   then the defect is that the card's affordance is not reachable without scrolling, which is a
   different (and smaller) fix. **The row says the card is visibly shorter, which argues against
   this - but measure, do not take my word or the row's.**

**Report which it was.** "The mechanism was X" is the deliverable here; a fix without it is a guess.

**Why it matters**: this card IS the dead end's next step (hard rule 7 - the comment above it says so
in as many words), and the whole card is one `Button`, so a Russian user has a tappable region with
**no visible affordance telling them it is tappable**. It is also the entry point for the corpus
growth F6 depends on.

**Then audit for the same shape** - any other multi-`Text` card whose action line is a plain `Text`
rather than a labelled control - and **report differentiated; do not fix silently.**

---

## Explicitly out of scope

- Rewriting the RU copy of either card.
- Redesigning `ImportPrimaryBar` or the wizard's steps.
- `RV.93`'s multi-file work, which touches the same file - if it has already landed, **rebase your
  reading on what is in the tree**, do not assume these line numbers.

## Tests

Read the current `swift test` count yourself before you start and report before -> after.

- **L4 in RU (defect A)**: the 422 card's **full text and its help link** are on screen, asserted by
  a **frame comparison against the window** - never `isHittable`.
- **L4 in RU (defect B)**: the action line is **present in RU**. `ImportUITests` already runs seeded
  RU checks - use that mechanism rather than inventing one.
- Suites: `ImportUITests`. Report the observed count.

### Vacuous traps, named

- **`isHittable`** - it lies in exactly this state, measured.
- **Asserting in EN**, which fits today and renders today.
- **Asserting the card EXISTS** rather than that it is **fully visible** - the card exists in both
  languages in both defects.
- Asserting the card's accessibility identifier rather than the **visible action line** (defect B's
  card identifier is on the whole button, so it is present either way).

### Mutations (run each, report, restore byte-for-byte)

1. Put the 422 card back inside the `safeAreaInset` -> the RU frame test must fail.
2. Whatever made the RU action line render, undo it -> its RU test must fail.

**A mutation that PASSES is a finding** - say so and grow the test until it fails. **If defect B turns
out to be "below the fold" rather than "not rendering", say so plainly** - that is a real result, and
the honest fix is different.

## Screenshots - these are the GATE for this row

Both defects were found by looking, and neither by a test. EN **and** RU, **dark**, into
`design/screenshots/`:
- `RV.84-import-422-ru.png` (and `-en`) showing the **whole** 422 card including its help link.
- `RV.84-import-not-supported-ru.png` (and `-en`) showing the action line.
- Capture **outside** a test run; `-homeResetDatabase` alongside any seed. `-seedSendFile` opens the
  not-supported sheet (`ImportWizardView.swift:54-57`).
- RU: `xcrun simctl launch <device> app.tankbook.Tankbook -AppleLanguages "(ru)" -AppleLocale ru_RU`.
- **Verify every EN/RU pair differs with `md5 -q`** and report the hashes. RV.58 shipped an "RU" shot
  byte-identical to its EN one and could not tell.
- **You cannot see your own screenshots.** The orchestrator opens every one - do not claim they look
  right.

## Docs to reconcile

`docs/ERRORS.md` (the import wizard's cards and their next steps), `docs/DESIGN.md` only if the fix
establishes a layout rule worth stating (an actionable card must not live in a `safeAreaInset` - if
you conclude that, write it down; it is the general shape [RV.80] identified).

## Hard rules that decide things in this area

**7** (every error names its next step - a clipped or absent next step is the rule broken) ·
**10** (EN + RU from day one; a phrase that fits only in English is a layout defect) · **5** (palette
tokens only, no ad-hoc hex) · **14** (it builds and it lints).

## Where you may write

Only inside `/Users/sbelyaev/repos/fuel-counter-ios`, and within it only:
`ios/Sources/TankbookCore/**`, `ios/App/Sources/**`, `ios/Tests/**`, `ios/App/UITests/**`,
`backend/src/**`, `backend/tests/**`, `Spike/ImportFixtures/**`, `design/screens/**`,
`design/screenshots/**`, and the docs named in this brief. **If your row's "out of scope" says not to
touch a tier, that fence wins over this list.**

**Never move, rename or delete a file you did not create.** Another session may be working in this
checkout. Expect files, and even a red test, that are not yours: **report them and carry on** - never
"clean the baseline".
Do NOT tick anything in `docs/TASKS.md` - the orchestrator ticks at merge. Do NOT commit.
No `git add -A`, `git checkout`, `git stash`, `git clean`.

## Write code first, explore second

The dominant failure mode is a run that reads everything and writes nothing. The cause is pinned to
lines above and is confirmed - do not spend the run re-deriving it. Where this brief leaves a
genuinely open choice, **take the smallest correct option and keep going**, then say in the report
which you took and what you rejected. Do not stop and wait on it. (`RV.74`'s first dispatch ran two
hours and wrote nothing, stuck on a question its brief left open.)

If a fence in this brief turns out to be wrong, **report it as a Residual rather than obeying
quietly** - a fence can be wrong the same way a diagnosis can. Two of my diagnoses have been wrong
this month and the agent was right both times.

## The baseline gate (CLAUDE.md rule 14)

From the **repo ROOT**, judged by exit code (`echo $?`), never by skimming output:
- `cd ios && swift build` -> 0
- `cd ios && swift test` -> 0, count reported (before -> after). Never subset it.
- `swiftlint lint` **from the repo root** -> 0 errors. From `ios/` it prints thousands of phantom
  violations; that false red has cost two sessions.
- `swift run --package-path ios localization-gate` from the root -> 0.
- **If you touched `backend/`**: `cd backend && dotnet build` -> 0 and `dotnet test` -> 0 (count
  before -> after), plus `dotnet format --verify-no-changes` -> 0.
- **If you touched `ios/App/`**: `xcodebuild -project Tankbook.xcodeproj -scheme Tankbook -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:<the suites this brief names> test` -> 0.
  `swift build` does NOT compile `ios/App`; only `xcodebuild` does. Run `xcodegen generate` first if
  you added a file. **Check the observed count is non-zero.** Do NOT run the whole UI suite - that
  belongs to phase completion (2026-08-29 rule).
- **`$?` after a pipe is the pipe's exit code.** `dotnet test | tail` once reported 0 while the run
  aborted and "66 passed" of ~396 nearly read as green. Never judge a run by `... | tail`.
- **Never `pgrep -f` for a build** - your own brief is in your command line and you will match, and
  could kill, a sibling agent. Use `pgrep -x xcodebuild`.
- **Simulator contention produces false reds** with a *different* failing set each run, and a suite
  reporting "Executed 0 tests" beside its failures is kills, not assertions. Shut the simulators down
  and re-run once on a quiet machine before believing a red.

## Report back

1. Exit code of every gate, and observed test counts (before -> after), per tier you touched.
2. Each mutation: what you broke, which named test failed, and that you restored it byte-for-byte.
   **A mutation that PASSES is a finding** - say so rather than moving on. Four passed on 2026-09-06
   and each meant the test did not cover the claim its row was written for.
3. Screenshot paths and md5s, if this brief asked for screenshots.
4. What the user can now do that they could not before. If the honest answer for some case is
   "nothing changed", say so.
5. Anything in this brief that was wrong, as a Residual.
6. Whether the tests were actually **run**, not only written.

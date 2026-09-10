# RV.177 + RV.178 - the home-currency question becomes a sheet with a real hierarchy

You are working in `/Users/sbelyaev/repos/fuel-counter-ios`. **Write only inside that repo.**
Write code first, explore second. Do not commit; the orchestrator commits after verifying.
**Never move, rename or delete a file you did not create** - assume you are not alone in this
checkout. **Agents never tick `docs/TASKS.md` and never commit.** An agent ticked its own row on
2026-09-10 and the orchestrator reverted it.

**Two rows, one change, one surface.** They touch the same control and cannot be built separately.

## The defect

[RV.152] shipped the home-currency question as a **system alert** with two roleless buttons
(`VehicleDetailView.swift:144-151`):

```swift
.alert(currencyChangeTitle, isPresented: currencyChangePresented, presenting: currencyChange) { prompt in
    Button("Convert the log") { commit(prompt.updated, answer: .convert) }
    Button("Keep the entries as they are") { commit(prompt.updated, answer: .keep) }
} message: { prompt in
    Text(L10n.homeCurrencyChangeMessage(pending: prompt.plan.stillPendingCount))
}
```

**Neither carries a role, so iOS tints both with the app accent - and the accent IS taillight red.**
One rewrites every entry's derived half and **cannot be undone**; the other changes no entry at all.
They render identically. A user picks by position, not by consequence.

**This is why `.destructive` alone does not fix it**: `.destructive` renders red, a plain button
renders the accent, and here they are the same colour. That collision is what forces the answer
below.

It is [RV.159]'s comprehension class - *"drawn as the same object"* - and `docs/DESIGN.md` gained
the governing rule a day earlier: **a consequential control differs from a harmless one
structurally, never by colour alone.** Red is *legal* here (hard rule 5 permits it inside a system
dialog), which is exactly why the rule needs its own form for this case.

## The product decisions are MADE - both of them - do not relitigate

**Product owner, 2026-09-10.**

**RV.177: replace the system alert with a custom sheet you can style.** Escaping iOS's tinting is
the point: the sheet gives the two answers a real hierarchy.

- **"Convert the log"** - the **filled, primary** action.
- **"Keep the entries as they are"** - a **quiet secondary**.

**RV.178: NO cancel. Save means Save.** The currency change is decided by tapping Save; this sheet
asks **only** what to do with the existing entries. Record that in `docs/ERRORS.md` as a deliberate
choice, so it is not mistaken later for an accident of having two buttons.

**Reconcile the two carefully - this is the trap in this row.** The option preview that settled
RV.177 sketched a third quiet "Cancel" line. **RV.178 overrides it: build TWO actions, no Cancel.**

## The consequence RV.178 creates, and you must handle it

**A `.sheet` is swipe-dismissible by default.** A user who drags it down would abandon the question
silently - which is *worse* than the alert it replaces, because the alert at least forced a choice.
Under "Save means Save" the sheet must not be dismissible without answering:
`.interactiveDismissDisabled(true)`, and no close affordance.

**Say in your report how you verified a swipe cannot dismiss it**, and what happens to the pending
save if the app is backgrounded while it is up.

## This brief's reading is a hypothesis - confirm it before you change anything

Line numbers were read on the tree as left. Re-read the save path first: `VehicleDetailView`'s save
**already returns before `commit`** when the question is needed (`:331-338`), which is what makes
the vehicle row unwritten while the question is up. Confirm that still holds - the whole design
rests on it.

## What to build

The sheet, with the hierarchy above, carrying **the same copy RV.152 shipped** - the pending count
stated before committing, what "keep" means for the stats, and the pairing that makes the warning
fair: *the original receipt amounts are never touched* **and** *this cannot be undone*. Do not
reword it; that copy was settled and is verified by RV.152's tests.

**Record the treatment rule in `docs/DESIGN.md`**, beside RV.159's gate-vs-offer rule: when the
accent colour collides with `.destructive`, hierarchy comes from **structure** - a filled primary
against a quiet secondary - not from a role that renders the same colour. **Audit the app's other
multi-action alerts in the same pass and report** which pair a consequential action with a harmless
one; do not fix them here.

## Explicitly out of scope

- [RV.152]'s conversion logic, `conversionPlan`, `convertedPair` and their tests. **Do not touch
  the arithmetic.** If a test of yours needs a fixture, reuse `-seedHomeRV152`.
- The manual-rate-replacement question RV.152 flagged.
- Every other alert in the app - report, do not change.

## Docs to read before writing (in order)

1. `docs/DESIGN.md` -> hard rule 5's palette semantics and RV.159's *"a sending gate is never drawn
   as an optional attachment"*. **The authority**; extend it in the same change.
2. `docs/ERRORS.md` -> the RV.152 home-currency rows. Record RV.178's "Save means Save" there.
3. `docs/SCREENMAP.md` - if this becomes a presented sheet rather than an alert, check whether the
   screen inventory needs it. **[RV.162]'s guard now fails a screen with no production door**, so if
   you add a `Route`, it needs one.
4. `CLAUDE.md` hard rules 5, 7, 10.

## Environment axes this crosses

**Locale** - EN and RU, gate at 100%; **RU is where a filled primary's label plus a two-line warning
is tightest**. **Largest Dynamic Type** - a custom sheet does not get the alert's automatic scaling,
so exercise XL and say what you found. **Screenshots: EN and RU required**, and RU is the real check.
No offline path. Release build if you touch a `#if DEBUG` seam.

## If this adds a failure path, what makes it visible in production?

None expected - this is presentation over a decision that already exists. If you add a branch that
can dismiss without answering, that **is** a failure path and needs the shape-only event that says
it happened (`docs/LOGGING.md`, hard rule 12 - counts and currency **codes** are shape, amounts are
not).

## Tests you must add

- **L4, and it FAILS TODAY**: the two actions are **distinguishable by an asserted property** -
  assert the structural difference you introduced (the filled primary vs the quiet secondary), never
  that both exist. Both exist today.
- **L4**: the sheet **cannot be dismissed without answering** - a swipe-down leaves it up and writes
  nothing. **Oracle**: the vehicle's `homeCurrency` is unchanged and no entry was touched.
- **L4**: both answers still do what RV.152 made them do - Convert converts, Keep keeps. Reuse
  RV.152's assertions rather than writing parallel ones; say which you reused.
- **L4**: EN and RU at the largest text size.
- **L1**: no Cancel path exists - the negative claim that pins RV.178's decision. Assert there is no
  third action, so a future "helpful" addition fails this test and has to re-decide deliberately.

Name the UI suite you extend and report its observed, **non-zero** count. **Run app-target suites
separately, and check the COUNT** - on 2026-09-10 a filter matched nothing three times and printed
`TEST SUCCEEDED` with exit 0 on **zero tests**; one of those suites was `extension
ConfirmManualUITests` in a differently-named file, so filter by the **suite** name, not the file's.

## The mutation you must run - I am naming it, do not choose your own

**Give the quiet secondary the primary's filled treatment**, so both actions look alike again -
leaving both behaviours intact. The distinguishability test **must go red**, and the two
does-what-it-says tests must stay **green**. Then restore and re-run. Report both outputs verbatim.

That split is the evidence: it shows the new test measures *telling them apart*, not *what they do*.

## Vacuous traps, named

- **Asserting both actions exist** - true today, passes on the unfixed code.
- **Building a Cancel.** RV.178 decided against it; the RV.177 preview's third line is overridden.
- Leaving the sheet swipe-dismissible, which silently abandons the question - worse than the alert.
- Using amber or red to carry the hierarchy (hard rule 5); the whole point is that colour cannot.
- Rewording RV.152's settled copy.
- Adding a `Route` without a production door - [RV.162]'s guard now fails that.

## Never stash, move or `git checkout` to get a "clean baseline"

Write the test, run it against the unmodified code, then make the change. **Do not** `git stash`,
`git checkout`, or move files out of the tree: an agent did that on 2026-09-08 and a bad `mv` loop
destroyed three of its own new files.

## Never `pgrep -f` for a build process

Your brief is part of your command line, so `pgrep -f "xcodebuild.*test"` matches **this agent**.
Use `pgrep -x xcodebuild`. **Never `pkill -f`.**

## `simctl launch` on a running app ignores new arguments - `terminate` first

**You cannot see your own screenshots**: state what you captured, never that it looks right. **Check
what is BEHIND your subject** - on 2026-09-10 a correct toast was photographed over a screen no user
can reach, and it looked like a successful capture.

## Standing checks

Re-measure the baseline yourself and report what you observe. As left, `main` is **1863 tests / 221
suites**, **829** localization keys at 100% RU.

1. `cd ios && swift build` - exit 0.
2. `swiftlint lint` from the **repo ROOT** - exit 0. From the root, **not** `ios/`: the `excluded:`
   paths are root-relative and from `ios/` it exits 2 with ~5000 phantom errors.
3. `cd ios && swift test` - full, never subsetted; report the count.
4. **`xcodebuild ... build` for the app target** - `swift build` compiles only the SwiftPM package,
   and on 2026-09-10 a change was green on build + lint + 1826 tests and did not compile into the
   app ([RV.174]).
5. `xcodegen generate`, then the UI suite you touched **by its suite name**, with an observed,
   **non-zero** count.
6. Localization gate - exit 0; report keys and RU percentage.
7. Release build if you touch a `#if DEBUG` seam. Say which applies.

Verify by **exit code** (`echo $?`), and report the codes you observed.

## Report back

Every check with the **exit code you observed** and the observed counts; whether each test was **run
or only written**; **the named mutation's red-then-green output, verbatim**; **how you verified a
swipe cannot dismiss the sheet**, and what happens if the app is backgrounded while it is up; which
RV.152 assertions you reused rather than duplicated; the other multi-action alerts your audit found;
and **anything you found and did not fix**.

# PJ.56 - a purchase-group header says nothing for `.mixed` and `.pending`

You are working in `/Users/sbelyaev/repos/fuel-counter-ios`. **Write only inside that repo.**
Write code first, explore second. Do not commit; the orchestrator commits after verifying.
**Never move, rename or delete a file you did not create** - assume you are not alone in this
checkout. If a file is in your way or a test is red that is not yours, report it and carry on.

## The defect, pinned to a line

`ios/App/Sources/Home/HomeSections+LogStream.swift`, `groupTotalFigure(_:)`:

```swift
case .complete(let amount, let currency):
    groupTotalText(amount, currency: currency)
case .partial(let amount, let currency, let pendingCount):
    VStack(alignment: .trailing, spacing: 1) {
        groupTotalText(amount, currency: currency)
        Text(L10n.pendingRates(pendingCount))    // ← says why
    }
case .mixed, .pending:
    EmptyView()                                  // ← says nothing at all
```

**The month divider, reducing the SAME `MonthTotal` through the same accumulator, speaks in both of
those cases** - the pending phrase at `:133-136` and `:165-166`, the mixed breakdown at `:239-241`.
So one surface explains its silence and the other, one row lower on the same screen, does not.

A user meets a group card whose header states **no total and no reason**, while the divider above it
says "1 entry pending rates". The member rows below still state each amount, so **nothing is lost** -
what is missing is the explanation, and hard rule 7 asks a surface that withholds a figure to say
why.

**This is pre-existing, not introduced by [RV.166].** The old `grandTotalCurrency == nil` branch
printed nothing too. RV.166 made the silence *principled* (the classification is now correct and
shared) without making it *legible*. Say so in your commit reasoning rather than blaming the row.

## Is it reachable? Confirm this before you build anything

`.pending` requires **every** member's `homeAmount` to be unknown; `.mixed` requires the **known**
members to span two or more home currencies (`LogStream+Accumulator.swift` - read it, and check the
exact conditions rather than trusting this sentence).

**Establish a concrete production sequence for each**, and say what it is:

- `.pending` looks reachable - a foreign receipt logged while offline, dated outside the bundled
  rate pack, is the `RV.106`/`RV.166` shape with no known member.
- `.mixed` is the one I could **not** trace to a real sequence. A single receipt whose lines carry
  two different *home* currencies is unusual - the home currency comes from the car. **If `.mixed`
  turns out to be unreachable in production, say so and treat it differently** (a defensive branch
  is not a user-facing state, and inventing copy for it is waste). That finding is worth more than
  the fix.

If neither is reachable, **report that and stop** - do not write copy for states no user can meet.

## What to build

**Give the reachable silent state the sentence the divider already has.** Reuse `L10n.pendingRates`
and the divider's mixed treatment rather than inventing group-specific copy: the group header and
the divider have classified identically since [RV.166], so they must not *explain* differently.

`.mixed` is the harder call even if reachable: a full breakdown may not fit a header, and *"no
single total"* may be the honest phrase where the divider can afford a list. **Decide, and record it
in `docs/ERRORS.md` beside RV.166's row.**

**Never print a cross-currency total.** That is the hard rule 3 violation [RV.145] removed - a
figure summed across currencies is a wrong number, and `.mixed` exists precisely to refuse it.

## Explicitly out of scope

- `.complete` and `.partial` - [RV.166] settled both; its four tests must stay green.
- The accumulator's classification rules. If you think a case is classified wrongly, **report it**;
  changing them touches every money surface in the app.
- The month divider's own rendering.

## Docs to read before writing (in order)

1. `docs/ERRORS.md` -> **Home, F9** and the RV.166 paragraph - what a partial or withheld figure is
   allowed to say. **This is the authority**; extend it in the same change.
2. `docs/SCHEMA.md` -> Money, and hard rule 3 (money is a pair; a rate snapshot is per entry).
3. `CLAUDE.md` hard rules 3, 4 (a purchase group is counted once), 7.

## Environment axes this crosses

**Locale** - EN and RU if any copy is added; `L10n.pendingRates` already exists and is localised.
**Screenshots: EN and RU required** if the header's words change; if only its shape changes, say so
and skip them with a reason. **Offline** is how `.pending` is reached - say how you exercised it. No
Release seam unless you add a `#if DEBUG` seed (a new seed is likely - `RV166HomeTestSeed.swift` is
the model, and **a new DEBUG seed means the Release build gate applies**).

## If this adds a failure path, what makes it visible in production?

None expected - this is presentation over an existing classification. Say so rather than adding a
log line.

## Tests you must add

- **L1, and it FAILS TODAY**: a `.pending` group reports a state the UI can explain, and the render
  path produces the pending phrase rather than an empty view. **Oracle**: the divider's own output
  for the same members - `L10n.pendingRates(n)` where `n` is the count of members with no
  `homeAmount`. Assert through the shared seam, never a parallel count written in the test.
- **L4**: a `.pending` group header carries the phrase, on screen, not blank space. **Assert the
  frame against the window, never `isHittable`** ([RV.84] measured it true for an element 86%
  clipped).
- **L1**: `.complete` and `.partial` are unchanged, to the cent - RV.166's `LogStreamGroupTotalTests`
  must stay green, and say that you ran it.
- **L1**: no cross-currency total is ever printed for `.mixed` - the negative claim that keeps the
  fix from becoming a hard rule 3 violation.

Name the UI suite you extend and report its observed, **non-zero** test count.

## The mutation you must run - I am naming it, do not choose your own

**Restore `case .mixed, .pending: EmptyView()`** in `groupTotalFigure`. The new test **must go red**
on the explanation, while RV.166's four tests stay green. Then restore and re-run. Report both
outputs verbatim.

## Vacuous traps, named

- **A fixture with only `.complete`/`.partial` members** - it passes today and proves nothing. This
  is the same trap RV.166's brief named, one case further out.
- Making the header print a **single figure** for `.mixed` - the hard rule 3 violation RV.145
  removed.
- Inventing a second vocabulary for what the divider already says.
- Writing copy for a state you could not show is reachable - report unreachability instead.
- Asserting the phrase exists in the hierarchy rather than that it is visible.

## Never stash, move or `git checkout` to get a "clean baseline"

Write the test, run it against the unmodified code, then make the change. **Do not** `git stash`,
`git checkout`, or move files out of the tree: an agent did that on 2026-09-08 and a bad `mv` loop
destroyed three of its own new files.

## Never `pgrep -f` for a build process

Your brief is part of your command line, so `pgrep -f "xcodebuild.*test"` matches **this agent**.
Use `pgrep -x xcodebuild`. **Never `pkill -f`.**

## `simctl launch` on a running app ignores new arguments - `terminate` first

**You cannot see your own screenshots**: state what you captured, never that it looks right. **Check
what is behind your subject** - `RV.149`'s first capture put a correct toast over an empty garage, a
state no user can reach, and it looked like a successful capture.

## Standing checks

Re-measure the baseline yourself and report what you observe.

1. `cd ios && swift build` - exit 0.
2. `swiftlint lint` from the **repo ROOT** - exit 0. From the root, **not** `ios/`: the `excluded:`
   paths are root-relative and from `ios/` it exits 2 with ~5000 phantom errors.
3. `cd ios && swift test` - full, never subsetted; report the count.
4. `xcodegen generate`, then the UI suite you touched by name with an observed, **non-zero** count.
5. Localization gate - exit 0; report keys and RU percentage.
6. **Release build if you add a `#if DEBUG` seed** - `xcodebuild -configuration Release … build`.
   An unguarded call to a DEBUG-only type passes every other check and breaks the release path,
   which is how `PR.11`/`OB.4` reached `main` "verified".

Verify by **exit code** (`echo $?`), and report the codes you observed.

## Report back

Every check with the **exit code you observed** and the observed counts; whether each test was **run
or only written**; **the named mutation's red-then-green output, verbatim**; **the concrete
production sequence that reaches `.pending`, and whether `.mixed` is reachable at all**; what you
decided `.mixed` says and why; and **anything you found and did not fix**.

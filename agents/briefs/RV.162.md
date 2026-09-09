# RV.162 - no test asserts that a screen is reachable, and one shipped that was not

You are working in `/Users/sbelyaev/repos/fuel-counter-ios`. **Write only inside that repo.**
Write code first, explore second. Do not commit; the orchestrator commits after verifying.
**Never move, rename or delete a file you did not create** - assume you are not alone in this
checkout. If a file is in your way or a test is red that is not yours, report it and carry on.

## The defect

Three instances of one shape, **each found by a human**, none by a test
(`docs/DEFECT-PATTERNS.md` Part 2):

| Row | What shipped |
|---|---|
| `PJ.4` | The Reminders screen's only route was gated on a DEBUG flag - **unreachable in a Release build** - with a green suite |
| `PJ.25` | The parts shelf was reachable only from inside a service entry |
| `PJ.20` | Two flows routed "send us this case" to a screen that did not exist |

**Why the suite could not see it**: the UI tests navigate via `-presentScreen`, a DEBUG launch
argument. So every screen is reachable *to a test* whether or not it is reachable *to a user*, and
`PJ.4`'s route **existed and compiled**. A green UI suite is not evidence of reachability, and that
is the precise thing this guard must supply.

## The blocker you must solve first, and it is not the test

`docs/SCREENMAP.md` is the navigation authority, and its screens live in a **markdown table** from
about line 239 (`| **Inbox** (RV.38, RV.45) | … |`). That part is parseable.

**The screens that legitimately have no route are NOT machine-readable.** They are described in a
**single prose paragraph at line 477** - *"The map names screens that exist as nodes but have no
artboard yet"* - which runs to thousands of characters and mixes in the history of five rows,
parenthetical asides about screens that **left** the list, and at least one screen (**Paywall**)
whose doors were deliberately **removed** by `RV.70`.

**A test cannot read that, and the row says so**: *"the marker has to be machine-readable or the
test is unwritable."*

**So your first deliverable is the marker, not the guard.** Add an explicit, machine-readable
marker to `docs/SCREENMAP.md` for every screen with no production route, each carrying **its
reason** - the same discipline `RV.167`'s allowlist uses, and for the same reason: a list without
reasons degrades into a skip list. **Do not delete the prose paragraph's content** - it is the
history of five decisions; move what is normative into the marker and leave the narrative, or say
why you restructured it.

**Be careful with Paywall specifically.** `RV.70` removed its Settings doors on purpose (a blank
`LeafContent` placeholder contradicting the no-IAP listing, `docs/STORE.md` §6). It is
**[v2]**-marked and has exactly one v1 door - the free-tier car-limit sheet. It must not fail your
guard, and the reason it does not must be the *recorded* one, not an accident of parsing.

## This brief's reading is a hypothesis - confirm it before you change anything

Line numbers were read on the tree as left. **Read `docs/SCREENMAP.md` end to end first.** If the
inventory is not the table I describe, or a marker already exists that I missed, build on what you
find and say what differed.

## What to build

**A test that asserts every screen `SCREENMAP.md` lists has at least one NON-DEBUG production route
reachable from a tab root.**

The idiom exists in this repo - reuse it rather than inventing a third way:

- `SyncTriggerSourceGuardTests` (RV.157) reads a doc and binds each named trigger to a call site.
- `MoneyHomeSideSumGuardTests` (RV.167, shipped today) is the closest model: a **pure function over
  source text** plus a tree walk plus a reasoned allowlist with a stale-entry check. **Read it
  before you start.**

The two hard parts:

1. **A DEBUG-only route does not count.** That distinction is the entire point - `PJ.4`'s route
   existed, compiled, and was inside `#if DEBUG`. Your scanner must know the difference between a
   route reference in production code and one inside a DEBUG region or in `DebugLaunch.swift`.
   `Routes.swift` has 63 cases; `Destinations.swift` and `DebugLaunch.swift` are both real and
   only one of them counts.
2. **"Reachable from a tab root" is stronger than "referenced somewhere."** `PJ.25`'s shelf was
   referenced - from inside a service entry, a place a user reaches only mid-task. Decide what
   depth of reachability you can actually assert, **state the limit honestly in the test's comment**,
   and do not claim more than you check. A guard that overclaims is worse than one with a stated
   blind spot.

## Explicitly out of scope

- **[RV.163]** - the "who creates this entity?" guard. Sibling row, same shape, its own dispatch.
  If your scanner generalises to it, **say so in your report**; do not build it.
- **[RV.165]** - the full journey suite. Much larger, and this guard exists partly so that row can
  be smaller.
- Fixing any unreachable screen you find. **Report it** - each is a row.

## Docs to read before writing (in order)

1. `docs/SCREENMAP.md` **end to end** - the navigation authority and the thing you are binding to.
   You will edit it; that edit is half this row.
2. `docs/TESTING.md` -> where an architecture test sits and which gates it needs. Extend it in the
   same change to name this guard, as `RV.167` did.
3. `docs/DEFECT-PATTERNS.md` Part 2 - the product-reachability shapes, which is what this mechanises.
4. `CLAUDE.md` hard rule 14 and its `#if DEBUG` / Release paragraph.

## Environment axes this crosses

**None at runtime** - a test-only change plus a doc edit; no shipping code path differs. No
screenshots, no locale, no offline, no Release seam **unless** you touch a `#if DEBUG` region while
investigating - say which applies. This is the same axes answer `RV.167` gave; if you disagree, say
why.

## Tests you must add

- **L1, and this is the teeth**: **wrap one real production route in `#if DEBUG` and watch the guard
  fail.** The row names this explicitly. Do it, report the output, and **revert the edit**. A guard
  that has never been shown to fail on the real defect is not evidence.
- **L1**: a screen marked planned-not-drawn does **not** fail.
- **L1**: **adding a screen to `SCREENMAP.md` with no route fails** - supply the doc text to the
  scanner as a string, the way `RV.167`'s scanner takes source text, so this is testable without
  editing the real doc.
- **L1**: a marker entry with **no reason** fails the guard's own self-check.

**Oracle for every expectation**: `SCREENMAP.md`'s inventory table is the list; `Routes.swift` plus
non-DEBUG references are the routes; `PJ.4`'s Reminders screen is the historical positive case.

## The mutation you must run - I am naming it, do not choose your own

**Wrap the production route to a real screen in `#if DEBUG`** - pick one that is currently reachable
and say which. The guard **must go red naming that screen**. Then revert and re-run.

That is the mutation because it reproduces `PJ.4` exactly: the route still exists, still compiles,
still passes the UI suite, and the screen is gone from a Release build.

## Vacuous traps, named

- **Counting a DEBUG route**, which is precisely the bug. If your scanner counts `DebugLaunch.swift`
  or anything inside `#if DEBUG`, it passes on `PJ.4`'s defect.
- Asserting a route **exists** rather than that it is reachable from a root.
- A doc parser so loose it passes on anything - test it against a deliberately-broken doc string.
- A marker list without reasons, which becomes a skip list.
- Marking a screen planned-not-drawn to make the suite green. If a screen has no route, that is a
  **finding and a row**, not a marker entry.
- Claiming depth of reachability you did not check.

## Never stash, move or `git checkout` to get a "clean baseline"

Write the test, run it against the unmodified tree, then make the change. **Do not** `git stash`,
`git checkout`, or move files out of the tree: an agent did that on 2026-09-08 and a bad `mv` loop
destroyed three of its own new files.

## Never `pgrep -f` for a build process

Your brief is part of your command line, so `pgrep -f "xcodebuild.*test"` matches **this agent**.
Use `pgrep -x xcodebuild`. **Never `pkill -f`.**

## Standing checks

Re-measure the baseline yourself and report what you observe.

1. `cd ios && swift build` - exit 0.
2. `swiftlint lint` from the **repo ROOT** - exit 0. From the root, **not** `ios/`: the `excluded:`
   paths are root-relative and from `ios/` it exits 2 with ~5000 phantom errors.
3. `cd ios && swift test` - full, never subsetted; report the count. It must be **greater** than the
   baseline you measured.
4. No UI suite expected. If you touch one, name it and report an observed, **non-zero** count.
5. Localization gate - exit 0; report keys and RU percentage.
6. Release build only if you touch a `#if DEBUG` seam. Say which applies - and note the mutation
   above **temporarily** creates one, which is not the same as shipping one.

Verify by **exit code** (`echo $?`), and report the codes you observed.

## Report back

Every check with the **exit code you observed** and the observed counts; whether each test was **run
or only written**; **the named mutation's red-then-green output, verbatim, naming which route you
wrapped**; **the marker format you added to `SCREENMAP.md` and how you handled the line-477 prose**;
the reachability depth your guard actually checks and what it cannot see; **every unreachable screen
you found**; and **anything you found and did not fix**.

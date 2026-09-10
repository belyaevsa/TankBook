# RV.194 - 138 capture lines exist and have never been run

You are working in `/Users/sbelyaev/repos/fuel-counter-ios`. **Write only inside that repo.**
Write code first, explore second. Do not commit; the orchestrator commits after verifying.
**Never move, rename or delete a file you did not create** - and on this row that fence is load
bearing: `design/screenshots/` is the visual record and a deleted frame cannot be recovered from a
test. **Agents never tick `docs/TASKS.md` and never commit.**

## The defect

[RV.176] closed the "a committed PNG no capture line produces" hole by writing a line for each of
**198 orphans**. But its agent **inferred** each line's seed and launch arguments from the task's own
`-seed*` flags and **verified only the `RV.150` pair end to end** - and said so plainly, which is the
report line working.

**A wrong line is worse than no line.** The check goes green because a line EXISTS, not because it
reproduces that frame - which is the exact failure mode RV.176 was filed against. The hole is closed
on paper and possibly open in fact, at up to 138 places.

**Not obviously bad**: the orchestrator sampled `RV.141-home-excluded` and it did reproduce. It is
unverified, not known-wrong. Your job is to turn "unverified" into a list.

## Why this row exists as its own row, and what you can and cannot do

**You cannot see images.** The final judgement - *does this frame show the screen its name claims?* -
is the orchestrator's, and it is why this row was not a footnote on RV.176.

**What you CAN do, and what this row is really asking for**: make that judgement cheap by narrowing
470 frames to a short suspect list mechanically.

## What to build

1. **A comparison that ignores what always changes.** Re-capturing any frame changes the clock, the
   battery and the status bar. So compare **everything below the status bar**: crop a fixed top band
   off both the committed PNG and the freshly captured one, then compare. Report a per-frame
   difference measure, not a boolean - a frame that differs by a hair is a rendering nudge, one that
   differs wholesale is a **different screen**, and only the second kind is this row's finding.
   `sips` and `ImageMagick`'s `compare` may or may not be present; **check first and say which you
   used**. A tiny Swift or Python helper using CoreGraphics is acceptable if neither is.
2. **Run the full capture** and produce the ranked list: every frame whose below-the-status-bar
   content differs materially from the committed PNG, worst first, with its capture line.
3. **Fix the lines you can prove wrong** - where the frame is plainly a different screen AND the
   right seed is obvious from a sibling line. **Where it is not obvious, list it and stop**; a guess
   at a seed is how this row was created.
4. **Record `runtime` and `device` truthfully in the manifest.** The 463 bootstrapped entries were
   stamped `iOS.26.5`/`iPhone 17` by default; a few historical frames were shot on `iPhone 17 Pro`
   (see `RV.28`'s brief). A full run refreshes them from the machine that actually took them.

## The second finding, and settle it in the same pass

Several frames carry a **previous screen's header bleeding through at the top** - a "Reminders" title
over Home, a conflict banner over Edit entry. The capture fires **mid-transition**. A frame caught
between two screens is not a record of either.

Find where `scripts/capture-screenshots.sh` decides the screen has settled and make it wait for the
screen it asked for rather than for a fixed delay. **Say what the current wait is** before you change
it. If the fix is a longer sleep, say so and say why nothing better is available - a settle
condition tied to the app's own state is much better than a bigger number.

## This brief's reading is a hypothesis - confirm it before you change anything

**Re-run the audit yourself.** In particular: the count "138 reconstructed lines" comes from RV.176's
own report. Establish which lines are actually new - `git log -1 --format=%H -- scripts/capture-screenshots.sh`
and the diff of commit `09b9e50` will tell you exactly - and work from that list, not from a number
in a report.

## Explicitly out of scope

- The screenshots' **content** and any UI change. If a frame reveals a UI defect, **file it in your
  report**; do not fix it here.
- `PR.36` (the iOS 18 re-record). Not now.
- The 5 `legacy` entries. They are reasoned and cannot be produced by a line.
- Deleting any PNG. If a frame has no honest line, report it.

## Docs to read before writing (in order)

1. `scripts/capture-screenshots.sh` end to end, and `scripts/check-screenshot-manifest.sh`.
2. `git show 09b9e50 -- scripts/capture-screenshots.sh` - the 138 lines under audit.
3. `docs/TESTING.md` -> where the screenshot gate is declared.
4. `CLAUDE.md` -> Conventions, the screenshot rules (EN **and** RU, dark theme).

## Environment axes this crosses

**Runtime and device are the row's own subject** - record them truthfully rather than defaulting
them. **Locale**: every `-ru` frame is half the record and must be re-shot too. Note the standing
warning: **never `SKIP_BUILD=1` after changing the source**, which on 2026-09-10 photographed a
mutated binary and presented it as proof of a fix.

## If this adds a failure path, what makes it visible in production?

None - tooling and CI only, never the app. Say so.

## Tests you must add

- **A test for the comparison itself, both directions**: two frames that differ only in the clock
  band compare as SAME; a frame paired with a genuinely different screen compares as DIFFERENT. Use
  two committed PNGs you already have rather than inventing images.
- **The settle fix's test**: whatever condition you add, prove it waits - a pose that used to catch
  the previous screen no longer does. If that cannot be tested automatically, **say so plainly**
  rather than implying coverage.

Report each check's observed, **non-zero** count.

## The mutation you must run - I am naming it, do not choose your own

**Point one capture line at the wrong seed** - take a line whose frame you have verified and swap its
`-seed*` for another screen's - re-run that one frame, and show your comparison reports it as
materially different. Then restore the line byte-identical and show it reports SAME.

That is the mutation because it is exactly the defect this row exists to find: a line that produces
*a* frame, but not *that* frame.

## Vacuous traps, named

- **Comparing whole images including the clock**, so every frame differs and the list is the whole
  corpus. That is the same as no check.
- **Comparing with a checksum.** Anti-aliasing and the battery glyph move; the row says so.
- **Guessing a seed** to make a line "work". That is how the 138 lines were written.
- Declaring the audit done without saying **how many frames you actually re-shot** - a partial run
  reported as a full one is the failure being audited, repeated.
- Fixing the mid-transition bleed with a bigger sleep and not saying that is what you did.

## Never stash, move or `git checkout` to get a "clean baseline"

An agent's `git stash` + `mv` loop destroyed three of its own new files on 2026-09-08. On this row
that would destroy committed screenshots.

## Never `pgrep -f` for a build process

Your brief is in your command line, so `pgrep -f "xcodebuild.*test"` matches **this agent**. Use
`pgrep -x xcodebuild`. **Never `pkill -f`.**

## `simctl launch` on a running app ignores new arguments - `terminate` first

**You cannot see your own screenshots**: state what you captured and what your comparison measured,
never that a frame looks right.

## Standing checks

1. `bash -n scripts/capture-screenshots.sh` and the check script - exit 0.
2. `bash scripts/check-screenshot-manifest.sh` - exit 0 on a clean tree, non-zero on a planted orphan.
3. `bash scripts/tests/check-screenshot-manifest.test.sh` - exit 0; report the count.
4. `swiftlint lint` from the **repo ROOT** - exit 0, if you touch any Swift.
5. The **full** capture run - report how long it took and how many frames it produced.

Verify by **exit code** (`echo $?`).

## Report back

**The ranked suspect list first** - that is the deliverable even if you fix nothing: every frame whose
content differs materially, with its difference measure and its capture line. Then: which lines you
fixed and on what evidence; which you left and why; how many frames you re-shot out of how many
exist; what the mid-transition wait was and what you changed it to; the mutation's output both ways;
and **anything you found and did not fix**.

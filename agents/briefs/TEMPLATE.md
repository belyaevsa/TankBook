# Brief template

*A brief is assembled from this file, not remembered. Every fence below exists because something went
wrong once, and each is followed by the evidence - a fence with no incident behind it is guesswork and
should be cut, not kept.*

**Do not dispatch a brief that skips the three questions in Part A.** They cost minutes and they are
what turns one task into one task instead of a family of them.

---

## Part A - three questions to answer BEFORE writing the brief

Each comes from a class in `docs/DEFECT-PATTERNS.md` that cost this project multiple rows.

1. **Does this defect have siblings?** `grep` for the shape, not the symptom. A rate-pending row
   summed as zero appeared on **five** surfaces across five rows; the echo loop took three arms.
   **Put the inventory in the brief.** The fix ships with every sibling fixed or every sibling filed.
2. **Does anything create the state this touches, and can a user reach it?** One grep for the write
   path. `PJ.19`, `RV.150` and a Garage list all shipped onto a station set nothing could populate.
3. **Does the doc or comment match the code?** The row's premise is usually months old. `PJ.28`,
   `PJ.19` and `RV.139` all carried stale premises; `recordsEqual`'s comment documented its own bug
   as deliberate. **Name the stale part in the brief** so the agent does not re-derive it.

4. **Which environment axes does this change cross, and which will you test?** Release vs Debug is
   only one - and it is the one that hid `PJ.4`'s unreachable screen. The others that have bitten
   this project: **clean install vs upgrade**, **offline**, **locale** (`RU` strings run 20-30%
   longer and RU screenshots have caught three defects), **Low Power Mode**, **signed-out**, and
   **stale cache**. Name the axes the change touches and say which you exercised; "none" is an
   answer, but it has to be a stated one.
5. **If this adds a failure path, what makes it visible in production?** `RV.139` cost three builds
   because no event existed to say which branch was taken - the fix was not code, it was a log line.
   A new error, fallback, deferral or silent no-op needs the shape-only event that would let one
   session's log answer "did this happen?" (`docs/LOGGING.md`, hard rule 12).

Then: **pin the cause to a file and a line.** A task with a confirmed cause is mechanical whatever
area it touches, and that is what makes flash the right default.

---

## Part B - the sections a brief carries, in order

1. **Where you may write** - a whitelist (`only inside <repo>`), never a blacklist.
2. **Write code first, explore second.**
3. **The defect**, with the cause pinned to a line, and **what is already ruled out** so the run is
   not spent re-deriving it.
4. **"This brief's diagnosis is a hypothesis - confirm it before you change anything."** Four of the
   orchestrator's diagnoses were wrong in one session and an agent caught every one.
5. **What to build**, and **explicitly out of scope** - naming the neighbouring rows by id.
6. **Docs to read, in order**, with the authority marked, and **extend them in the same change**.
7. **Checks** - build, lint **from the repo ROOT**, full test suite, named UI suites, localization,
   Release when a `#if DEBUG` seam is touched. Judged by **exit code**.
8. **Tests you must add**, including at least one that **fails on the current code**.
   - **Every expectation names its ORACLE** - the domain rule, the independent calculation, or the
     hand-verified fixture the number came from. *"150.00 because the receipt's `KOKKU` line says
     so"* is an oracle; *"expect 150.00"* is not. A checks row is where a plausible wrong number gets
     frozen: `MoneyBackfillServiceTests` asserted `costPerKm == 0.1` for a window whose pending row
     was skipped, canonising the defect `RV.147` later removed.
   - **The BRIEF names the mutation**, not the agent. Pick the line that carries the row's headline
     claim and say "revert this, the test must go red". An agent choosing its own mutation proves
     sensitivity to *that edit*, not that the assertion encodes the requirement - and it will choose
     the easy one.
9. **Vacuous traps, named** for this task.
10. **Screenshots** for any UI change, EN and RU.
11. **Report back** - exit codes observed, whether each test was **run or only written**, and
    **"anything you found and did not fix"**.

---

## Part C - standing fences, and the incident behind each

Paste all of these. They are short, and each one is a mistake that already happened.

- **`swiftlint lint` from the repo ROOT, not `ios/`.** Root-relative `excluded:` paths; from `ios/` it
  exits 2 with ~5000 phantom errors. *(The orchestrator got this wrong three times in one session.)*
- **Check the test COUNT, not the exit code.** A `--filter` or `-only-testing:` matching nothing
  prints "0 tests … passed" and exits 0. *(Happened twice; several RV suites are `extension
  HomeUITests`, so a class-name filter matches nothing.)*
- **Never stash, move or `git checkout` for a clean baseline.** Write the test, run it, then change
  the code - or mutate one line to prove the test's teeth. *(An agent's `git stash` + `mv` loop
  destroyed three of its own new files, 2026-09-08.)*
- **Never `pgrep -f`; use `pgrep -x`. Never `pkill -f`.** The brief is in the process arguments, so
  `-f` matches the agent itself and its siblings. *(One agent killed another 48 minutes in,
  2026-08-24.)*
- **`simctl launch` on a running app ignores new arguments** - `terminate` first. *(An "RU"
  screenshot was English with Russian dates; it passes an md5-difference check and is still wrong.)*
- **Assume you are not alone in the checkout.** Never move, rename or revert a file you did not
  create; report it and carry on. *(A dispatched agent moved another session's uncommitted migration
  out of the repo, 2026-09-04.)*
- **You cannot see your own screenshots.** State what you captured; never assert it looks right.
- **Assert a frame against the window, never `isHittable`.** *(It returned true for an element 86%
  clipped, `RV.84`.)*

---

## Part D - what makes a report useful

Ask for these explicitly or they do not arrive:

- **Exit codes observed**, not prose. A summary is a claim; `echo $?` is evidence.
- **Run or only written**, per test.
- **The failing-then-passing output** for the headline test.
- **"Anything you found and did not fix."** Six rows in one session came from this line -
  `RV.148`, `RV.149`, `RV.150`, `RV.153`'s leftovers and two Trends findings. A fence plus a report
  is how a task stays one task and nothing is lost.

---

## Part E - what the orchestrator still owns, and cannot delegate

- **Open every screenshot.** No test asserts colour, truncation or language. Three defects in one
  session were visible only in an image.
- **Run the gates yourself.** An agent's green is a claim until it is reproduced.
- **Commit.** Agents never commit and never tick `docs/TASKS.md`.
- **Stage explicit paths, never a directory, while a dispatch is live.** *(`git add ios/Tests` swept a
  running agent's file into an unrelated commit.)*

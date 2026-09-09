# Agent briefs

One file per dispatched agent task, named for its task id in `docs/TASKS.md`
(`P1.2.md` briefs task P1.2). **Every brief is written here before dispatch, not in a temp directory** –
these are the record of what an agent was actually asked to do, which is the only way to tell a bad
agent from a bad brief after the fact.

## Why they are kept

Three P0.12 runs produced zero files. The post-mortem was only possible because the brief could be read
back alongside the run log, and it showed the failure was ours twice over: the write fence was a
blacklist (`don't write to /tmp`) that an agent stepped around by writing to `/tmp_gen.swift` at the
filesystem root, and the task was too large to finish in one run. Neither was visible from the code,
because there was no code.

A brief is also the cheapest place to fix a recurring mistake: a fence added here is a mistake that does
not happen again.

## Assemble a brief from `TEMPLATE.md`, do not remember it

`TEMPLATE.md` carries the three pre-brief questions, the section order, the standing fences with the
incident behind each, and what to ask for in the report. **Every fence in it exists because something
went wrong once** - and they demonstrably work: after the `git stash` fence was added mid-session, no
later agent repeated it; after the `pgrep -x` fence, no sibling was killed. What is fragile is the
orchestrator remembering to paste them, which is what the template is for.

**Part A is the half that is easy to skip and expensive to skip**: does this defect have siblings,
does anything create the state it touches, does the doc match the code. Those three questions come
from `docs/DEFECT-PATTERNS.md`, where each is backed by a class that cost multiple rows.

## What a brief contains

The pattern these converged on, in order:

1. **Where you may write** – a whitelist (`only inside <repo>`), never a blacklist. A single rejected
   tool call kills an unattended run.
2. **Write code first, explore second** – the dominant failure mode is a run that reads everything and
   writes nothing.
3. **What NOT to explore** – closed questions, named. One run spent its whole budget cross-verifying
   Ed25519 across languages; it is standardised and the real risk was canonicalization.
4. **What already exists** – types, files and signatures the task builds on, so the agent does not
   redesign or duplicate them.
5. **Read before writing** – the specific docs, in order, with the authority for this task marked.
6. **What to build**, then **explicitly out of scope**.
7. **Tests, with current counts** – "`swift test` is 193 and must rise" is checkable; "add tests" is not.
8. **The baseline gate** – build + `swiftlint lint` exit 0, judged by exit code (`CLAUDE.md` rule 14).
9. **Report back** – exact numbers, and *whether tests were actually run* rather than only written.

## Conventions

- **Sized to finish in one run.** P0.12 delivered nothing three times as a single task, then went green
  in two runs once split into a/b/c. Nothing about the prompt changed; the size did.
- **Quote spec copy verbatim** (error strings, tolerances, invariants) rather than paraphrasing – a
  paraphrased error message ships as a paraphrased error message.
- **Name the vacuous-assertion traps** for that task. `#expect(true)`, asserting only that a call did not
  throw, or a "tamper" test that mutates a field the code never reads.
- A brief that turns out to be wrong is **edited and re-dispatched**, keeping the same file. Only a brief
  replaced by a different decomposition gets a `-superseded` suffix, kept for the record.

## Name the UI suites; do not ask for the whole thing

Since 2026-08-29 the full UI suite belongs to **phase completion**, not to every task. A brief asks
for `swift build`, `swiftlint`, all 873 unit tests, and `-only-testing:` the suites that task
touched - **named explicitly**. "Run the UI tests" is not a check, and a `--filter` that matches
nothing prints "0 tests ... passed", so the brief should also ask for the observed count.

The cost of the old wording, measured: five full runs in one day, about two and a quarter hours,
one genuine defect, two false reds from machine contention.

## Never `pgrep -f` for a build or test process

**An agent's brief is part of its command line.** `opencode run ... "$(cat brief.md)"` puts the
whole brief into the process arguments, so `pgrep -f "xcodebuild.*test"` matches **any agent
whose brief mentions running xcodebuild** - and `pkill -f` on that pattern kills it.

That is not hypothetical. On 2026-08-24 the P2.3 agent ran
`pgrep -f "xcodebuild.*test"` to check the device was free, matched the concurrently-running
P2.1b agent, and killed it 48 minutes into its task. P2.1b's log simply stops mid-edit; nothing
in it looks like a failure, and `agent-health.sh` reported it as EXITED, which reads exactly
like "finished". Only the P2.3 agent's own honest report revealed what happened.

Match the **process name** instead: `pgrep -x xcodebuild`. Any brief that tells an agent to
check for a running build must say so explicitly, and no brief should ever hand an agent a
`pkill -f` pattern.

This bites harder with worktrees, where several agents run at once by design.

## Screenshot pitfalls (learned the hard way)

- **Seeds are idempotent and silently do nothing on a populated database.** `-seedEditEntry` and the
  `-seedHome*` family all bail once a vehicle exists, so a capture run against a previous run's database
  renders "Entry not found" instead of the screen. Always pass `-homeResetDatabase` alongside the seed.
- **An agent cannot see its own screenshot.** The DeepSeek runs have no image input, so they verify by
  accessibility tree or OCR and can ship a screenshot of an error state believing it is the screen. P1.6
  shipped two such images. **The orchestrator must open every screenshot** - that is the check the whole
  convention exists for.
- **Never drive the simulator while `xcodebuild test` is running** - they fight over the device and the
  test run fails in a way that looks like a real regression.

## Never stash, move or `git checkout` to get a "clean baseline"

A brief that says *"run your new tests against the current code first, they must fail"* is asking
for a real thing, and the obvious way to do it is the destructive one. On 2026-09-08 the `RV.144`
agent read that line, ran `git stash push` (tracked files only), moved its four **untracked** new
files to a temp directory, and then a bad `mv` loop sent them all to the same destination path so
each overwrote the last - **three files lost**, recovered only because their contents were still in
the agent's own context. Nothing of the orchestrator's was damaged, but only by luck: the same loop
would have taken a concurrent session's uncommitted work, which is exactly what happened on
2026-09-04.

**The safe recipe needs no stash at all:**

1. Write the test.
2. Run it against the unmodified code and watch it **fail**.
3. Then make the production change and watch it **pass**.

If the change is already written, prove the test's teeth with a **mutation** instead: revert the one
line the test is about, run the test, restore the line. That is a smaller, reversible edit than
moving the working tree, and it proves more - it shows the test fails for the reason claimed.

Every brief that asks for a fail-then-pass demonstration must carry this fence.

## `simctl launch` on a running app silently ignores new arguments

The RU capture is where this bites. `xcrun simctl launch` on an app that is already running does
**not** relaunch it with the new arguments - it foregrounds what is there. So the "RU" shot is the EN
one with a different clock, and the agent cannot see that it happened.

**Always `xcrun simctl terminate <device> <bundle>` first, and wait for the relaunch to settle before
the screenshot.** The capture script does this; a hand-rolled capture loop is where it gets missed.

The tell is subtle and worth knowing: on 2026-09-09 the RV.145 agent's "RU" screenshots had Russian
**date formats** (`9 Sep`) and English **strings** everywhere else - `-AppleLocale` had taken effect
and `-AppleLanguages` had not, because the process had not actually restarted. A byte-identical file
is the easy case; this one passes an md5 check and is still wrong.

**This is why the orchestrator opens every screenshot.** No test catches it, and the agent has no
image input.

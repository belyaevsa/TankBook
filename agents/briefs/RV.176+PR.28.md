# RV.176 + PR.28 - a committed screenshot no capture line can reproduce

You are working in `/Users/sbelyaev/repos/fuel-counter-ios`. **Write only inside that repo.**
Write code first, explore second. Do not commit; the orchestrator commits after verifying.
**Never move, rename or delete a file you did not create** - except as this brief's audit explicitly
decides, and then only with the reason recorded. **Agents never tick `docs/TASKS.md` and never
commit.**

**Two rows, one dispatch**: `PR.28` already specifies the mechanism `RV.176` needs. RV.176 is the
defect; PR.28 is the manifest and the CI check. Building either alone touches the same file twice.

## The defect (RV.176)

`design/screenshots/` is the visual record - the **only** check that catches colour, truncation and
layout, because XCUITest asserts behaviour and never how a screen looks. A committed PNG that no
capture line produces is therefore evidence nobody can regenerate: a shared change (a palette token,
a font, a screen) silently invalidates it, and it ages into confident proof of code that no longer
exists.

**Three instances in about twelve hours**, which is what moved this from tidy-up to a gap:

| Row | What happened |
|---|---|
| `RV.150` | `RV.150-station*.png` committed; the script had **no `stationSettings` pose at all** until `PJ.55` added one |
| `RV.152` | Committed a pair, no capture line. They depicted a system alert `RV.177` then retired - stale within a day, and deleted by the orchestrator |
| `RV.177` | Committed a pair, no capture line; the orchestrator added the lines and re-shot through the script |

## What PR.28 already specifies

> `design/screenshots/manifest.json` (file → runtime, device, commit) written by
> `capture-screenshots.sh`; CI fails a PNG without an entry; the iOS 18 re-record task registered.
> **Check**: script run produces the manifest; CI check exits non-zero on a planted orphan PNG.

**That is RV.176's check.** Build it as written; the two rows differ only in that RV.176 supplies the
evidence for why.

## What to build

1. **The manifest**, written by `scripts/capture-screenshots.sh` on every run: for each frame it
   produces, the file, the **runtime**, the **device** and the **commit**. The runtime matters
   because of a standing decision - snapshot baselines recorded on iOS 26.5 **are not valid for iOS
   18** (`CLAUDE.md`), so a frame's runtime is part of what it proves.
2. **The check**: a committed PNG with no manifest entry fails. Mirror the duplicate-frame check the
   script already carries (`4bbb302`) - that one catches two names for one frame; this catches a
   name no line produces.
3. **Close today's gap**: audit `design/screenshots/*.png` against the names the script produces
   (`capture` **and** `alias_shot`), and for each orphan either **add the capture line** or **delete
   the file**. Report the full list and which you did for each.

**Deleting is not always right.** `docs/SITE.md`, `site/hugo.toml`, `site/content/*` and several
briefs reference screenshots by filename - `P1.4-home` and `P1.1-shell-dark` are cited by the site.
**Check every reference before deleting anything**, and prefer adding the line.

## This brief's reading is a hypothesis - confirm it before you change anything

Re-run the audit yourself; the three instances above were found by hand and the real list may be
longer. If the manifest turns out to need something PR.28 did not anticipate - a frame produced by
`alias_shot` rather than `capture`, say - **say so** and record the shape you chose.

## Explicitly out of scope

- `RV.175` (About has no scroll hook) - a separate row, though it is why one frame was deleted rather
  than fixed.
- Re-recording anything for iOS 18. PR.28 says **register** that task, not do it.
- The screenshots' content.

## Docs to read before writing (in order)

1. `scripts/capture-screenshots.sh` **end to end** - especially the `alias_shot` helper and the
   duplicate-frame check at the end; you are extending both ideas.
2. `docs/TESTING.md` → where a CI gate is declared. Extend it to name this check.
3. `docs/SITE.md` and `site/` - who references a screenshot by filename, before you delete one.
4. `CLAUDE.md` → Conventions, the screenshot rules.

## Environment axes this crosses

**None at runtime** - tooling and a check; no shipping code path differs. **No screenshots of your
own** (a manifest is not a screen), and say so rather than shipping one. Note the script's own
warning: **never `SKIP_BUILD=1` after changing the source**, which on 2026-09-10 photographed a
mutated binary and presented it as proof of a fix.

## If this adds a failure path, what makes it visible in production?

None - this runs in CI and on a developer's machine, never in the app. Say so.

## Tests you must add

- **A check-script test, and it FAILS TODAY on a planted orphan**: plant a PNG with no capture line,
  run the check, assert non-zero. **Then remove it.** This is PR.28's own stated acceptance.
- **The mirror**: with the tree clean, the check exits zero. Both halves, or the check is untested in
  the direction that matters.
- **A manifest test**: a script run produces an entry per frame, carrying file, runtime, device and
  commit.
- **An `alias_shot` frame gets a manifest entry too** - the copies are real committed files, and a
  check that ignores them has a hole exactly where the script's own cleverness lives.

Report the observed, **non-zero** count for anything test-shaped, and the check's exit codes both
ways.

## The mutation you must run - I am naming it, do not choose your own

**Delete one capture line whose PNG stays committed** - reproducing `RV.150`'s exact state. The check
**must fail naming that file**. Then restore the line and re-run. Report both outputs verbatim.

That is the mutation because it recreates the defect as it actually occurred, rather than as a
synthetic orphan.

## Vacuous traps, named

- **Adding the missing lines and no check**, so the next out-of-band capture is invisible again -
  the row exists because this happened three times.
- Matching on a **prefix** rather than an exact name, which lets `-ru` and `-xl` variants pass on
  their base name.
- **Deleting a screenshot the site or a doc references** - check first.
- A manifest the script writes but nothing reads.
- Ignoring `alias_shot` copies.

## Never stash, move or `git checkout` to get a "clean baseline"

An agent's `git stash` + `mv` loop destroyed three of its own new files on 2026-09-08.

## Never `pgrep -f` for a build process

Your brief is in your command line, so `pgrep -f "xcodebuild.*test"` matches **this agent**. Use
`pgrep -x xcodebuild`. **Never `pkill -f`.**

## Standing checks

As left, `main` is **1864 tests / 222 suites**, **829** localization keys at 100% RU.

1. `cd ios && swift build` - exit 0.
2. `swiftlint lint` from the **repo ROOT** - exit 0 (from `ios/` it exits 2 with ~5000 phantom errors).
3. `cd ios && swift test` - full; report the count.
4. `bash -n scripts/capture-screenshots.sh` - exit 0, and **run the script with a `FILTER`** to prove
   the manifest is written; say which frames you shot.
5. The new check, **both directions** - clean tree zero, planted orphan non-zero.

Verify by **exit code** (`echo $?`).

## Report back

Every check with the **exit code observed**; **the mutation's red-then-green output, verbatim**; **the
full orphan audit** - every committed PNG with no producing line, and whether you added a line or
deleted it, with the reason; the manifest's shape and why; whether any doc or site file referenced a
file you touched; and **anything you found and did not fix**.

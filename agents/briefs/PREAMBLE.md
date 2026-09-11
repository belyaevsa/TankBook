## Standing fences - appended to every build brief by `scripts/dispatch.sh`

Each one exists because something went wrong once. They are not advice.

**Where you may write.** `/Users/sbelyaev/repos/fuel-counter-ios` only. Write code first, explore
second. **Do not commit; never tick `docs/TASKS.md`** - the orchestrator verifies, ticks and commits.
**Never move, rename or delete a file you did not create.**

**Never `git stash`, `mv` or `git checkout` to get a "clean baseline".** An agent's stash + mv loop
destroyed three of its own new files on 2026-09-08. `git log -S`, `git show`, `git diff` are fine -
they write nothing.

**Never `pgrep -f` for a build process.** Your brief is in your own command line, so
`pgrep -f "xcodebuild.*test"` matches YOU. Use `pgrep -x xcodebuild`. **Never `pkill -f`.**

**`simctl launch` on a running app ignores new arguments** - `terminate` first. **You cannot see
your own screenshots**: state what you captured, never that it looks right. **Never pass
`SKIP_BUILD=1` after changing the source** - it photographs the previous binary.

**Concurrent work in this checkout.** A corpus run may hold uncommitted changes under
`Spike/ReceiptSpike/fixtures/`, `PumpPhotoGate.swift` and `ios/Tests/TankbookCoreTests/Corpus*`.
Do not touch, revert or checkout any of them. Pre-existing and not yours: `SyncWriteTriggerTests`
(`RV.203`) fails under machine load and passes alone - re-run it alone before reporting it.

**Fix the sibling when it is the same function or line; file it when it is a different decision.**
A fix that stops one entry kind, one door or one screen short of the code it shares is how this
codebase produces its most common defect (`docs/DEFECT-PATTERNS.md`). If you file, name the seam.

**Standing checks - verify by exit code (`echo $?`), report every count.**
1. `cd ios && swift build` - 0.
2. `swiftlint lint` from the **repo ROOT** - 0 (from `ios/` it exits 2 with thousands of phantom errors).
3. `cd ios && swift test` - full, alone; report the count.
4. `xcodebuild ... build` for the app target (`RV.174`: `swift build` compiles the package only).
   **Release too** if you touched a `#if DEBUG` seam.
5. `xcodegen generate`, then **each suite by name, in its own invocation**: `-only-testing` across
   the app-target bundle and the UI bundle in one command runs ONE of them and exits 0 (found
   2026-09-11). Report a non-zero count per suite - a filter matching nothing prints SUCCEEDED.
6. Localization gate - 0; report keys and RU percentage. **EN + RU screenshots** for any UI change,
   dark theme, with capture lines added to `scripts/capture-screenshots.sh` (`RV.176` fails CI on a
   frame no line produces).
7. `bash scripts/check-screenshot-manifest.sh` - 0.

**Report back**: every check with its observed exit code and count; the named mutation's
red-then-green output **verbatim**; what you captured; **anything you found and did not fix**, with
the row that owns it or a statement that none does.

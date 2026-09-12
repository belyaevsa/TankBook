# RV.257 + RV.258 - two tests that follow the host, not the tree

**no-scenario: test determinism.** Both cost the orchestrator false attributions on 2026-09-12;
neither is a product defect. One dispatch because both are "make the gate say what was verified".

## RV.257 - a sign-in L4 gives a real-transport first push five seconds

`SignInUITests.testEmptyRestoreShowsRecoveryBeforeAddCarIsUsable` failed 3 of 5 runs on one tree
then passed twice: after *Start fresh*, `finish(.acceptEmpty)` awaits `AppSync.firstPushNow` →
`syncNow` against whatever `apiBaseUrl` resolves to, because `-signInStubAuth` stubs auth but NOT
the sync transport (`SignInTestSeed.swift:120`). `testSignInWithLocalLogUploadsAndCompletesTheFlow`
is the same shape and failed for two agents.

**Build**: seed the sync transport in the stub-auth scenario through the `SeededLaunchTransport`
seam that already exists (read how `-seedSettingsSignedIn` and the sync stubs do it), so the first
push answers instantly and deterministically. Keep the 5-second window - widening it hides the
dependency instead of removing it.

**Check**: run each of the two tests 5 times in a row (own invocations) and report 5/5 each.
**Mutation**: remove the seeded transport; report how many of 5 runs fail.

## RV.258 - the four real-center reminder tests follow the simulator's notification daemon

`ReminderNotificationActionTests` real-center tests (`:76,110,150,179`) were 4/4 in the morning
and 0/4 from midday on the same tree, unchanged by a simulator shutdown and an erase. Their own
comment (`:200`) documents the daemon dropping every `add` from a test-hosted process; the
recording-scheduler siblings already cover the orchestration.

**Build**: probe the center once per run - arm one request, read it back - and when the daemon
drops it, `XCTSkip` the four real-center tests with the documented reason, so the bundle count
says what was actually verified. Never delete the real-center tests: they are the only proof the
real center honours the identifiers.

**Check**: on this host the bundle reports the skips (count them in the report); the
recording-scheduler siblings still run. **Mutation**: break a recording-scheduler sibling's
assertion and show the bundle still goes red - the skip must not swallow the orchestration proof.

## Gates

`swift test` in full, `TankbookTests` in its own invocation with its skip count, lint 0. No UI.

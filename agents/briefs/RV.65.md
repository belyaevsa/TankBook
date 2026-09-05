# RV.65 – a dead session on `/extract` uploads the photo twice, forever, and says nothing

Found 2026-09-04 in a production log the product owner supplied. **The cause is confirmed in code –
confirm it still holds, do not re-derive it.**

## Where you may write

Only inside `/Users/sbelyaev/repos/fuel-counter-ios` – **`ios/` and `docs/` only.**
**Do not run `git add` or `git commit`. Do not touch `docs/TASKS.md`.** Touch no `backend/` file.
**Never move, rename or delete a file you did not create.** `.claude/worktrees/rv48` belongs to
another session and is not your gate.

**Use the `iPhone 17` simulator.**

## The measurement – this is what the row exists to move

Eight capture attempts between **18:18:32 and 20:59:16** (two hours forty-one minutes), each
producing **two** `POST /v1/extract -> 401`, every one carrying `RequestBytes=53457`:

    18:18:32 (604 ms) + 18:18:33 (177 ms)
    18:19:43 (359 ms) + 18:19:43 (177 ms)
    18:28:26 (541 ms) + 18:28:27 (177 ms)
    18:29:37 (360 ms) + 18:29:37 ( 16 ms)
    20:38:54 (360 ms) + 20:38:54 (178 ms)
    20:40:06 (349 ms) + 20:40:07 (177 ms)
    20:58:05 (355 ms) + 20:58:05 (175 ms)
    20:59:15 (543 ms) + 20:59:16 (177 ms)

**16 uploads of the same 53 KB image – about 855 KB of the user's mobile data – for nothing.** At
the end of it the user has no entry and has never been told why.

## The cause, verified

`ios/Sources/TankbookCore/Config/TankbookHTTPClient.swift:187-190`:

```swift
if response.status == 401, let refresher {
    let token = try await refresher.refresh()
    response = try await follow(traced, remainingRedirects: maxRedirects, overrideToken: token)
}
```

It replays the **whole request**, body included. For a JSON sync pull that is nearly free; for
`/extract` it re-sends the image.

**The replay was doomed before it was sent.** The log contains **no** `/v1/auth/refresh` line
anywhere between those pairs, so the refresher returns a stale token without a round trip. The tell
is the timing: the second call is consistently **177 ms** against 360-600 ms for the first – the
shape of a request rejected earlier in the pipeline.

## What to build

**(a) Do not replay a large body against a token that did not actually change.** If `refresh()`
hands back the same bearer, there is nothing to retry - fail immediately. A genuine rotation still
replays once. **Say how you decided "unchanged"** - comparing the token value is the obvious way and
is fine; say so rather than leaving it implicit.

**(b) A 401 on `/extract` must name its next step** (hard rule 7). The capture surfaces something
like "sign in to use cloud reading" and **stops**, instead of failing silently eight times across an
evening. **The entry must still be saveable**: the local parse runs regardless (hard rule 1 - no
screen is sync-gated; hard rule 15 - typing is a peer door), so the honest behaviour is a working
manual entry plus a named reason the cloud half is unavailable. It must **survive being ignored**.

**Check the same replay path for `/blobs`**, which also carries bytes, and report what you find -
fix it here only if it is the same one-line shape, otherwise name it separately.

**Do not fix this by removing the 401 refresh-and-retry.** It is correct and load-bearing when the
token really did rotate; the defect is replaying a large body when it did not.

## Read before writing

1. **`CLAUDE.md`** – hard rules 7 (every error names its next step and survives being ignored), 1,
   15, 10 (String Catalogs, EN+RU, whole phrases), 12 (log codes and counts, never payloads), 14.
2. `docs/ERRORS.md` – the capture/gateway rows; add the signed-out row if it is missing.
   `docs/API.md` – `/extract` status codes. `docs/SECURITY.md` – token lifetime.
3. `ios/Sources/TankbookCore/Config/TankbookHTTPClient.swift` (`send`, `follow`),
   `ios/Sources/TankbookCore/Extraction/Gateway/GatewayExtractClient.swift`,
   `GatewayScanSession.swift`, `ios/Sources/TankbookCore/Sync/RemoteBlobTransport.swift`,
   and whatever provides `refresher` (see RV.26's refresher work).

## Tests

**iOS unit 1378 today; must not fall.** Name the UI suites you run with `-only-testing:`; expect
`GatewayCaptureUITests` and `CaptureUITests`.

- **The headline L1, over a recording transport: a 401 whose refresh returns an UNCHANGED token
  sends the body ONCE.** Assert the **request count AND the total bytes sent** - "the call failed"
  passes against this bug today, and bytes are the thing this row exists to reduce.
- L1: a refresh that genuinely rotates the token still replays exactly once, and succeeds.
- **L4: a capture with a dead session shows the sign-in next step, and the manual form still
  saves.** Both halves - the named step, and that nothing is sync-gated.
- L1: the message survives being ignored (dismiss it, Save still works).

**Vacuous-assertion traps, named:**
- Asserting the extract call threw. It already throws.
- Asserting one request without asserting bytes - the payload is the defect.
- Testing with a tiny body, which hides the exact cost this row removes. Use a realistic rendition.
- Asserting an error string exists rather than that Save is still reachable.

**Mutation-check and report it**: restore the unconditional replay and confirm the bytes/count test
goes red. Restore byte-for-byte, confirm green.

## The baseline gate (CLAUDE.md rule 14)

    cd ios && swift build ; echo "BUILD=$?"
    cd ios && swift test ; echo "IOSTEST=$?"
    swiftlint lint ; echo "LINT=$?"               # repo ROOT
    swift run --package-path ios localization-gate --sources ios/App/Sources \
      --catalogue ios/App/Sources/Localizable.xcstrings ; echo "L10N=$?"   # from repo ROOT
    xcodegen generate && xcodebuild -project Tankbook.xcodeproj -scheme Tankbook \
      -destination 'platform=iOS Simulator,name=iPhone 17' build ; echo "APPBUILD=$?"

**Echo the exit code from the COMMAND, never through a pipe**; redirect to a file instead.
**Never `pgrep -f`/`pkill -f`.**

## Screenshots

**Required if you add a user-visible message, EN and RU, dark**, as
`design/screenshots/RV.65-*.png` / `-ru.png`, captured OUTSIDE a test run.
**Verify the two files differ** (`md5 -q a.png b.png`) before reporting them: RV.58 shipped an "RU"
screenshot that was byte-identical to its EN one because the `-AppleLanguages "(ru)"` launch did not
take, and the agent could not tell. Use `scripts/capture-screenshots.sh`'s own mechanism
(terminate, then launch with `-AppleLanguages "(ru)" -AppleLocale ru_RU`), and note that a `-`
prefixed launch argument can PERSIST across relaunches - reinstall between shots if a state flag
sticks. You have no image input: say so, and say what you could not check.

## Report back

- Exit codes (captured, not piped), unit counts before/after, UI suites run, mutation result.
- **Bytes sent per failed extract, before and after** - the number this row exists to move.
- How you decided a token was "unchanged".
- What the user now sees on a 401, in EN and RU, and confirmation Save still works.
- What you found on the `/blobs` replay path.
- Anything you noticed that is not RV.65 - named separately.

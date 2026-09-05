# RV.68 – import reports every non-HTTP error as "you need a connection"

Reported by the product owner 2026-09-05: *"I can't import a file, as it says it requires a
connection to a server. The connection exists."* **The premise is settled by the server log and the
mechanism is confirmed in code – confirm both, do not re-derive them.**

## Where you may write

Only inside `/Users/sbelyaev/repos/fuel-counter-ios` – **`ios/` and `docs/` only.**
**Do not run `git add` or `git commit`. Do not touch `docs/TASKS.md`.** Touch no `backend/` file.
**Never move, rename or delete a file you did not create.** `.claude/worktrees/rv48` belongs to
another session and is not your gate.

**Use the `iPhone 17` simulator.**

## What is established

**The device was online.** The server log shows the same device (`787c4f6f`, `1.0.0+643`) pulling,
pushing and running a 15.7 s `llm.extract` between 05:32 and 06:03 – all authenticated, all
successful.

**The request never reached the server.** There is **no** `/v1/import/formats` or
`/v1/import/parse` line anywhere in that log. So the client decided "offline" without asking.

**The mechanism.** `ios/Sources/TankbookCore/Import/ImportClient.swift:121-128`:

```swift
} catch is TankbookHTTPClientError {
    // Host-not-allowlisted / redirect loop: a real client bug or a
    // security violation, never an offline state.
    await director.report(.transportFailure)
    throw ImportClientError.client
} catch {
    await director.report(.transportFailure)
    throw ImportClientError.transportUnreachable      // <- CATCH-ALL
}
```

A decode failure, a cancellation, a timeout, a TLS or DNS error – all become
`transportUnreachable`, which `ImportFlowModel.swift:236-237` maps to `formatsState = .offline`
and `ImportSourceView.swift:109-110` renders as the offline card.

**Note what the existing code already gets right**: the `TankbookHTTPClientError` branch above is
separated deliberately, with a comment saying it is *"never an offline state"*. **The distinction
was understood; the line was drawn one case too narrow.** Your job is to widen it, not to invent a
new idea.

## Reproduce FIRST – this is a requirement, not a preference

**Identify which error actually occurs before changing the mapping.** A fix aimed at the wrong error
class will look right and change nothing.

**The leading suspect is cancellation, and there is precedent**: an earlier production log shows
`GET /v1/config/ -> 499` and `GET /v1/rates/pack -> 499`, the client abandoning requests at about
one second. A cancelled `URLSession` task throws `URLError.cancelled`, which lands in this
catch-all – and a SwiftUI `.task` cancelled by a re-render would produce exactly the reported
symptom. **Check whether the import screen's load is cancelled by a view update.** Say what you
found either way; "it was a decode failure" is an equally good answer if that is the truth.

## What to build

**1. Log the underlying error's type and code BEFORE mapping it.** This row exists partly because
nothing recorded which error occurred - disproving the message needed a server log. Hard rule 12:
an error type, a `URLError.Code` and a status are loggable; a payload, a URL query or a file's
contents are not. (`OB.2` is the general fix for the app's silence; this is the local one.)

**2. Narrow the mapping so only a genuine connectivity failure reports offline** –
`URLError.notConnectedToInternet`, `.networkConnectionLost`, `.cannotFindHost`, `.timedOut` and
their kin. **A cancellation is not a failure at all** and must not surface as an error state. **A
decode failure is a client/server contract bug**, and needs its own message with its own next step
(hard rule 7) - not "check your connection", which sends the user to fix something that is not
broken.

**3. Audit the three siblings that share this shape verbatim** and report on each:
`AccountClient.swift:147`, `FeedbackClient.swift:67`, `GatewayOutboxClient.swift:104`.
**Do not fix all four silently if they differ** - say which are the same defect, and fix only what
you can justify. If a sibling's catch-all is correct for its surface, say why.

**Do not remove the offline state.** Import is the ONE flow where offline is a legitimate answer -
hard rule 1's amendment makes `/import/parse` the named network exception, and an offline user
genuinely cannot import a foreign file. The defect is a FALSE offline, not the state existing.

**Any user-facing string** goes through the String Catalog, EN + RU, whole localised phrases, never
concatenation (hard rule 10).

## Read before writing

1. **`CLAUDE.md`** – hard rule 7 (every error names its next step - **and a WRONG next step is worse
   than none**), rule 1 and its import amendment, rule 12, rule 10, rule 14.
2. `docs/ERRORS.md` → the Import wizard rows (the offline row exists; add rows for the classes you
   split out). `docs/API.md` → `/import/formats`, `/import/parse`.
3. `ios/Sources/TankbookCore/Import/ImportClient.swift` (all of `send`, `decode`, `error(for:)`),
   `ios/App/Sources/Import/ImportFlowModel.swift` (`formatsState`, the catch at `:236`),
   `ImportSourceView.swift` (`offlineCard`), and the three sibling clients above.

## Tests

**iOS unit 1378 today; must not fall.** Name the UI suites you run; expect `ImportUITests`.

- **L1 per error class, over an injected transport - assert the STATE each maps to, not that an
  error was thrown:**
  - `URLError.notConnectedToInternet` -> offline
  - `URLError.cancelled` -> **not an error state at all**
  - a malformed/undecodable body -> a decode/contract error, **not** offline
  - a 500 -> the server-error path
- **L4 `ImportUITests`: with a healthy transport whose first attempt is cancelled, the wizard does
  NOT show the offline card.**
- L1: a genuinely offline transport still shows the offline card with its existing copy (the
  legitimate case must not regress).

**Vacuous-assertion traps, named:**
- Asserting that an error surfaced. One already does - the wrong one.
- Testing only `notConnectedToInternet`. That case works today and is the one that was never broken.
- Asserting the offline card renders. It renders too eagerly; that is the bug.
- Asserting a thrown error's type without asserting the UI state the user actually sees.

**Mutation-check and report it**: restore the bare catch-all and confirm the cancellation test goes
red. Restore byte-for-byte, confirm green.

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

**Only if you change or add user-facing copy** – then EN and RU, dark, as
`design/screenshots/RV.68-*.png` / `-ru.png`, captured OUTSIDE a test run.
**Verify the EN and RU files differ (`md5 -q a.png b.png`) before reporting them**: RV.58 shipped an
"RU" screenshot byte-identical to its EN one because the `-AppleLanguages "(ru)"` launch did not
take, and the agent could not tell. Use `scripts/capture-screenshots.sh`'s mechanism, and note a
`-` prefixed launch argument can PERSIST across relaunches - reinstall between shots if a state flag
sticks. You have no image input: say so.

## Report back

- Exit codes (captured, not piped), unit counts before/after, UI suites run, mutation result.
- **Which error class actually caused the report** - the reproduction, stated plainly. If you could
  not reproduce it, say so and say what you fixed anyway on the strength of the code reading.
- **The full mapping table you now implement**: error class -> user-visible state.
- What you log before mapping, and confirmation it carries no payload (hard rule 12).
- **A verdict on each of the three siblings** - same defect or not, and what you changed.
- Anything you noticed that is not RV.68 - named separately.

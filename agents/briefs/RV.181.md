# RV.181 - nothing is ever dispatched to a share destination

You are working in `/Users/sbelyaev/repos/fuel-counter-ios`. **Write only inside that repo.**
Write code first, explore second. Do not commit; the orchestrator commits after verifying.
**Never move, rename or delete a file you did not create** - assume you are not alone in this
checkout. **Agents never tick `docs/TASKS.md` and never commit.** An agent ticked its own row on
2026-09-10 and the orchestrator reverted it.

## The defect

Product owner, 2026-09-10: *"Sharing doesn't work. If I want to share a diagnostic log, photo
attached, I can see the share proposal, select a destination, but in the end, nothing is dispatched
to the destination source."*

**Every share in the app is affected.** `UIActivityViewController` is hosted as the **root of a
SwiftUI `.sheet`** through `ActivityView: UIViewControllerRepresentable`
(`ios/App/Sources/Shared/ActivityView.swift:16-22`):

```swift
func makeUIViewController(context: Context) -> UIActivityViewController {
    let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
    controller.completionWithItemsHandler = { _, completed, _, _ in completion?(completed) }
    return controller                     // ← returned AS the sheet's root
}
```

An activity controller must be **presented BY** a view controller. Hosted as a sheet root it is
presented by SwiftUI's hosting controller, so when the user picks a destination the chosen activity
has **no presenter for its own UI** - Mail's compose window, Messages, the Files browser - and the
hand-off dies silently. The sheet simply closes and nothing arrives.

The five call sites, all through that one seam:

| Surface | Site | Payload |
|---|---|---|
| Diagnostics bundle | `Settings/DiagnosticsPreviewView.swift:38` | a `String` |
| Receipt photo / PDF | `EditEntry/AttachmentViewerView.swift:135` | `UIImage`, or a temp-file `URL` |
| Account + per-car export | `Export/ExportFlow.swift:42` | a directory `URL` + CSV `URL`s |
| "Send us the file" (PJ.20) | `Import/ImportWizardView.swift:542` | a file `URL` + a message |

**`ExportFlow.swift:43` compounds it** with `.presentationDetents([.medium, .large])` applied to the
activity controller itself.

## Why nothing caught this, and what it means for your tests

`PJ.36` and `PJ.38` ship **committed screenshots of the share sheet open**, and their L4s assert it
appears. **The sheet appearing is the half that already works.** The orchestrator opened those
screenshots during this session and read them as evidence; they are not.

**So an assertion that the sheet is presented passes on today's broken code.** Your acceptance is
that an artefact **arrives**.

## This brief's reading is a hypothesis - confirm it before you change anything

The cause above is the orchestrator's diagnosis from reading the code, **not a runtime observation**.
Four of the orchestrator's diagnoses were wrong in one session and an agent caught every one.

**Reproduce it first**: run the app, open a share, choose *Save to Files*, and confirm nothing lands.
If sharing works for some payload types and not others - a `String` behaving differently from a
`URL`, say - **that changes the fix and you must report it**. If it works everywhere and the defect
is elsewhere, say so and stop.

## Why this row outranks the queue

*Export always free* is a launch commitment (`docs/VISION.md`), and `DELETE /account`'s copy points
the user at export as the way to keep their data (`site/delete-account.md`). Today **nothing leaves
the app**: not the diagnostics bundle the support flow depends on, not a receipt photo, not the CSV.
It is hard rule 8's promise failing in the export direction.

## What to build

**Present the controller instead of hosting it**, in the **one shared seam**. `ActivityView` is
already the single door - which is why this is one row and not five - so fix it there and let every
call site inherit the fix.

The shape: the representable owns a plain host `UIViewController` and presents the
`UIActivityViewController` from it, **guarded so it presents exactly once** (SwiftUI calls
`updateUIViewController` repeatedly; presenting twice throws, and re-presenting on every update is
its own defect). `ShareLink` is an acceptable alternative **only** where the payload is a single
item - it cannot carry the export's directory-plus-files - so if you use it anywhere, say where and
why the seam still exists for the rest.

**Drop `ExportFlow`'s `.presentationDetents`** - it applies a sheet's sizing to a controller that
now presents itself.

**Keep `completionWithItemsHandler` firing exactly once**, with `completed` true only when an
activity actually ran. `AttachmentViewerView.swift:138` and `:416` log shape-only outcomes off it
(`RV.17`); those log lines must keep meaning what they say.

## Explicitly out of scope

- What each surface *puts* in the share - the payloads are settled. Do not change what is shared.
- `PJ.20`'s consent step, `PJ.36`/`PJ.38`'s export building, `OB.4`'s diagnostics bundle contents.
- The import file picker.

## Docs to read before writing (in order)

1. `docs/ERRORS.md` -> the export and diagnostics rows - what each surface promises the user.
2. `docs/LOGGING.md` §5 - the diagnostics bundle and its shape-only rule; hard rule 12 means a share
   outcome logs **whether** and **what kind**, never the content or a destination app's identity.
3. `docs/VISION.md` -> export always free, and `docs/SECURITY.md` if a temp file's protection class
   matters to your fix.
4. `CLAUDE.md` hard rules 7, 8, 12.

Extend `docs/ERRORS.md` if the failure now surfaces to the user at all - **decide whether a share
that fails should say so**, and record the decision either way.

## Environment axes this crosses

**Device vs simulator matters here** - some activities exist only on a device, but *Save to Files*
and *Copy* work on the simulator and are enough to prove the hand-off. **Say which you used.**
**Locale**: no new copy expected; if you add a failure message it is EN + RU. **Screenshots**: only
if a user-visible surface changes - a working share looks identical to a broken one, so **a
screenshot is NOT evidence for this row**; say so rather than shipping one that proves nothing.

## If this adds a failure path, what makes it visible in production?

The current failure is **completely silent**, which is why it survived to a user report. Whatever
you build, make sure one device log can answer *"did a share reach an activity?"* - the existing
`completionWithItemsHandler` outcome is the natural place. Shape only: whether an activity ran, and
the payload **kind** (photo / pdf / csv / text). **Never** the destination app, the filename, or the
content (hard rule 12).

## Tests you must add

- **L4, and it FAILS TODAY**: a share **reaches a destination and the artefact exists afterwards**.
  *Save to Files* into a known directory, then assert the file is there. **Assert the RESULT, never
  that the sheet appeared** - the sheet appears on the broken code, which is exactly how this
  shipped.
- **L1**: `completionWithItemsHandler` fires **exactly once** per share, and `completed` is true only
  when an activity ran. Present twice in a row and assert one callback each - the guard against the
  present-on-every-update defect.
- **L4**: every surface goes through the fixed seam - diagnostics, photo, PDF, account export,
  per-car export, send-file. **Oracle**: `ActivityView` is the only construction site of
  `UIActivityViewController` in the app; a source-scan asserting that is cheap and stops the next
  call site forking its own.

Name each suite and report its observed, **non-zero** count. **Run app-target suites separately and
check the COUNT** - on 2026-09-10 a filter matched nothing three times and printed `TEST SUCCEEDED`
with exit 0 on **zero tests**; one suite was an `extension` in a differently-named file, so filter by
the **suite** name, not the file's.

## The mutation you must run - I am naming it, do not choose your own

**Restore the old shape: return the `UIActivityViewController` as the representable's root.** The
arrival test **must go red** - no file lands - while any "the sheet is presented" assertion stays
**green**. Then restore and re-run. Report both outputs verbatim.

That split is the whole point of the row: it demonstrates that the test which existed could never
have caught this, and the one you added can.

## Vacuous traps, named

- **Asserting the sheet is presented** - today's behaviour, and the reason this reached a user.
- Trusting `PJ.36`/`PJ.38`'s committed screenshots as evidence; they show the half that worked.
- Fixing one call site instead of the shared seam - or the seam while leaving
  `presentationDetents`.
- Presenting on every `updateUIViewController`, which throws or re-presents.
- Testing the hand-off in a unit test - `UIActivityViewController` cannot exercise it there.
- Shipping a screenshot as proof: a working share and a broken one look identical.

## Never stash, move or `git checkout` to get a "clean baseline"

Write the test, run it against the unmodified code, then make the change. **Do not** `git stash`,
`git checkout`, or move files out of the tree: an agent did that on 2026-09-08 and a bad `mv` loop
destroyed three of its own new files.

## Never `pgrep -f` for a build process

Your brief is part of your command line, so `pgrep -f "xcodebuild.*test"` matches **this agent**.
Use `pgrep -x xcodebuild`. **Never `pkill -f`.**

## Standing checks

Re-measure the baseline yourself and report what you observe. As left, `main` is **1863 tests / 221
suites**, **829** localization keys at 100% RU.

1. `cd ios && swift build` - exit 0.
2. `swiftlint lint` from the **repo ROOT** - exit 0. From the root, **not** `ios/`: the `excluded:`
   paths are root-relative and from `ios/` it exits 2 with ~5000 phantom errors.
3. `cd ios && swift test` - full, never subsetted; report the count.
4. **`xcodebuild ... build` for the app target** - `swift build` compiles only the SwiftPM package,
   and `ActivityView` lives in `ios/App/Sources`, invisible to it ([RV.174]).
5. `xcodegen generate`, then every UI suite you touched **by suite name**, with observed **non-zero**
   counts.
6. Localization gate - exit 0; report keys and RU percentage.
7. Release build if you touch a `#if DEBUG` seam. Say which applies.

Verify by **exit code** (`echo $?`), and report the codes you observed.

## Report back

Every check with the **exit code you observed** and the observed counts; whether each test was **run
or only written**; **the named mutation's red-then-green output, verbatim**; **how you reproduced the
defect before fixing it, and on device or simulator**; whether any payload type behaved differently
from the others; whether a failed share now tells the user anything and what you decided; and
**anything you found and did not fix**.

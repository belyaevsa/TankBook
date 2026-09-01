# PR.16b – the file-protection test cannot fail, on the only runtime CI has

## Where you may write

Only inside `/Users/sbelyaev/repos/fuel-counter-ios`:

- `ios/App/Sources/Persistence/AppStore.swift` (`applyFileProtection`, line ~71)
- `ios/App/Sources/Persistence/VehiclePhotoStore.swift` (line ~21)
- `ios/Sources/TankbookCore/` – `ConfigCache.swift:287`, `VehicleCatalogCache.swift:65`,
  `BlobStore.swift:55`, `ArchiveFileIO.swift:56` (the other appliers)
- `ios/App/Tests/FileProtectionTests.swift`, `ios/Tests/` for any core-side test
- `docs/SECURITY.md` – the authority; correct it if what it promises changes shape

A sibling lane (PJ.2b) is running and owns `ios/Sources/TankbookCore/Domain/ScannedSavePlan.swift`,
`ios/App/Sources/ConfirmManual/`, and `ios/Tests/TankbookCoreTests/ScannedSavePlanTests.swift` -
**do not touch those**. Do **NOT** touch `docs/TASKS.md`. **Never `git checkout`** to undo anything -
copy a backup back and verify with `md5`.

Write code first, explore second.

## Use this simulator

`iPhone 17 Pro`. The sibling uses `iPhone 17`. **Never** `pgrep -f`/`pkill -f` for a build - a brief
is part of the process command line and that pattern once killed a sibling agent 48 minutes in. Use
`pgrep -x xcodebuild`.

## The defect, and it is a test defect

PR.16 set the protection class the docs had promised for months. Its test asks the **filesystem**
what it stored:

```swift
let values = try url.resourceValues(forKeys: [.fileProtectionKey])   // FileProtectionTests:45
```

**The iOS Simulator does not emulate data protection.** That call reports
`completeUntilFirstUserAuthentication` as a **hard constant** no matter what is set - PR.16's agent
probed it four ways (`setAttributes` with `.none` and `.complete`, `createFile` attributes, host
xattrs, and a per-path cache) before concluding it. So the test passes **whether or not the code
sets anything**, on the only runtime CI has.

That is a green assertion measuring nothing - the same shape as P4.7's restore hash, where
stripping the payload left all 15 tests green, and the seven site checks that passed when inverted.
The agent surfaced it honestly instead of presenting green as proof; this row is the follow-through.

## What to build

Make the check **discriminating on a simulator**: inject the protection-applier as a seam and assert
it was **invoked with the promised class, per file** - rather than asking the filesystem what it
stored.

The appliers are these six, and they all call
`FileManager.setAttributes([.protectionKey: .completeUntilFirstUserAuthentication], ...)`:

```
AppStore.applyFileProtection        (the .sqlite/-wal/-shm triple)
VehiclePhotoStore                   (the attachments directory chokepoint)
BlobStore, ArchiveFileIO, ConfigCache, VehicleCatalogCache   (core)
```

Verify that list yourself - briefs here have carried wrong lists six times, and being right about it
is part of the job. A single shared seam that all six route through would be better than six
injection points, if you can do it without contorting the call sites; say which you chose and why.

**Keep the device-truth test too.** It is worthless on a simulator and correct on hardware, so it
should stay, with a comment saying exactly that - do not delete it because it cannot fail here.

## Named vacuous traps, and this row is made of them

- **A replacement that also cannot fail is worse than none**, because it looks like the gap is
  closed. The row exists because a passing test proved nothing.
- Asserting the applier was called **at all**, without asserting **which class** and **which file**.
  Calling it with `.none` must fail.
- A spy that the test itself installs and then asserts on, without the production path running -
  assert the real `makeRepository` / photo-store call routes through the seam.
- Testing only `AppStore`. The WAL and SHM are the ones people forget, and the attachment
  directories are half the promise.

## The mutation that MUST fail

Remove the `setAttributes` call from **one** applier and confirm your new test goes red, naming that
file. Then restore by copying a backup back and verifying `md5`. If it stays green, you have
rebuilt the defect.

## Checks

- `swift build --package-path ios` exit 0; `swiftlint lint` exit **0 from the repo root**.
  **`swift build` does not compile `ios/App`** - also `xcodebuild ... build` → `BUILD SUCCEEDED`.
- `swift test --package-path ios` - whole suite, never subsetted; it stood at **1122** (a sibling
  lane may add to it - report what you observe, a rise is not a failure).
- `xcodebuild ... -only-testing:TankbookTests test` on `iPhone 17 Pro` - the app-target bundle PR.16
  created. Report the observed count.

## Report back

The real list of appliers and where mine was wrong; whether you used one shared seam or several and
why; the exact assertion (quote it) and why it cannot pass when the class is wrong; what you did
with the device-truth test; observed counts and exit codes; the mutation result and the `md5` match.
Say whether you **ran** the tests or only wrote them. Do not commit.

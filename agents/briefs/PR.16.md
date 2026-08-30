# PR.16 – the file-protection class the docs promise is not actually set

## Where you may write

Only inside `/Users/sbelyaev/repos/fuel-counter-ios`:

- `ios/App/Sources/Persistence/AppStore.swift` (`makeRepository`, the database triple)
- the attachment writers: `VehiclePhotoStore`, `FileBackedBlobStore`, the invoice-page store
- `ios/App/Tests/` **or wherever the app-target test bundle lives** – find it; this test must run
  where the app's own file paths exist (L2), not in the SwiftPM core tests
- `docs/SECURITY.md`, `docs/PRACTICES.md` (the S2 pointer)

Do **NOT** touch `docs/TASKS.md`, `ios/App/Sources/ConfirmManual/`, or
`ios/App/UITests/ConfirmManualUITests.swift` – a sibling lane (PJ.17b) owns those.

Write code first, explore second.

## Use this simulator

`iPhone 17 Pro`. A sibling uses `iPhone 17`. **Never** `pgrep -f`/`pkill -f` for a build (a brief
is part of the process command line and that pattern once killed a sibling agent). Use
`pgrep -x xcodebuild`.

## The gap, already measured – start here

`docs/SECURITY.md:31` promises: *"Local database (`.sqlite` + WAL/SHM) ... `FileProtectionType
.completeUntilFirstUserAuthentication` on all three files"*, and line 52 says attachments inherit
the same class.

**Nothing in the code sets it.** Grep confirms only three peripheral caches do it -
`VehicleCatalogCache.swift:65`, `ArchiveFileIO.swift:56`, `ConfigCache.swift:287` - each via
`FileManager.setAttributes([.protectionKey: .completeUntilFirstUserAuthentication], ...)` plus
`isExcludedFromBackup`. The **database** and the **attachment directories** rely on the platform
default. A promise met by accident is not enforced, and hard rule 11 is what this row protects.

## What to build

1. Set the class **explicitly** on the database triple (`.sqlite`, `-wal`, `-shm`) after the
   database is opened, in `AppStore.makeRepository`. The WAL and SHM files do not exist until the
   database is opened, which is why it is *after*, not before.
2. Set it on every attachment directory: `VehiclePhotoStore`, `FileBackedBlobStore`, invoice pages.
3. **The promised test** (L2, app target): `resourceValues(forKeys: [.fileProtectionKey])` equals
   `.completeUntilFirstUserAuthentication` on all three DB files **and** on a written attachment.
4. `VehiclePhotoStore`'s backup comment is either **corrected** or `isExcludedFromBackup` is
   actually implemented – pick one and say which; a comment claiming behaviour the code lacks is
   the defect this repo keeps paying for.
5. Point `PRACTICES.md` S2 at the real test.

Follow the three existing call sites' shape rather than inventing a new helper, unless a shared
helper removes real duplication - then use it in all of them.

## Named vacuous traps

- A test that asserts the class on a file the **platform default already covers**, proving nothing
  about your change. Prove it discriminates: set a *different* class deliberately, watch the test
  fail, restore.
- Asserting only the `.sqlite` and not `-wal`/`-shm`. The WAL carries the same rows; that is why
  the doc names all three.
- Writing the test in the SwiftPM core target where the app's container paths do not exist.
- "Verified by reading the code" – this must be an executed assertion on a real file on disk.

## Checks

- `swift build --package-path ios` exit 0; `swiftlint lint` exit **0 from the repo root**.
  **`swift build` does not compile `ios/App`** – also run `xcodebuild ... build` and report
  `BUILD SUCCEEDED`. Keep files under **700 lines** (`file_length` is an error here).
- `swift test --package-path ios` – whole suite, never subsetted. It stood at **1094**; report the
  observed count.
- The new L2 test, run on `iPhone 17 Pro`, with its **observed count** (a filter matching nothing
  prints "0 tests ... passed" and exits 0).
- **Mutation**: set one of the three DB files to `.none` and confirm the test fails **naming that
  file**; restore by copying back a backup and verifying `md5` – **never** `git checkout`.

## Report back

Observed counts and exit codes for every command; which files you set the class on; whether you
corrected the comment or implemented `isExcludedFromBackup`; whether the mutation failed and what
it said; the `md5` match. Say whether you **ran** the tests or only wrote them. Do not commit.

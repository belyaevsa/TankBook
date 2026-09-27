---
name: debug-case
description: Fetch and diagnose a debug case the owner pasted by id (ten Crockford base32 characters in two groups of five, like 02412-PM1N2 or K7Q2M-9XDRA) - download it from Object Storage with yc, find the scan the owner means, read its record and pipeline trace, and name the stage that lost the reading. Use whenever the owner pastes a case / diagnostics id or says "look at diagnostic <id>".
---

# Debug case

A case is what the beta's About -> Experiments -> Send diagnostics uploaded: the app's redacted
log, the last few scan photos, and each scan's record and pipeline trace. It is user content
(hard rule 9's debug-cases amendment), so it goes to `~/.cache/tankbook/cases/<id>/`, **never the
repo**, and nothing from it is pasted into a commit, a task row or a brief beyond shape (ids,
counts, stage names).

## 1. Fetch

```
scripts/case-yc.sh <id>          # any spelling: 02412pm1n2 works
```

Reads `tankbook-blobs/<owner>/cases/<id>/*` with the owner's `yc` profile (folder
`b1gvsptqkf1ol3rl8ec0`). The owner (account or device id) is not in the case id, so the script
searches every owner prefix. `scripts/case.sh` (via the admin viewer) is the other route, but it
only works once AD.8 is deployed and `~/.config/tankbook/admin-read.env` exists. **Use yc.**

"Not in tankbook-blobs" has three causes. The API spools parts to its own disk and uploads them
after it responds, usually within seconds, so wait a minute and retry once. Otherwise the case
is past the 30-day purge, or the id is mistyped. **Try the fetch before telling the owner to
wait.** A case the owner thought was still uploading was already complete (2026-09-27).

## 2. Find the scan

`manifest.json` has `build` (the app's commit) and `scans`, as `[photo, record, trace]` triples.
Scans are numbered oldest-first, so **the owner's "the photo I attached" is usually the
highest-numbered scan**. Check that its `capturedAt` is close to `generatedAt`. Earlier scans can
come from older builds (`record.build`), so read each against its own build.

```
jq 'del(.ocrLines)' scan-N-record.json      # resolvedSource, detection path, extraction, crossCheck
jq -r '.ocrLines[] | "\(.confidence) \(.text)"' scan-N-record.json
sips -Z 1400 scan-N-photo.jpg --out <scratchpad>/sN.jpg   # then Read it - look at the photo yourself
```

Write down the truth from the photo (total, litres, unit price) before reading any stage. Then
check it closes: litres x price, rounded or floored to the cent, equals the total.

## 3. Walk the trace (pump photos)

`scan-N-trace.json` is `PumpTraceJSON`, the same shape `pump-read --trace-serve` and the
annotator's pipeline view show (`tools/pump-annotate`). Walk it in pipeline order, and the first
stage that is wrong is the finding:

```
T=scan-N-trace.json
jq -r .currency $T      # FIRST: the currency the reader was given - not the record's extraction.currency
jq '{chosen, budget, orientationScores, final}' $T                 # which rotation, what the law said
jq -r '.attempts[] | "--- \(.kind) rot=\(.rotationCW) law=\(.law.reason) committed=\(.law.committed)",
  (.reads[] | "\(.field) \(.reader) digits=\([.readings[]? | (if .dp then "\(.top[0].d)." else "\(.top[0].d)" end)] | join("")) minMargin=\([.readings[]?.margin] | min)")' $T
jq -c '.attempts[0].verdicts[] | {kept, reasons, cells, meanMargin}' $T   # why a row was dropped
```

| Stage | Wrong looks like |
|---|---|
| currency | `.currency` is not the currency on the display. The law's decimal conventions and its price band both key off it, so every read can be right and the law still abstains (`nothingClosed`, `priceOutOfBand`). It is the car's home currency, else the region's (`PumpReaderCurrency.choose`, docs/EXTRACTION.md -> "The currency the reader is given"). Case 02412-PM1N2: a RUB car at an Estonian pump |
| orientation | the wrong `rotationCW` wins `orientationScores` |
| detection | the truth's window is missing from `detectedRows`, or it has `passesSize:false` |
| verify | the window's verdict has `kept:false`, with `reasons` naming why |
| assign | the right digits sit under the wrong `field` (a board price read as `unitPrice`) |
| read | the top digits differ from the truth; a low `margin` marks the unsure cell |
| law | every field reads right, but `law.reason` abstains (`nothingClosed`, ...) |

If the reads are right and the law abstains, rebuild the law's input by hand (the
`closingTriples` arithmetic in `ios/Sources/TankbookCore/Extraction/PumpReader/PumpReadingLaw.swift`)
and find the candidate that was missing. Usually it is the wrong window as `unitPrice`, a
decimal placement, or a banned candidate.

## 4. Reproduce locally

Re-run the photo on the current tree and compare it with the phone's trace. A difference means
the device and the simulator disagree, which is a finding in itself:

```
(cd ios && swift build --product pump-read)
echo '{"currency":"<trace .currency>"}' | ios/.build/debug/pump-read ~/.cache/tankbook/cases/<id>/scan-N-photo.jpg \
  | jq -c '{appCommitted, appUnclosed, abstainReason, rowTexts}'
```

Read `appUnclosed` beside `appCommitted`. `appCommitted` is what the form gets, and since PU.100
that includes an unclosed top read, which reaches the form under a warning without being
committed. To replay the phone's own windows through the reader and the law instead of the
detector, pass them in the request:
`jq -c '{currency:"RUB", windows:[.attempts[0].reads[]|{field,quad}]}' scan-N-trace.json | ios/.build/debug/pump-read <photo>`.
Run it from the repo root, because the default model paths are relative (`ios/App/Resources/*.mlpackage`).
Pass the trace's currency to reproduce the phone. Pass the display's currency to see whether the
currency was the only thing wrong. If the phone's `build` differs from `HEAD`, say so. The
fix may already be in.

## 4b. Receipt scans

A receipt scan has no trace. Its record carries the phone's OCR lines, so replay those lines
through the parser on this tree:

```
cd ios && CASE_DIR=~/.cache/tankbook/cases/<id> swift test --filter CaseReceiptReplay
```

A case often holds several shots of one receipt taken seconds apart, and the shots that disagree
are the finding. Read which line Vision misread in the shot that went wrong (`ocrLines`,
confidence 1.0 does not mean right), then check whether the cross-check could have caught it. A
wrong field under `crossCheck notApplicable` reaches the form silently. That is F2, the worst
kind (case 6JFJ1-4JRYX, RV.311).

## 5. Report and file

Tell the owner: the truth, what each stage produced, the first stage that went wrong, and whether
the current tree still does it. A real miss becomes a `PU` row in `docs/TASKS.md` (journey `J4`),
named by stage and the case id. If the photo belongs in the corpus, ask first, then follow the
`corpus-intake` skill. A case is held-out evidence only after it is registered there.

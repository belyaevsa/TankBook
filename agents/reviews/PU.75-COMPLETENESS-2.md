# PU.75 completeness review, second pass (re-check of review 1's two items)

Run 2026-09-24 against the working tree on `main` (HEAD `37197a09`). Review 1
(`agents/reviews/PU.75-COMPLETENESS.md`) found every checklist item MET except two, now changed. This
pass verifies only those two; everything review 1 passed is left un-re-reviewed. Read-only
git/grep/read; the only write is this file.

## Item 1 - `docs/EXTRACTION.md` decision 10 PU.75 amendment (note A1): **MET**

The amendment is present, placed after the PU.63 amendment, and records the contract change exactly as
the note's A1 requires:

- `docs/EXTRACTION.md:1002-1010` - "**Decision 10, amended 2026-09-24 (PU.75): the fast path does not
  count text lines at all.**" sits directly after the PU.63 amendment at `:985`. It states the pass now
  runs only after the fast verdict abstains, that the slow path keeps the count and its ceiling, and
  that a fast-decided frame's `Detection.textLines` is `PumpDisplayCapture.textLinesNotMeasured`
  (`-1`), "carried into `capture.classify` (`docs/LOGGING.md`) and shown as 'not measured' by the
  annotator's pipeline and compare views."
- Against `PumpDisplayCapture.decideAt` (`PumpDisplayCapture.swift:199-239`): the fast verdict at
  `:207` calls `fastVerdict(rows: detected, textLines: textLinesNotMeasured)` and returns at `:214-215`
  before `let textLines = textLineCount(upright)` at `:218` - the text-line pass runs only on the slow
  branch, matching the amendment's "the pass now runs only after the fast verdict abstains". The
  sentinel is `textLinesNotMeasured = -1` (`:76`), and the doc comment at `:72-75` gives the note A1's
  reason for `-1` rather than `0` (a pump face can show no text line at all).
- Against the note's A1 (`agents/research/PU.75.md:328-334`): the `-1` sentinel, its `-1`-not-`0`
  rationale, and the requirement that the docs record it in the same change are all satisfied. The
  amendment also carries the measured movement the note and the row own (`appDecide` 78.5 -> 51 ms).

The stale PU.38 framing review 1 flagged (`:973-974`, `:981-982`) is now superseded by the PU.63 and
PU.75 amendments immediately following it; the PU.63 text at `:985` already carried the "ceiling
guards the slow path only" correction, and the PU.75 amendment closes the remaining "fast path still
ran the count" gap.

## Item 2 - the compare view and every other `textLines` consumer: **MET**

- `tools/pump-annotate/index.html:2150-2152` (compare view, `decisionHtml`): the ternary now branches
  on `d.textLines === -1` and renders `<span style="opacity:.6">text lines not measured – the fast
  path decided first</span>` instead of `test(d.textLines <= (L.maximumTextLines ?? 30), …)`. The
  `-1 <= 30` pass no longer occurs; the ceiling test runs only for a real count. This mirrors the
  trace view's fix at `tools/pump-annotate/pipeline.js:674`, which already branched on
  `d.textLines === -1`.
- Grep of the rest of `tools/` and `ios/Sources/PumpReadTool` for any other consumer of
  `Detection.textLines` that would mis-render or mis-compute `-1`:

  | Consumer | Verdict | Evidence |
  |---|---|---|
  | `tools/pump-annotate/pipeline.js:674` | tolerates `-1` | `d.textLines === -1 ? 'not measured – the fast path decided first' : …` |
  | `tools/pump-annotate/index.html:2150-2152` | tolerates `-1` | fixed (above) |
  | `ios/Sources/PumpReadTool/main.swift:342` | emitter only | writes `decision.textLines` into `reply.appDecision`, consumed by the compare view (fixed) |
  | `ios/Sources/PumpReadTool/main.swift:315` | not a consumer of `Detection.textLines` | `timings["textLines"] = timed("textLines") { textLineCount(upright) }` - a benchmark of the pass's cost, not a read of the field |
  | `ios/Sources/PumpReadTool/TraceServe.swift:103,:187` | emitter only | writes `attempt.textLines` / `detection.textLines` into trace JSON, consumed by the trace view (fixed) |

  No other site in `tools/` or `ios/Sources/PumpReadTool` renders or computes with `textLines`; the two
  JS renderers that do (pipeline.js trace view, index.html compare view) both branch on `-1`, and the
  three Swift sites are pass-through emitters (two) plus a timing benchmark that never reads the field.

## Verdict

**COMPLETE.** Both items review 1 flagged are fixed in place and match the note's A1 and the working
code: the decision-10 PU.75 amendment records the lazy pass and the `-1` sentinel, and both annotator
views render `-1` as "not measured" instead of a passing ceiling check, with no remaining consumer
that mis-renders or mis-computes `-1`.

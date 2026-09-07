# iOS Code Comment Review and Agent Rules

Review date: 2026-09-07

Scope:

- production Swift under `ios/Sources/TankbookCore` and `ios/App/Sources`;
- supporting unit and UI tests under `ios/Tests`, `ios/App/Tests`, and
  `ios/App/UITests`;
- the repository instructions in `CLAUDE.md` and the authoritative product
  documents referenced from comments.

The aim is not to remove comments broadly. It is to keep comments that help a
reader make a correct change and remove material that becomes false as the
repository evolves.

## Finding

The iOS code is heavily commented, and many comments contain valuable domain
reasoning. The main problem is that comments often act as a second copy of
`docs/TASKS.md`: they include task IDs, dates, old behavior, implementation
history, test results, and future plans. This makes current code read like an
annotated changelog and causes factual drift.

Static inventory:

| Area | Swift files | Lines | Comment lines | Comment density | Task-ID comment lines |
|---|---:|---:|---:|---:|---:|
| `ios/Sources/TankbookCore` | 210 | 32,831 | 9,666 | 29.4% | 456 |
| `ios/App/Sources` | 229 | 40,658 | 9,381 | 23.1% | 1,098 |
| Production total | 439 | 73,489 | 19,047 | 25.9% | 1,554 |
| Unit/app tests | 186 | 42,612 | 6,706 | 15.7% | 443 |
| UI tests | 59 | 14,140 | 3,387 | 24.0% | 313 |

In production code, 342 of 439 Swift files contain a task ID in at least one
comment. There are also 201 production comment lines with temporal language
such as “today,” “for now,” “later,” or “eventually.” There are no `TODO`,
`FIXME`, `HACK`, or `XXX` markers in the reviewed Swift paths, which is a good
property: the backlog is already centralized rather than scattered through
those conventional markers.

Comment volume is not itself a defect. The risk comes from what the comments
claim and how many places must change when one decision moves.

## Confirmed misleading examples

| Location | Comment claim | Current code or evidence | Required correction |
|---|---|---|---|
| `ios/Tests/TankbookCoreTests/CorpusCompressionTests.swift` | The header says the app's exact compression step is 1600 px at quality 0.7 and cites a 174/210 result. | `GatewayRendition` defaults to 1800 px at 0.9, and the test's current floor is 189/235. | Describe the test as exercising `GatewayRendition` defaults. Keep the measured floor beside `recordedReceipts`, not in a second header narrative. |
| `ios/Sources/TankbookCore/Extraction/Gateway/GatewayRendition.swift` | The file-level history says the shipped rendition scores 89/175. | The corpus now contains 235 asserted receipt cells. The comment is an old measurement even though the selected constants remain 1800/0.9. | Keep the reason that compression is corpus-gated. Move dated measurements to the corpus record or task history. |
| `ios/App/Sources/Settings/AppSync.swift` | `makeBlobFetcher` says a fetch failure leaves a shimmer and is “never an error.” | `AttachmentViewerView.load()` converts a failed fetch into `.unavailable(.failed)` and renders a failure card with a next step. | Describe only the fetcher's responsibility: verified download and cache. Let the caller's state documentation describe presentation. |
| `ios/App/Sources/Settings/AppSync.swift` | Debug fixtures are described as outcomes the app version can “never provoke from a real server,” including 426, 402, unknown 4xx, and 429. | Those are real server responses that the production state mapper handles. The fixture exists because a deterministic screenshot should not depend on producing them live. | Say the fixtures render server response states without a live request. |
| `ios/App/Sources/Navigation/TabRoots.swift` and `Routes.swift` | The inbox is described as holding late extraction work “plus later reminders.” | `AppInbox` stores only `GatewayInboxItem`; no reminder producer or reminder item type exists. | Remove the planned reminder claim. Keep future inbox work in `TASKS.md`. |
| `ios/App/Sources/EditEntry/AttachmentViewerView.swift` | The recognized-data overview lists only `ocrText` and `extractedTimestamp`. | The viewer now passes `attachment.extractionMeta`, and assigned fields are the primary recognized-data surface. | Describe the current stored assignment and raw evidence without the RV.17/RV.48 change history. |
| `ios/App/Sources/Config/AppConfigService.swift` | The App Store ID is “empty today” and remains so until an ID “lands.” | The present invariant is simply `compiledAppStoreID == ""`, which suppresses the button. The temporal wording becomes wrong as soon as the value changes. | Explain the empty-value behavior next to the constant; put release status in the release checklist. |
| Several localization and extension files | A file exists so another file remains below a specific lint line budget. | File size and lint configuration change independently of feature semantics. | Use a neutral responsibility-based file comment, or omit it when the filename already explains the split. |

These are examples rather than an exhaustive defect list. The density of task
markers makes a one-time manual cleanup insufficient; the repository needs a
rule that applies whenever an agent touches code.

## Comments worth keeping

The strongest comments explain facts that names and syntax cannot express:

- why a plain hybrid differs from a plug-in hybrid in `CaptureMode`;
- which receipt identifier shapes caused false numeric candidates in
  `ReceiptNoiseFilter`;
- why refresh-token callers share one in-flight task;
- why a sync cursor must not advance beyond an uncommitted concurrent write;
- why log values are classified before any sink sees them;
- why a DEBUG seam exists for a simulator limitation;
- why a migration or persisted field must remain compatible with older data.

Even these comments should state the present constraint. A short concrete
counterexample is useful. The task number, date, agent story, and old
implementation are usually not.

## Comments to remove or move

### Move to `docs/TASKS.md` or Git history

- task IDs used only to identify the change that introduced a symbol;
- dates on which behavior changed;
- “before this change,” “this shipped,” “the agent found,” and mutation-run
  narratives;
- old test counts, previous accuracy scores, and verification logs;
- rejected designs that are no longer plausible from the current code.

### Move to an authoritative design document

- product decisions shared by several features;
- complete endpoint, navigation, logging, retention, or localization rules;
- future release scope and features that do not exist yet;
- measurements that need a dated evidence record.

### Delete

- comments that translate the next line into English;
- headings whose only content is a task number;
- comments that repeat a property name, type name, or straightforward branch;
- stale statements preserved only because they once explained a bug;
- claims about line counts or file splits with no semantic effect.

### Keep beside code

- a surprising invariant or precondition;
- a platform or framework behavior that forces the implementation shape;
- concurrency, ordering, persistence, privacy, or ownership consequences;
- the reason for a non-obvious constant, with the value sourced from the
  constant itself;
- a compact example that prevents a likely but wrong simplification;
- a workaround's removal condition.

## Agent rules

These rules are also added to `CLAUDE.md` so they apply during implementation.

1. **Describe the current tree.** A reader should not need to know which task
   introduced the code. Use present tense and remove old-state narration.
2. **Explain why, not what.** Keep a comment when it identifies an invariant,
   consequence, ownership boundary, tradeoff, or external constraint that the
   code does not make obvious.
3. **Keep history out of code comments.** Do not add task IDs, dates, commit
   references, agent actions, test-run counts, before/after stories, or “done”
   evidence. Put them in `TASKS.md`, an ADR/spec, or Git.
4. **Do not announce future behavior.** Production comments describe features
   that exist. Planned producers, screens, routes, and migrations belong in
   the backlog.
5. **Do not duplicate mutable facts.** Reference the named constant or the
   authoritative document section instead of copying scores, file lengths,
   endpoint lists, timeouts, quotas, or version counts.
6. **Reserve contract words.** A comment using “always,” “never,” “only,” or
   “must” needs enforcement in code structure or a discriminating test. If the
   implementation merely intends the behavior, use narrower wording.
7. **Use doc comments for callers.** `///` explains public or internal API
   semantics, inputs, outputs, effects, isolation, and errors. Private fields
   and obvious helpers do not need Quick Help prose.
8. **Keep implementation comments local.** Place one explanation at the
   narrowest point where a future edit could violate it. Link the authoritative
   document rather than repeating the same rule at every call site.
9. **Document workarounds completely and briefly.** State the platform or
   dependency constraint, the consequence of removing the workaround, and the
   condition that makes removal safe.
10. **Update comments as part of behavior changes.** For every touched Swift
    file, read all comments in that file and update or delete claims invalidated
    by the change.
11. **Search for stale vocabulary.** After renaming a symbol, changing a
    constant, altering a state, or replacing a route, search comments for the
    old identifier and literal value.
12. **Tie promises to evidence.** When a comment makes a behavioral promise,
    identify the test that fails if it becomes false. If the promise is not
    worth testing and not required by a public contract, remove or narrow it.

## Decision test for each comment

An agent reviewing a comment should apply these questions in order:

1. Is it true for the current implementation?
2. Does it tell the reader something the names, types, and control flow do not?
3. Is this file the narrowest authoritative place for that fact?
4. Is the fact stable enough to remain true after ordinary feature work?
5. If it promises behavior, what code or test enforces it?

Keep the comment only when the answers support keeping it. Rewrite it when the
idea matters but the wording carries history or duplicated facts. Move it when
the authority is a specification or backlog. Delete it when the code is equally
clear without it.

## Review procedure for agents

For every code change:

1. Read all comments in each modified file before editing.
2. Mark each affected comment as keep, rewrite, move, or delete.
3. Make code and comment changes together.
4. Search the modified paths for old symbol names, old literal values, task
   markers, dates, and future-tense promises.
5. Review new comments once without looking at the task description. They must
   make sense from the repository's current state alone.
6. Run the normal compile and lint gates required by `CLAUDE.md`.

A useful review command for production Swift is:

```sh
rg -n '//.*(PR\.|RV\.|PJ\.|OB\.|P[0-9]+\.|20[0-9]{2}-|\btoday\b|\bfor now\b|\blater\b|\beventually\b)' \
  ios/Sources/TankbookCore ios/App/Sources --glob '*.swift'
```

This is a candidate list, not an automatic deletion list. Dates in parsing
fixtures and words such as “current” in date algorithms may describe real data
rather than history.

## Cleanup plan

### Priority 0 — correct false claims

1. Fix the confirmed examples above.
2. Search production comments for symbols and literal values changed by the
   last several completed tasks.
3. Review every comment containing “never,” “always,” “only,” or “must” against
   current tests and code.

### Priority 1 — remove changelog prose from production

1. Start with high-density files such as `AppSync.swift`, `TabRoots.swift`,
   `ManualFillUpView.swift`, `ImportFlowModel+Wizard.swift`, and `L10n.swift`.
2. Remove task IDs and dates while retaining current invariants and necessary
   framework constraints.
3. Replace task-number `MARK` headings with feature or responsibility names.

### Priority 2 — simplify tests

1. Let descriptive test names carry the ordinary scenario.
2. Keep comments that explain fixture provenance, a subtle discriminating
   assertion, a platform limitation, or why a tempting assertion is vacuous.
3. Move mutation history and past failure narratives to the task record.

### Priority 3 — prevent recurrence

1. Add a changed-lines comment-hygiene check that rejects new task IDs, dated
   history, and future-plan language in production Swift comments.
2. Use a baseline or changed-lines gate so existing debt does not block all
   work; lower the baseline during cleanup.
3. Include “comments describe current truth” in code-review and agent
   completion checks.

## Brief quality summary

- **Valuable:** domain invariants, privacy boundaries, concurrency reasoning,
  fixture-backed parser exceptions, and platform workaround explanations.
- **Overused:** doc comments on private state and straightforward view wiring.
- **Misplaced:** 1,554 production comment lines carrying task IDs and many
  comments carrying task results or implementation history.
- **Stale-risk:** 201 temporal production comment lines and 144 lines with
  mutable numeric claims.
- **Confirmed false or incomplete:** compression settings/results, blob-fetch
  failure presentation, live-server response reachability, reminder inbox
  support, and recognized attachment fields.

Overall quality: **the reasoning is often excellent, but it is stored too close
to changing implementation details and mixed with project history. The target
state is fewer comments, each describing one present, enforced reason.**

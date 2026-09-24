# PU.74 research note - the law refuses a close whose digit counts are impossible for their roles

*RESEARCH-TO-CODE run for `PU.74` (`docs/TASKS.md`). Product owner, 2026-09-23: "review the
published research to apply it into the code, instead of coming up with our own solution."
Corpus populations counted at HEAD `2f7fd5dd` (the tree moved under this run from `b42f38da`;
the implementer re-counts with the same filter, §6). Evidence rule: every claim cites a paper
section/equation, a `file:line`, or a measured number; inference is labelled. Precisions carry
Wilson 95% intervals per PU.68's instrument (`agents/research/PU.68.md` §2.1, BCD eq. 4).*

**Headline finding, stated first because it changes the row's premise.** The row's citation
(Hokamp & Liu, Grid Beam Search) is real and correctly cited, but its constraints are *lexical*
(phrases that must appear) and cannot express "this field has k digits with the decimal at
position d". The published method that maps onto "a field's digit count and decimal convention
are known per role and currency" is **finite-state / grammar-constrained decoding**: build the
automaton for the field's format language and let the beam emit only strings it accepts
(Willard & Louf 2023 §2.2-§3; classically, WFST composition of a lattice with a format acceptor,
Mohri-Pereira-Riley 2002). GBS contributes one transferable device, the coverage-indexed grid
that stops score-pruning from deleting hypotheses that still owe a constraint (§2.1, §4 A1).
Measured at HEAD, the decimal half of the constraint is **already** the law's candidate-placement
set for EUR and RUB (`PumpReadingTypes.swift:215-222`; KZT's total row is wider than measured,
:223-225); what leaks is the **`default` branch**
(`PumpReadingTypes.swift:231-233`), which hands GBP/AUD/BYN and every unlisted currency a
permissive `[2,3]` placement set. That leak, not a missing algorithm, is what admits pump-137's
tenfold shrink: at HEAD pump-137 has **three** exactly-closing triples and the measured GBP row
collapses them to the single true one (§5, §6). pump-106, by contrast, has **one** closing triple
at HEAD under the shipped RUB conventions; its tenfold-shrink exposure is the convention-table
widening mutation PU.14 names, so for pump-106 the constraint is a regression audit, not a verdict
change (§5.2).

## 1. The citations, checked

| Citation as the row gives it | Fetch result | Verdict |
|---|---|---|
| Hokamp, C., Liu, Q. (2017). *Lexically Constrained Decoding for Sequence Generation Using Grid Beam Search.* ACL 2017, arXiv:1704.07138 | arXiv abs page: title exact, authors Chris Hokamp and Qun Liu (ADAPT Centre, Dublin City University), v1 24 Apr 2017, v2 2 May 2017, cs.CL, comment "Accepted as a long paper at ACL 2017". Full text read from the ACL Anthology PDF (P17-1141): *Proceedings of the 55th Annual Meeting of the ACL*, Vancouver, 30 Jul - 4 Aug 2017, pages 1535-1546, DOI 10.18653/v1/P17-1141. | **Correct as cited.** Full text read; method in §2 below. |
| (row: "also search" - constrained beam search for OCR) Post, M., Vilar, D. *Fast Lexically Constrained Decoding with Dynamic Beam Allocation for Neural Machine Translation.* | arXiv API title search: arXiv:1804.06609, v1 18 Apr 2018, v2 9 Nov 2018; comment "Proceedings of NAACL-HLT 2018 (Long Papers)". Abstract read; full text not read in this run. | **Exists and is the efficiency successor to GBS** (O(1) in constraints vs GBS's linear). Cite as Post & Vilar 2018, NAACL-HLT, arXiv:1804.06609. Abstract-only here. |
| (row: "regular-expression constraints in constrained beam search") Willard, B. T., Louf, R. *Efficient Guided Generation for Large Language Models.* | arXiv API + abs page: arXiv:2307.09702, v1 19 Jul 2023, v4 19 Aug 2023, cs.CL/cs.LG. No venue in the record (it is the Outlines library paper); venue unverified. Full text read from arXiv HTML v4 (§2.2, §3, Algorithms 2-4, Example 1). | **This is the method that maps** (§2.2, §3). Cite as Willard & Louf 2023, arXiv:2307.09702; no peer-reviewed venue claimed. |
| (row: "field-level validation in document understanding") Geng, S., Josifoski, M., Peyrard, M., West, R. *Grammar-Constrained Decoding for Structured NLP Tasks without Finetuning.* | arXiv API title search: arXiv:2305.13971, v1 23 May 2023, v6 18 Jan 2024; comment "Accepted at EMNLP 2023 Main Conference". Abstract read; full text not read. Checked: the id `2305.14837`, which review prose in this repo's neighbourhood sometimes pairs with this title, resolves to an unrelated paper (*Using the Uniqueness of Global Identifiers to Determine the Provenance of Python Software Source Code*) - verify by title, never by recall (PU.68 §1 caution). | Exists; the CFG generalisation and the **input-dependent grammar** device (the grammar depends on the input, i.e. per-currency tables are input-dependent grammars in their sense). Cite as Geng et al. 2023, EMNLP, arXiv:2305.13971. |
| (caution found while searching) Park, K., Wang, J., Berg-Kirkpatrick, T., Polikarpova, N., D'Antoni, L. *Grammar-Aligned Decoding.* | arXiv API title search: arXiv:2405.21047, v1 31 May 2024; comment "Accepted to NeurIPS 2024". Abstract read. | Exists. Relevant as a **published warning**, not a method to adopt: hard grammar masking distorts the model's distribution (§2.3, A6). |
| (classical antecedent for format-constrained recognition) Mohri, M., Pereira, F., Riley, M. *Weighted finite-state transducers in speech recognition.* | CrossRef `10.1006/csla.2001.0184`: *Computer Speech & Language* 16(1): 69-88, Jan 2002, authors verified. Full text not read. | Exists; the classical statement of intersecting a recognition lattice with a grammar acceptor. Cited as the antecedent of §2.2's device, method not read here. |
| (domain antecedent, searched and NOT verified) bank-check courtesy-amount recognition with a format constraint and an independent verifying field (Hull-Srihari-Cohen 1990 and family) | CrossRef title and author searches returned the family (e.g. Anisimov et al., *Bank check reading: Recognizing the courtesy amount*, LNCS 1995, pp 161-172, DOI 10.1007/3-540-60697-1_99, authors and venue verified) but **not** the 1990 TPAMI paper under its remembered title, and no full text was read. | **Not cited as a method.** Named only as the historical home of "numeric field with known format, verified against a second field"; the implementable method in this note comes from the verified family above. Do not quote a 1990 TPAMI reference from this note. |

Searches that returned nothing usable, recorded so the implementer does not repeat them: arXiv
`all:"constrained decoding" AND all:"receipt"`, `all:"grammar" AND all:"constrained" AND
all:"OCR"`, `all:"cross-field" AND all:"validation"`, and odometer/automatic-meter-reading
queries return no peer-reviewed constrained-decoding-for-numeric-OCR paper; the OCR numeric-field
literature lives in ICDAR/DAS proceedings that this run could not fetch full texts for. The
mapped method is therefore the generation-side FSM/grammar-constrained family, which is
model-agnostic by construction (Willard & Louf §2.2 needs only a next-symbol distribution), so it
applies to a per-cell digit classifier as well as to an LLM.

## 2. The methods as published

### 2.1 Grid Beam Search - Hokamp & Liu 2017, §2-§4

Objective (§2, eq. 1-2): `ŷ = argmax_{y∈{y^[T]}} p_θ(y|x)` with `p_θ(y|x) = ∏_{t=0}^{T}
p_θ(y_t | x; {y_0...y_{t-1}})`; greedy per-step argmax is eq. 3. A lexical constraint is a
sub-sequence `c_i = {c_{i0}...c_{ij}}` that must appear somewhere in `ŷ` (§1).

Algorithm (§3, Algorithm 1, lines 1-29): beams are a grid `Grid[t][c]` where `t` is the timestep
and `c` the number of **constraint tokens** covered so far; `numC` is the total tokens in all
constraints. Each beam is filled three ways (lines 8-21): **open** hypotheses in `Grid[t-1][c]`
*generate* from the model; **open** hypotheses in `Grid[t-1][c-1]` *start* a constraint;
**closed** hypotheses in `Grid[t-1][c-1]` *continue* the constraint they are inside. Line 22:
`Grid[t][c] = k-argmax_{h ∈ n ∪ s ∪ g} model.score(h)`. Lines 25-27: only the top level
`Grid[:][numC]` yields finished hypotheses (those that then emit EOS), and the best finished
hypothesis is returned. §3.1: a coverage vector forbids using a constraint twice; *filters*
express ordering/gap conditions between constraints. §3.3: naive cost `O(k t c)` against plain
beam's `O(k t)`; columns `c` are independent so a timestep parallelises; keep `k` small.
§3.4 eq. 4: `g_t = k-argmax_i o_ti` over the softmax; *start*/*continue* index the softmax at the
constraint's token instead of argmaxing. **Parameters the authors chose: `beamSize = 10` for all
experiments (§3.4); subword vocabulary 80000 shared; NMT hyperparameters in Appendix A.**

Data and results (§4): interactive Pick-Revise post-editing simulated on WMT newstest2013 (EN-DE),
newstest2014 (EN-FR) and an Autodesk Post-Editing test corpus (EN-PT), constraints of up to three
tokens per cycle, four cycles: +20 BLEU across cycles (Table 1). Domain adaptation by PMI-extracted
terminology (eq. 5-6, nPMI ≥ 0.9, both phrases ≥ 5 occurrences, n-grams length 2-5) on the Autodesk
corpus (~100,000 train sentences, 1000 test): GBS over baseline/random/beginning = EN-DE
27.99/25.18/26.44 vs baseline 26.17; EN-FR 35.05 vs 32.45; EN-PT 29.15 vs 15.41 (Table 2).

**What GBS's constraints can and cannot say.** A constraint is a token sub-sequence that must
appear. There is no primitive for "the output has exactly k symbols" or "symbol j is a decimal
point": length and format are not lexical constraints. The transferable device is structural -
organising the beam by a *constraint-coverage counter* so that a hypothesis which still owes a
constraint is never pruned on score alone (Figure 3: beams on the top level are the only ones that
may finish) - plus the open/closed split that makes a partially-emitted constraint deterministic.

### 2.2 Finite-state (regex/grammar) constrained decoding - Willard & Louf 2023, §2.2-§3

§2.2: from the next-token logits `α = LM(S̃_t, θ)`, an un-normalised constrained distribution is
`α̃ = m(S̃_t) ⊙ α`, `s̃_{t+1} ~ Categorical(α̃)`, where `m: P(V) -> {0,1}^N` is a boolean mask over
the vocabulary; the paper lists as example mask families "digit samples", "strings that match the
regular expression `[a-zA-Z]`", and "strings that parse according to a specified grammar".
Algorithm 2 (line 5-6) is sampling with that mask constructed at each step. §3 Definition 1: the
guiding regex is a 5-tuple automaton `(Q, Σ, δ, q0, F)`; the FSM state is tracked across steps so
matching never restarts. **Example 1 and Figure 1 use the regex `([0-9]*)?\.?[0-9]*` - a numeric
format grammar - and show the mask refusing "A" at state 0 and narrowing completions after ".2"
(state 3) to {"42","1"}.** Algorithm 3 (`find_sub_sequences`) walks the automaton from every viable
start state for each vocabulary string; Algorithm 4 builds the index `σ: Q -> P(V)` mapping each
FSM state to the vocabulary strings accepted from it, so the per-step mask is a lookup, not an
`O(N)` scan. Cost claim: "adds little overhead to the token sequence generation process"
(abstract), the index being built once per grammar.

### 2.3 The published caution - Park et al. 2024 (abstract)

Greedy grammar masking makes outputs grammatical but **not** distributed as the model conditioned
on the grammar; their ASAp corrects the sampling distribution. For a *decoder that must return
posteriors* (ours does: `Candidate.logPosterior`, `PumpReadingLaw.swift:320`) this is the warning
that a hard mask silently re-weights the beam; §4 A6 names our answer.

### 2.4 Which method maps onto "digit count and decimal convention known per role and currency"

**The FSM/regex-constrained device (§2.2), not GBS.** Per (role, currency) the legal strings form a
finite language - for EUR unitPrice, four digit cells with the point after the first
(`d d . d d d` as a cell pattern) - i.e. a tiny regular language whose automaton is a chain; the
beam over a window's ranked digits is then intersected with that chain, exactly Willard & Louf's
mask specialised to a 10-symbol alphabet and a per-cell step. Geng et al.'s *input-dependent
grammar* is the same statement at CFG level: the grammar is a function of the input, here of the
currency the display is in. GBS's grid is retained for one thing only: the **cross-field
arithmetic** is a constraint satisfied only when all three fields are decoded, so the triple tier
must not let per-field score-pruning delete the operand strings a closing triple needs - that is
GBS's coverage-counter argument applied to a non-lexical constraint, and it is already how
`stringsPerField` (= 12, `PumpReadingLaw.swift:24`) is sized (§4 A1).

## 3. Mapping onto this code (line numbers as read at HEAD `2f7fd5dd`)

*Line numbers are from the working tree as read at the start of this run. A concurrent uncommitted
edit to `PumpReadingLaw.swift` landed while the note was being written; if a line has moved, resolve
by symbol name - every seam below is named, not only numbered.*

1. **The constraint lands in `PumpReadingLaw.candidates`** (`PumpReadingLaw.swift:353-387`),
   specifically the placement loop `for d in decimals` at :376-384. Inputs today: a
   `PumpLocatedWindow` (cells with ranked digits, `PumpReadingTypes.swift:114-122`) and a
   `decimals: [Int]` list. Inputs after: the same window plus the **measured per-(currency, role)
    placement set** and the **measured per-(currency, role) cell-count set** (§5.2 tables). Output
    type unchanged (`[Candidate]`, :318-323); a candidate whose placement is outside the measured
    set is not emitted, and a window whose `cells.count` is outside the measured cell-count set for
    its (currency, role) yields `[]` and is named by `diagnoseNothingClosed` (:171-183) through a new
    `.cellCountImpossible`-style reason added to `PumpAbstentionReason` (`PumpReadingTypes.swift:23-54`).
 2. **What it replaces: the hand-written switch `PumpDisplayConventions.forCurrency`**
    (`PumpReadingTypes.swift:213-235`). The EUR and RUB rows (:215-222) already equal the measured
    placement sets (§5.2 table 2); KZT's total row is wider than measured; the KGS row (:226-230)
    has **no reviewed fixture in the corpus at HEAD** and is unmeasured; and the **`default` row
    (:231-233) is the defect**: it gives every unlisted currency `volumeDecimals [2,3]`,
    `priceDecimals [2,3]`, which is what admits pump-137/145/308-316's shrunk and grown triples
    (§5.3). The row retires no numeric constant; it retires the *default's width* by replacing the
    switch with the measured table plus an explicit "currency not measured" refusal instead of a
    permissive fallback (adaptation A3).
3. **What it does not touch.** `beamWidth` (:22), `stringsPerField` (:24), `closingSlack` (:27),
   `ambiguityWindow` (:33), `readWindow` (:38), `decimalMarkPenalty` (:43), `maxSubstitutions`
   (:343), `closingTriples` (:392-430), `commit` (:434-466) and the pair tier (:276-308) keep their
   semantics. `decimalMarkPenalty` is demoted in role, not deleted: with a hard placement set the
   seen-mark penalty only breaks ties *inside* the legal set (a 4-cell EUR price can only be d=3,
   so the penalty has nothing to decide there); it stays load-bearing exactly where the measured
   set has two members (RUB price {1,2}, RUB total {1,2}, KZT price {0,1}), which is inference from
   the table, not a measured claim.
4. **The digit-count half is a window-level audit, not a candidate filter.** Candidate digit count
   is always `window.cells.count` (the loop at :356-367 emits one digit per cell), so a digit-count
   constraint cannot prune inside a window; it can only refuse the window. That is precisely PU.14
   §2.1's "free audit of both assignment and slicing" (a 3- or 5-cell EUR price window is a
   mis-slice), and it is where the row's title lives: a close assembled from a mis-sliced window
   is refused before the arithmetic sees it.
 5. **The truncated-total tier must survive the constraint.** Four reviewed fixtures' totals
    reproduce no placement of the asserted value because the display rounded or truncated its own
    product (pump-065 `3765,7` vs 3765.65; pump-073 `2249.9` vs 2249.92; pump-158 `9900,0` vs
    9899.95; pump-003 `20886.3` vs 20886.25; §5.2 table 3); they commit through `closingTriples`'
    truncated branch (:415-426) as derived totals. A placement constraint applied to the *derived*
    total would refuse them; the constraint applies to read placements only (adaptation A4).

## 4. Adaptations, named (the fence)

Each is a departure from the published method; anything the implementer adds beyond this list
needs the product owner's OK.

- **A1. GBS's grid is kept as an argument, not as code.** Paper: beams indexed by constraint
  coverage, `O(k t c)`, top level only finishes (§3, Algorithm 1). We: no grid. Our constraint is
  position-local (a per-cell placement chain), so coverage is known in advance and the chain
  intersection is exact; the only global constraint is the arithmetic, which `closingTriples`
  already evaluates over the kept strings. Why: a grid over three fields' coverage would multiply
  the beam by the product of the three chains for no pruning gain; `stringsPerField = 12`
  (:24) is the existing, measured device that keeps a closing triple's operands alive.
- **A2. Masking becomes set membership over placements, not over a vocabulary.** Paper: boolean
  mask `m` over `V`, index `σ: Q -> P(V)` (Willard & Louf §2.2, Algorithms 3-4). We: the alphabet is
  10 digits plus "point position", one step per cell, and the automaton is a chain of length
  `cells.count`; the mask is `d ∈ measuredSet(role, currency)`, a table lookup. Why: no `O(N)`
  vocabulary scan exists to optimise away; building Willard & Louf's index would be code with no
  work behind it. The FSM framing is kept in the comment and the test names, so the departure is
  visible.
- **A3. An unmeasured currency refuses instead of falling back to a permissive default.** Paper:
  none (the papers assume the grammar is given). We: `forCurrency`'s `default` row
  (`PumpReadingTypes.swift:231-233`) is replaced by "measured row or abstain with a named reason".
   Why: the default's width is the measured cause of 14 of 253 reviewed fixtures carrying false
   closes (§5.3); a silent permissive fallback is the defect pattern this row exists to close
   (`docs/DEFECT-PATTERNS.md`, silently-reachable fallback). Currencies with fewer than three
   reviewed fixtures (BGN, BRL, ISK, NOK, PHP, PLN, SEK, TMT, §5.2 table 2) keep an explicit narrow
   row seeded from what is measured, labelled as n=1 in the table's comment.
- **A4. The constraint binds read placements only; derived totals are exempt.** Paper: the grammar
   governs the whole output. We: `closingTriples`' truncated branch (:415-426) and `pairOutcome`'s
   implied price (:291) are outside the placement set. Why: four reviewed totals are display
   roundings or truncations of the product (§5.2 table 3); constraining them would refuse the
   truth.
- **A5. The placement set is measured as "the d that reproduces the asserted value from the
   displayed digits", not as the asserted string's decimal count.** Paper: n/a. We: §5.2 table 2's
   construction, over every reviewed non-zero window whose digits reproduce the asserted value,
   `csvDisagrees` included (the flag governs scoring, not the display's own placement fact). Why:
   taking decimals from `expected.csv`'s text ("244.0" -> 1) wrongly refuses pump-006, whose display
   shows the integer tenge price `244` (3 cells, d=0); this trap was found by measurement in this
   run and is the reason the table is built the way it is.
- **A6. Posteriors are not re-normalised under the mask.** Park et al. 2024 show hard masking
  distorts the conditioned distribution and give ASAp to fix sampling. We: keep
  `Candidate.logPosterior` as the unmasked joint log-posterior of the cells and treat the
  constraint as a support restriction, reporting the distortion as out of scope. Why: our verdicts
  are argmax-plus-uniqueness over closing triples, not samples; the law's nat windows
  (:33, :38, :43) are tuned to the unmasked scale (PU.72 owns calibration). If a future row samples
  from the beam, ASAp is the published fix and needs its own note.
- **A7. Seven-segment cells, not tokens.** Paper: subword tokens of an NMT/LLM vocabulary. We: one
  step per sliced cell, alphabet = ten digits, the point position carried as `decimalPoint`
  (`PumpReadingTypes.swift:82`). Why: the classifier emits per-cell digit posteriors
  (`PumpCellReading.ranked`), so the "sequence" is fixed-length and cell-aligned; no Core ML,
  Vision, Accelerate, Metal or C/C++ target is needed - the constraint is a table lookup in
  existing Swift, iOS 18.0 / iPhone 12 constraints are not engaged.
- **A8. Cell-count sets are unions of observed counts, never modal sets.** Paper: n/a. We: the
   digit-count audit refuses a window only when its cell count is outside the union observed for
   that (currency, role) at the build commit. Why: a modal-pair audit would wrongly refuse **96
   reviewed windows** across the seven (currency, role) groups with n ≥ 3 (§5.2 table 3): EUR
   liters 15, EUR total 27, EUR unitPrice 1, GBP total 1, KZT total 2, RUB liters 16, RUB total 30,
   RUB unitPrice 4 - real small fills, zero-padded heads, 1-decimal RN prices and idle displays;
   the union refuses nothing today and still catches a mis-slice that produces an unobserved count.
- **A9. Zero displays are excluded from the convention fit.** `0.00` reproduces at every d, so
  idle windows would widen every set to {0..6}. The law already abstains on all-zero liters before
  candidates matter (`PumpReadingLaw.swift:81`); the fit excludes asserted value 0 and the audit
  never sees an idle window's verdict.
- **A10. The cell-count audit runs once per window in `resolve`, not inside `candidates`
  (orchestrator's build-time amendment, 2026-09-24, after completeness reviews 2 and 3).** Note:
  §3 places the count constraint in `candidates`, an impossible window yielding `[]`. Built: the
  audit runs in `PumpReadingLaw.resolve` (triple tier) and `resolveWithoutPrice` (pair tier), after
  the structural guards and before `closingTriples`; the placement mask stays in `candidates`. Why:
  a cell count is a property of the window, identical for every candidate string the beam yields
  from it, so Willard & Louf's per-step mask degenerates here to one check per window; performed
  inside `candidates` it would empty the set and surface as `.cellUnknown`, losing the named
  `.cellCountImpossible` the row asks for. The refused set is identical either way - no triple is
  built from a refused window in either placement - and `PumpDisplayConventionsCorpusTests`'s close
  sweep replicates the law with the audit in this position (0 of 224 true closes refused).

## 5. What the papers measured, and what we expect on our corpus

### 5.1 Population, counted at HEAD `2f7fd5dd`

Filter = the harness's (`PumpReaderTestSupport.swift:83-88`: `isHeldout` = split `heldout` AND
`reviewed`; `isReviewedTrain` = split `train` AND `reviewed`; a fixture absent from `split.csv` is
train), plus non-blank `expected.csv` and not `csvDisagrees` for scored cells, exactly as PU.68 §6:

- `Spike/ReceiptSpike/fixtures/pump/windows.json`: 328 entries; **reviewed stills 327** = train 255
  + heldout 68 + heldout2 4 (heldout2 is the owner's second frozen draw, `c86755d6`, not swept here).
- **Scored numeric cells: heldout 183, reviewed-train 679.** 183 equals
  `PumpPhotoGate.readerNumericTotal` (`ios/Sources/TankbookCore/Config/PumpPhotoGate.swift:95`),
  the cross-check that the filter is the harness's. (PU.68 counted 250/668 at `310e7660` and
  244/670 at its build; the 2026-09-23 intake moved both.)
- Reviewed stills carrying all three transaction texts: 280 (heldout 59, train 217, heldout2 4).
- The close-enumeration sweep below runs on **253** reviewed heldout+train fixtures with all three
  texts and a parseable expected triple (the 280 minus heldout2's 4 and 23 with a blank or
  unparseable asserted field).

### 5.2 Measured digit-count and placement facts (the re-count PU.14 §2 demands)

Table 1 - displayed cell counts per (currency, role), reviewed stills, non-empty windows
(`windows.json` `text`, digits counted; `measure3.py` in this run's scratch):

| currency, role | displayed digit counts (n) | PU.14 §2.1 claim, re-counted |
|---|---|---|
| EUR unitPrice | 4 (x140), 2 (x1: pump-306 idle twin `0.0`) - n=141 | "exactly 4 digits in 63/63" becomes **140/141 = 0.9929, Wilson 95% [0.9609, 0.9987]**; the single exception is an idle twin display, not a price |
| EUR liters | 6 (x83, zero-padded Gilbarco), 4 (x81), 3 (x15) - n=179 | "3, 4 or 6" holds; 3-cell includes idle `0.00` and small fills (pump-014 `3.92`, pump-063 `7.17`) |
| EUR total | 6 (x83), 4 (x70), 5 (x18), 3 (x8), 0 (x1: pump-263 `closed`) - n=180 | "3-6" holds plus one non-numeric window |
| RUB unitPrice | 4 (x96), 5 (x11), 3 (x4: the 1-decimal RN heads `68,3`, `71,3`, `36,7`) - n=111 | wider than EUR; a modal audit would refuse the 1-decimal heads |
| RUB total | 6 (x61), 5 (x38), 7 (x9, zero-padded), 4 (x3), 3 (x1) - n=112 | zero-padding and 1-decimal truncation both present |
| GBP unitPrice | 4 (x10) - n=10 | asserted 4d/3dp in 10/10, but displayed separator sits at 1dp (`182.8`): the seen mark is not the truth here |

Table 2 - measured placement set per (currency, role): the set of `d` with
`int(display digits)/10^d` equal to the asserted value, over reviewed non-zero windows that are
not `csvDisagrees` (`measure6.py`; per-member counts are in its output and move with every intake,
so the table carries sets only):

| currency | liters | unitPrice | total | vs `forCurrency` today |
|---|---|---|---|---|
| EUR | {2} | {3} | {2} | equals :215-217 |
| RUB | {2} | {1,2} | {1,2} | equals :218-222 in effect (the 1-decimal totals are read there via the truncated tier; making them a read placement is this table's only RUB change) |
| KZT | {2} | {0,1} | {0} | :223-225 is wider on total (`[0,2]`) |
| GBP | {2} | {3} | {2} | **falls to `default` `[2,3]/[2,3]/[2]` - too wide** |
| AUD | {2} | {3} | {2} | **falls to `default` - too wide** |
| BYN | {2} | {2} | {2} | **falls to `default` - too wide** |
| n=1 rows (BGN, BRL, ISK, NOK, PHP, PLN, SEK, TMT) | as measured | as measured | as measured | all fall to `default` |

Fit exclusions, named because each is a refusal trap: idle-zero windows reproduce at every `d`
and are out (A9); `csvDisagrees` windows are out, so pump-190's 1-decimal KZT total and pump-200's
3-cell-shifted RUB liters (`990,00` asserted 99.00, a lit leading segment) do not widen the sets -
both are unscored anyway.

Table 3 - what a wrongly-built constraint would refuse, i.e. the refusal traps, counted at HEAD:

| trap | population | members (representative) |
|---|---|---|
| Displays whose total reproduces no placement (derived tier must stay exempt, A4) | 4 reviewed windows | pump-065 `3765,7`/3765.65, pump-073 `2249.9`/2249.92, pump-158 `9900,0`/9899.95, pump-003 `20886.3`/20886.25 |
| Windows whose displayed digits disagree with the asserted value at every placement (digit-level, not placement; already unscored) | 3 reviewed windows | pump-031 `0032,58`/32.50, pump-015 `1.884`/1.889, pump-313 `167,5`/1.689 |
| Non-modal displayed cell counts a modal-pair audit would refuse (A8) | 96 reviewed windows | EUR liters 15 (pump-014 `3.92`, idle `0.00` x6), EUR total 27 (pump-001 `125.22`, pump-275 `103.37`), EUR unitPrice 1 (pump-306 `0.0`), GBP total 1 (pump-308 `5.00`), KZT total 2 (pump-006 `10980`, pump-190 `7200,7`), RUB liters 16 (pump-108 `0032.49`, pump-200 `990,00`), RUB total 30 (pump-009 `02038,00`, pump-191 `500,0`), RUB unitPrice 4 (pump-044 `68,3`) |
| Placements read off the asserted string's decimals instead of the reproducing `d` (A5) | 1 scored fixture | pump-006 KZT price `244` = 244.0 at d=0, refused by a "1 decimal" reading of `244.0` |

### 5.3 Expected effect of the constraint, enumerated at HEAD

Replica of `candidates` + `closingTriples` (oracle digits = the annotated texts, `closingSlack`
0.011, truncated branch as at :415-426) over the 253 swept fixtures, current conventions vs the
measured table (`measure4.py`, `measure5.py`):

- True triple closes today: **241/253 = 0.9526, Wilson 95% [0.9189, 0.9727]**; the 12 that do not
  are `csvDisagrees`-shaped displays and mis-annotated cells the scored tiers already exclude.
- Under the measured placement set the true triple closes for **253/253** (by construction of A5),
  i.e. **wrong refusals 0/253, one-sided 95% upper bound 0.0106**. The named wrong-refusal traps
  (table 3) are: pump-006 if placements are read off the asserted string's decimals (A5); pump-065,
  pump-073, pump-158 and pump-003 if the constraint binds derived totals (A4); idle-zero windows if
  zeros enter the fit (A9); and the 96 non-modal-count windows of table 3 if the count audit uses a
  modal set (A8).
- **Fixtures whose false closes the constraint removes (3 closes today -> 1, true survives): 14 of
  253 = 0.0553, Wilson 95% [0.0332, 0.0907]** - pump-137, pump-145, pump-173, pump-180, pump-185,
  pump-190, pump-217, pump-308, pump-309, pump-310, pump-311, pump-312, pump-314, pump-316. Each
  is a GBP/AUD/KZT fixture where `default` (or KZT's wide total set) admits a tenfold-shrunk and a
  tenfold-grown triple beside the true one; e.g. pump-137 closes (5.23, 18.28, 95.60),
  (52.30, 1.828, 95.60) and (52.30, 18.28, 956.0) today and only the middle one under the measured
  GBP row. pump-137 and pump-190 are in PU.68's in-sample wrong-commit list, so 2 of the 6
  currently-wrong train commits sit inside the disambiguated set.
- **pump-106 has exactly one closing triple at HEAD** under the shipped RUB conventions
  (51.00, 70.31, 3585.8 via the truncated branch): the row's "consistent tenfold shrink commits"
  is **not reproducible at HEAD on oracle digits**. Its exposure is PU.14 §6 row 1's mutation
  (swap or widen the liters/total convention tables and pump-108/106 flip to the 10x-shrunk
  triple), so for pump-106 the constraint's job is to make the narrow table an enforced, measured
  fact with a red test, not to change today's verdict. Labelled: this revises the row's premise;
  the row text should keep pump-106 as the audit catch and pump-137 as the live catch.

### 5.4 What the papers measured vs what we measure

GBS measured BLEU on WMT newstest2013/2014 and a ~100k-sentence Autodesk corpus (§4); Willard &
Louf measured generation overhead and structure-guarantee on LLM benchmarks (abstract); neither
measured anything at our scale or domain. Our measurement is the close-enumeration above plus the
shipped ratchets: oracle ratchet 763 commits at 0.9987 with fragility 0.050 is the regression bar
(row text), heldout app path 45/45, annotated tier 112/112 (`gateMirror`,
`PumpReaderPipelineTests.swift:28,187`), reviewed train 124/117 in-sample (`PUMP_CERTIFY=1`), all
scored at `CorpusScorer.tolerance = 0.005` (`CorpusABScorer.swift:175`).

**Falsifiers, named in advance.**
- **F1 (wrong refusal).** Any implementation of the constraint under which a swept fixture's true
  triple stops closing: the sweep must print 0/253; a non-zero count names the fixture and the
  adaptation (A3-A5, A8, A9) that was violated.
- **F2 (no effect).** If after the change pump-137 still commits a shrunk triple on the train
  in-sample run, or the 14-fixture disambiguation list still enumerates >1 closing triple, the
  measured table is not actually wired into `candidates` (mutation: revert `forCurrency` to the
  `default` row for GBP - the disambiguation test must go red).
- **F3 (over-refusal on the ratchets).** heldout committed below 45, `gateMirror` below 112, or
  fragility above 0.10: the constraint refused a live close; the row's exit gate (oracle ratchet
  loses no commits) is broken.
- **F4 (count audit mis-slices the truth).** If the cell-count audit refuses any of the 96
  non-modal-count windows of table 3 on a scored fixture, the audit is modal, not union (A8).
- **F5 (derived totals).** If pump-065, pump-073, pump-158 or pump-003 loses its derived total, the
  constraint was applied to the truncated tier (A4).

## 6. Cost

- **Latency.** The constraint is two table lookups per window (placement set, cell-count set)
  inside `candidates`, which already runs a ≤12-string beam per field; no new loop over the corpus
  and no model call. Expected device cost: nanoseconds per window, unmeasurable against the
  read's 112-164 ms Release Mac figure (PU.75's number); **no Release latency number is owed by
  this row**, and if the implementer measures one it must be Release, per the standing rule.
- **Bundle.** The measured tables replace the `forCurrency` switch: of the same order (a few dozen
  integers per currency row); net TankbookCore change well under 1 KB. No new dependency, no C/C++
  target, no Core ML/Vision/Accelerate/Metal surface.
- **New code to maintain.** Roughly 60-100 lines: the measured-table literal plus its generation
  comment, the two membership checks in `candidates`, one new `PumpAbstentionReason` case, and the
  sweep test that re-enumerates closes at each corpus intake (the 253-fixture sweep is ~80 lines of
  test-support Python-or-Swift mirroring `measure5.py`). The table is corpus-derived, so every
  intake that adds a currency or a head shape is a table update - that recurring cost is the price
  of retiring the permissive default, and `scripts/`-side regeneration (as `measure6.py` does here)
  is the intended workflow, labelled as such.

## 7. Scratch artefacts

The measurement scripts of this run live outside the repo (scratch dir): `measure.py` (per-role
count/decimal distributions), `measure2.py`/`measure3.py` (population cross-check, outlier
naming), `measure4.py` (per-fixture close enumeration for the named catches), `measure5.py`
(the 253-fixture current-vs-constrained sweep), `measure6.py` (the measured placement table),
plus the fetched GBS PDF (`gbs.pdf`, ACL P17-1141) and Willard & Louf HTML (`wl.html`). They are
evidence, not deliverables; the implementer re-derives the tables in the test bundle.

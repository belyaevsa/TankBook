# RV.58: pump displays score 20% against a 95% gate. What is the right algorithm?

**Research and design only. You write exactly one file. You change no code.**

## Where you may write

Only this path, inside the worktree you are started in:

    diagnostics/RV.58-pump-qwen.md

**Run no `git` command.** Do not run `swift build`, `swift test`, `xcodebuild` or `swiftlint` -
another agent is implementing on this machine and Vision tests serialise badly. Do not touch
`docs/TASKS.md`, `agents/briefs/`, any `expected.csv`, or any fixture image.

**Never `pgrep -f`** - your brief is your command line, so it matches you. Use `pgrep -x`.

## The problem

The app can read a photo of the **pump display** instead of the paper receipt. The receipt path now
scores 180/220 cells (82%) after a day of work. The pump path scores **53/261 (20%)**, and the
feature ships **off** behind a gate that requires **95%** (`PumpPhotoGate`, `docs/TASKS.md` P2.7 -
"the gate IS the check"). It has been off since it was written.

**The question: what is the right algorithm to read a pump display, and is 95% reachable at all?**

An honest "no, and here is what the product should do instead" is a valid and valuable answer. So
is "yes, and here is the pipeline". What is not valuable is a plan that raises the corpus number by
guessing: on a pump, a wrong volume is a wrong fill-up in the user's history forever, and
`CLAUDE.md` hard rule 13 makes an abstention the correct output whenever the display does not
settle it.

## Why this is NOT the receipt problem

Three independent analyses of the receipt corpus concluded that the recognition layer was not the
bottleneck there - every glyph was already read at confidence 1.00 and the losses were all in the
parser. **The pump corpus is the opposite case, and the dump shows it immediately.** From
`diagnostics/pump-ocr-dump.txt`, `pump-001`:

    [1.00] SUMMA
    [1.00] 12522          <- the truth is 125.22 EUR
    [1.00] LIITRIT
    [1.00] 67.00          <- this one survived
    [1.00] 1869 HIND/1L   <- the truth is 1.869 EUR/L

Vision is a **text** recogniser pointed at a **seven-segment LCD**. The decimal point is a small
dot on a segment display and is frequently not in the recognised text at all - per field, not per
image, so one number on a display can keep its separator while its neighbour loses it. On
`pump-003` (Kazakhstan) **all three** are lost: `208863`, `8525`, `2450` for `20886.25`, `85.25`
and `245.0` - and note each needs a *different* divisor.

## Your evidence

**1. The photographs themselves.** 64 fixtures in `Spike/ReceiptSpike/fixtures/pump/`. If you can
read images, **open them** - that is the point of this brief, and no text dump substitutes for
looking. Fifteen worth your time, with ground truth (`liters, unitPrice, total`):

| file | truth | why it is here |
|---|---|---|
| `pump-001.heic` | 67.00, 1.869, 125.22 | decimal lost on two of three fields; matched to `receipts/receipt-001.heic` |
| `pump-003-kz-95-kzt.jpg` | 85.25, 245.0, 20886.25 | every separator lost, each needing a different scale |
| `pump-004-kz-95-kzt-tokheim.jpg` | 12.38, 243.0, 3008.00 | Tokheim LCD, and the pump TRUNCATES its own total to whole tenge |
| `pump-005-dresser-wayne-four-prices-ru.png` | 87.92, 52.56, 4621.08 | four grade prices, the correct one is LAST; only arithmetic picks it |
| `pump-006-kz-adast-92-kzt.png` | 45.00, 244.0, 10980.00 | three numeric formats on one display; the price is CLIPPED by the bezel |
| `pump-008-topaz-video-overlay-92-ru.png` | 20.00, 54.90, 1098.00 | the display is a VIDEO screen; numbers over cartoon footage, shown twice |
| `pump-009-gilbarco-zero-padded-ru.png` | 40.00, 50.95, 2038.00 | zero-padded (`02038,00`) with comma decimals |
| `pump-010-scheidt-preset-amount-ru.png` | 13.17, 75.95, 1000.00 | preset fill: 13.17 x 75.95 = 1000.26, so the arithmetic legitimately does NOT close |
| `pump-025-wayne-neste-ee-glare-obscured-total.jpg` | 22.91, 1.789, 40.99 | sun glare destroys the total's last digit |
| `pump-034-dresser-wayne-circlek-tallinn-ee-db0-pair.jpg` | 87.29, (none), 160.53 | the charged price is on NO board on the display |
| `pump-052-wayne-circlek-ee-glare-total-lost.jpg` | 34.64, -, - | litres readable, total gone: the ordinary sunlit outcome |
| `pump-053-wayne-circlek-ee-pump1-glare-total-digit.jpg` | 38.88, -, - | same, one digit |
| `pump-057-gilbarco-circlek-sikupilli-pump5-db0-pair.jpg` | 55.80, 1.799, 100.38 | matched to `receipts/receipt-046…`, so the paper is independent ground truth |
| `pump-058-gilbarco-circlek-ee-dirty-lcd-1969.jpg` | 20.02, 1.969, 39.42 | road dirt: the lowest-contrast readable display in the corpus |
| `pump-063-wayne-circlek-ee-insect-on-price-display.jpg` | 7.17, 1.834, 13.15 | a dead insect covers a digit of the price board |

**2. `diagnostics/pump-ocr-dump.txt`** - the raw Vision output for all 64, with confidences.

**3. `Spike/ReceiptSpike/fixtures/pump/README.md`** - long, and the single most valuable document
here: it records what each fixture proved, including findings that will save you from proposing
something already falsified. Read it before you write anything.

**4. `Spike/ReceiptSpike/fixtures/pump/expected.csv`** - ground truth. An empty cell means the
photograph genuinely does not carry that value; those are **not** misses to be fixed.

## What is already known, so you do not rediscover it

- **The cross-check** (`liters x unitPrice ~= total`) **solves discrete-candidate choice** - it
  picks the right price out of four on `pump-005` - **catches a misread digit**, and is **blind to
  a swapped pair** (`a x b == b x a`) and **blind to lost separators** (it is scale-invariant).
- **The grade badges belong to every nozzle, not to the fill.** A pump parser must not attempt fuel
  kind at all; `expected.csv` leaves it empty except where a paired receipt settles it.
- **Position on the price board carries no information** - the same five grades appear in different
  orders on four pumps at one forecourt. Only the badge beside a price identifies it.
- **A display holds the previous customer's transaction** until the next fill starts, so the numbers
  on a display are not necessarily the user's own.
- **Confidence is not correctness**: `pump-004` misreads at confidence 1.00.
- **Separator style is a property of the pump, not the country** - one forecourt, both conventions.
- `docs/EXTRACTION.md` records that image preparation and region re-recognition were judged
  no-ops **for receipts** and explicitly parked for the pump class, where "the deficit is measured".
  Nobody has tried them here.

## Directions worth evaluating - and say what you think of each, with evidence

1. **Decimal reconstruction as a solved arithmetic problem.** Three numbers with unknown decimal
   placement and a known relation `a x b = c`. Searching plausible powers of ten for each operand is
   a small, deterministic search with a checkable answer. What does it resolve, where is it
   ambiguous, and what does it do on `pump-010`, where the arithmetic legitimately does not close?
2. **Find the LCD, then read it.** Detect the display panel (bright rectangle, high local contrast,
   fixed aspect) and recognise only that region, upscaled - rather than handing Vision a whole
   forecourt. Does the dump show evidence that the surroundings are what confuse it?
3. **Seven-segment recognition proper**, instead of a text recogniser. What would it cost, what
   would it need, and is it justified for one screen in the app?
4. **The paired-receipt trick as a product answer**: five fixtures have a matching paper receipt.
   If the pump is unreadable, is the right product move to read the paper instead?
5. **Refuse honestly.** Given hard rule 15 (typing is a peer path, never a fallback) and rule 13,
   what does the *user* actually lose if this mode stays off, and what would make it worth shipping?
6. **Anything else the photographs suggest.** You are the first analyst to look at them.

## The answer

`diagnostics/RV.58-pump-qwen.md`, as a **ranked list**, each entry with: what it is; which
layer it acts on; expected accuracy gain **counted per fixture** against the 64; implementation cost
including runtime on an iPhone 12 (the floor device); wrong-answer risk and what abstains instead;
and whether it generalises beyond these 64 photographs.

Then three short sections:

- **"Is 95% reachable?"** - a number and an argument. If the answer is no, say what the ceiling is
  and what the product should do with a mode that cannot pass its own gate.
- **"What I would not do."**
- **"What I actually looked at"** - and be exact about whether you opened the photographs or worked
  from the dump. Working from the dump is acceptable; claiming otherwise is not.

## Report back

The file path, your top three, your answer on 95%, and what you actually read or viewed.

# SITE-ANIMATION-REVIEW — which animated elements are worth adding to tankbook.live

Read-only review. One report. The question: **which animations earn their place on this site, and which do not** — defended to an engineer who pays for them and to a user who did not ask for them.

---

## 1. What exists today

The honest finding is that **the site animates almost nothing**, and what it has is already done right.

| What | Where | Reduced motion? |
|---|---|---|
| Native smooth scrolling for anchor/`#id` links | `site/assets/css/base.css:16` (`html { scroll-behavior: smooth; }`) | Yes — `base.css:117` sets `scroll-behavior: auto` inside the reduce block |
| A global reduce-motion kill switch | `site/assets/css/base.css:115-126` | n/a — it *is* the switch: `* { animation: none !important; transition: none !important; }` |

There is **no `transition`, no `animation`, no `@keyframes`, and no `transform`/`opacity` animation anywhere** in the three CSS files (grep over `site/assets/css/*.css` returns only the two `base.css` hits above plus unrelated `text-transform: uppercase` in `layout.css:173` and `sections.css:39,132`). There is **no JavaScript file in the site at all** (`find site -name '*.js'` is empty; the only `<script>` is the Yandex Metrika loader in `site/layouts/_partials/head/analytics.html:7-15`, gated on `site.Params.metrikaId` and `hugo.IsProduction`). The inline SVG diagrams under `site/assets/diagrams/pump-reading/*.svg` are static: no `<animate>`/`<animateTransform>`/SMIL, markers and boxes use `var(--…)` tokens only.

Two consequences worth stating before the recommendations:

1. **The reduce-motion floor is already stronger than it needs to be.** `base.css:123-124` kills *all* `animation` and `transition` with `!important` the moment the user asks for reduced motion. Any CSS animation we add is therefore reduced-motion-safe *by construction*, with no per-feature code. This is not something to build; it is something to protect when writing new rules (do not add a `transition`/`animation` outside CSS, or the switch will not catch it — see §4).
2. **The final visual state must equal the static state.** Because the switch can arrive, and because the site is progressively enhanced, every animation must be a *reveal* whose resting state is what the page already shows. Nothing on this site may animate into a state that a no-JS, reduced-motion, or older-browser user never reaches.

---

## 2. Recommendations, ranked

Seven, ranked by how well each answers a real product question. "It looks modern" is deliberately absent.

### R1. The cross-check lock — rule draws in, tick lands. (Top.)

- **Where:** `site/layouts/_partials/sections/crosscheck.html:22-26` — the `.check-rule` row, its two `.check-rule__bar` spans and the `tick-circle` icon partial; optionally the `.check-total` line at `crosscheck.html:27`.
- **What moves / how long / trigger:** On scroll-into-view (~40% of the card), the left bar scales in from its outer end and the right bar from its outer end, meeting at the tick; the tick fades/scales in; the total settles. ~600 ms total, one-shot, never loops. A beat later, the amber underline on `.amber-underline` (`crosscheck.html:30`, `sections.css:343-346`) draws once left-to-right.
- **Why it earns its place:** This is the one product idea on the page that is *literally a motion in the app*. `docs/DESIGN.md` → Motion lists "the cross-check lock: the rule draws in from both ends toward the tick" as one of the three orchestrated moments the product already owns. Animating it on the site is not decoration; it is showing the customer the signature trust gesture — "litres × price = total, and you can watch it close" — which `docs/SITE.md:54` names as the thing incumbents cannot copy quickly. It also cannot over-promise: it is a *check*, the opposite of "automatic".
- **Build:** CSS-only `@keyframes` (two `scaleX` transforms with `transform-origin: left/right`, one `opacity`/`scale` for the tick), triggered either by `animation-timeline: view()` (progressive enhancement — if unsupported, the resting state shows, which is already correct) or by a ~400-byte `IntersectionObserver` script that adds `.is-inview` to `#check`. Default (no JS / reduced motion / old browser): bars full width, tick visible — exactly today's page.
- **Risks:** Low. Amber is used for the *attention* underline only, one pulse, never looping (hard rule 5). No text moves, so EN/RU and the 390 px phone are unaffected. No layout shift: the bars are already reserved space. The one discipline: the tick must *not* look like a checkmark stamping "correct" onto a scan — it lands on the arithmetic, which is what the copy says it checks.
- **Effort:** S.

### R2. Pump-reading pipeline flow — nine steps light up in order.

- **Where:** `/pump-reading/`, the `pipeline` diagram (`site/content/pump-reading.md:18`, SVG at `site/assets/diagrams/pump-reading/pipeline.en.svg` / `.ru.svg`).
- **What:** As the diagram scrolls into view, highlight each step box in sequence 1→9, drawing its connector arrow as it goes, and let step 8 ("the law of reading") and step 9 ("nothing offered → rotate") keep the `taillight` / dashed emphasis they already have (`pipeline.en.svg:45,56`). One-shot, ~1.4 s, or driven by scroll position so the reader controls the pace.
- **Why:** The article's job is to explain that reading a pump is *not* a single "AI snap". A static diagram shows nine boxes; the motion shows **there are decisions, checks, and a gate you can fail**. That is the anti-"magic" framing the copy rule (`docs/SITE.md:34-38`) demands. It answers "how does it read a pump?" by showing the *work*, which a still cannot.
- **Build:** Inline SVG is already `safeHTML`-inlined (`site/layouts/shortcodes/diagram.html:9`), so SMIL `<animate>` or CSS classes on the `<g>` elements work without touching the content file. Prefer CSS (`transition` on `fill`/`stroke` + a `stroke-dashoffset` draw for the arrows) with an IO trigger; SMIL is a fallback but is frozen and awkward to pair with the reduce-motion switch.
- **Risks:** The highest over-promise risk on the list — a *flowing* pipeline must read as "steps" and never as "instant read". Keep the emphasis on step 8 (the check) and step 9 (the fallback), not on a triumphant "→ Confirm" flash. Both languages: the `.ru.svg` files exist and the timing is identical, but the longer Russian box text must not be clipped by any drawn overlay — animate stroke/fill, never geometry.
- **Effort:** M.

### R3. Two doors, revealed in perfect unison.

- **Where:** `site/layouts/_partials/sections/doors.html:8-23`, the two `.door-card` elements.
- **What:** Both cards rise/fade in *together*, identical curve, identical 400 ms, when the section enters the viewport. No stagger, no accent difference.
- **Why:** Hard rule 15 is the product's spine and `docs/SITE.md:112-114` calls this "the section most likely to be diluted". The only animation that does not violate it is one that makes the **equality** visible: two doors, one beat. A stagger — even 100 ms — makes the first card primary and the second its fallback, which is exactly the bug the shared class structure (`doors.html:1-2`) exists to prevent.
- **Build:** One shared class, one keyframe, both cards. CSS-only, IO-triggered, resting state = visible. ~400 bytes if scripted.
- **Risks:** The point of this recommendation is as much a *warning* as a feature. If a future edit introduces a stagger or a per-door accent, it is a hard-rule-15 bug, not a style choice. Low value on its own — include it only if the section is to animate at all; the default is "no animation, both doors already equal".
- **Effort:** S.

### R4. Digit roll on the checked total.

- **Where:** `.check-total` at `crosscheck.html:27` (`= 71.02 €`, `sections.css:315-321`).
- **What:** A short vertical odometer roll (the app's "digit roll", `docs/DESIGN.md` → Motion #1) on the total as the section arrives — the whole number translates up a fraction of its height with a clipped mask, ~250 ms, spring-eased, then stops.
- **Why:** The brand's number language is DIN-with-a-roll; reusing it on the site says "these are real, checked figures" in the product's own voice. It is the cheapest way to make the arithmetic feel *observed* rather than printed.
- **Risks:** Numbers must stay `tabular-nums` (hard rule 6) throughout — a rolling digit must not jitter column width. Do **not** count the number up from zero: a count-up implies a live measurement; `71.02` is an illustrative fill-up figure, and counting to it is fake-data motion. A plain translate-in is honest; a counter is not.
- **Effort:** S (translate + clip) to M (per-digit markup for a true per-column roll).

### R5. The CTC merge — blanks fall away.

- **Where:** `ctc` diagram (`pump-reading.md:58`, `site/assets/diagrams/pump-reading/ctc.en.svg`).
- **What:** The "best symbol at each step" row (`ctc.en.svg:6-9`, the `0 0 – 0 0 – 1 4 4 , …`) resolves downward into the merged `0014,00` box (`ctc.en.svg:13`): the blank `–` cells fade out while the surviving digits slide together, once, ~700 ms.
- **Why:** This is the single most counterintuitive sentence in the article — "several network paths can spell the same row, and their evidence is combined." A still shows the input and the output; the motion shows the *merging*, which is the whole point. And it is honest: blanks dropping out reads as "uncertainty resolving", not "the app knew instantly".
- **Risks:** Same over-promise boundary as R2. The `–` is genuinely a blank, so fading it is truthful, but the animation must end at exactly the printed `0014,00` — never round-trip or loop, or it looks like a loading spinner for a reading that already happened. Russian box text is longer; animate opacity/position, not the `<text>` glyphs.
- **Effort:** M.

### R6. Cross-check's negative half — the amber underline.

- **Where:** `.check-warn` row and `.amber-underline` (`crosscheck.html:28-31`, `sections.css:328-346`).
- **What:** After the tick lands (R1), the amber underline under "amber underline" draws once, left→right, ~300 ms. No pulse, no loop.
- **Why:** The card tells two stories — it closes *and* it flags. Animating only the happy half would make the section a boast; the underline draw completes the sentence "and when it doesn't add up, you're told, not guessed". Amber is the attention colour, so it earns the one motion the palette allows: a single draw of attention, never a blink.
- **Build:** Fold into R1's keyframes (or its own 300 ms rule); CSS-only.
- **Risks:** Do not loop or pulse — amber that keeps moving is an alarm, and hard rule 5 reserves amber for attention only. One draw, then still.
- **Effort:** S (and best shipped *with* R1 as one sketch).

### R7. Perceivable hover/focus micro-transitions on interactive chrome.

- **Where:** `.btn`, `.nav-links a`, `.chip`, `.lang-chip`, links (`layout.css:59-66,77-80`, `sections.css:155-197`, `base.css:54-56`).
- **What:** 100–160 ms colour/border transitions on hover and focus-visible, instead of the current instant swap.
- **Why:** This answers "is this clickable?" — the one user question a 160 ms transition answers better than an instant state flip, and the cheapest accessibility win on the page (state change becomes perceivable rather than a snap). It is the only recommendation here that is polish rather than product, and it is deliberately last.
- **Build:** Pure CSS. Already covered by the reduce-motion switch.
- **Risks:** Must not touch focus-ring timing — `:focus-visible` (`base.css:79-83`) stays instant; only the resting colour/border of the target transitions.
- **Effort:** S.

---

## 3. What NOT to animate, and why

| Rejected idea | Reason it fails here |
|---|---|
| **Hero title load-in / staggered text reveal** | Pure "modern". No product question answered; the page's tone (`docs/SITE.md:34-38`, the honest pre-launch note) is calm. |
| **Any simulated "scanning / AI reading" animation** on the hero or doors (a shimmer over a receipt, a highlight sweeping the photo, "dots being OCR'd") | This is the copy rule's nightmare in motion: it *shows* "snap it and you're done", which `docs/SITE.md:34` forbids in words. A capture is a head start the user checks — nothing on the site may gesture at automatic. |
| **Staggered or asymmetric door reveals** | A 100 ms stagger makes one door primary and the other its fallback — the exact defect hard rule 15 and `doors.html:1-2` exist to prevent. |
| **FAQ accordion / collapse animation** | Hides answers behind a disclosure for no product gain, and risks muddying the `FAQPage` structured data the site deliberately ships (`docs/SITE.md:121,220`). |
| **Parallax / scroll-jacking on the generated night-grounds** (`section--ambience`, `hero-ground`, `check-ground`) | Main-thread scroll cost, vestibular trigger, zero product answer — and the grounds are photographic atmosphere with no claim in them (`docs/SITE.md:171`). |
| **Pulsing/glow on the palette dots** (`.dot--taillight` / `.dot--headlight`, `powertrains.html`) | Colour is meaning, not decoration (hard rule 5). Animating the fuel/electric dots turns meaning into an attention signal — and attention is amber's job, alone. |
| **Count-up numbers anywhere** | A counter implies a live measurement; the site's figures are illustrative fill-up values. Counting to `71.02` is fake-data motion. |
| **Currency / "both amounts" morph** | Money that animates into a value invites misreading, and the locale/format risk (RU separators) is real; the border story is already carried by the static pair. |
| **A Lottie / GSAP / animation library** | Violates the site's own rule — "No JavaScript framework. Progressive enhancement only" (`docs/SITE.md:76`) — and buys nothing CSS/SMIL cannot do at 1/100th the weight. |
| **Ambient background drift / gradient animation** | Same as parallax: decoration, main-thread cost, contradicts the photographic, still-night atmosphere. |

---

## 4. One sketch — R1, the cross-check lock

**Elements (existing classes):**
- `#check` section — `crosscheck.html:10`.
- `.check-rule` row — `crosscheck.html:22`, styled `sections.css:301-306`.
- `.check-rule__bar` × 2 — `crosscheck.html:23,25`, styled `sections.css:308-313` (`flex:1; height:2px; background: var(--taillight)`).
- `tick-circle` icon partial — `crosscheck.html:24`, `site/layouts/_partials/icons/tick-circle.html`.
- `.check-total` — `crosscheck.html:27`, `sections.css:315-321`.
- `.check-warn` / `.amber-underline` — `crosscheck.html:28-31`, `sections.css:328-346`.

**States and timing** (one-shot; trigger = `IntersectionObserver` fires at ~40% visibility of `#check`, adds `.is-inview`; resting state == today's static page):

| t (ms) | Element | Property | From → To | Easing |
|---|---|---|---|---|
| 0 | `.check-rule__bar` (left) | `transform: scaleX` | `0 → 1`, `transform-origin: left center` | `cubic-bezier(0.16, 1, 0.3, 1)` |
| 0 | `.check-rule__bar` (right) | `transform: scaleX` | `0 → 1`, `transform-origin: right center` | same |
| 0–400 | both bars | duration | 400 ms | — |
| 300 | `tick-circle` | `opacity` + `transform: scale` | `0 / 0.6 → 1 / 1` | `cubic-bezier(0.34, 1.56, 0.64, 1)` (spring-out) |
| 300–520 | tick | duration | 220 ms | — |
| 520 | `.check-total` | `opacity` + `translateY` | `0 / 6px → 1 / 0` | ease-out |
| 520–800 | total | duration | 280 ms | — |
| 1000 | `.amber-underline` | `background-size` (or a `scaleX` underline) | `0 2px → 100% 2px`, origin left | ease-out |
| 1000–1300 | underline | duration | 300 ms | — |

**Degradation matrix:**
- **No JavaScript:** no `.is-inview` ever added → every element rests in its static, fully-visible state (bars full width, tick visible, underline full). The page is complete; the animation is a bonus. (This is why the `from` states live in the keyframes with `animation-fill-mode: backwards`, and the *default* styles are the final state.)
- **Reduced motion:** `base.css:123-124` sets `animation: none !important` → same resting state, no motion.
- **Old browser without `IntersectionObserver` or `@keyframes`:** same resting state.

**Script cost:** ~400 bytes, no dependency, one observer for the `#check` section (and reused, if desired, for the other sections' `#id` anchors). All animation lives in `sections.css` keyframes, so the reduce-motion switch and the minified inline `<style>` (`head/css.html`) handle it for free. No new asset, no new request, no layout shift (bars and tick are already reserved space).

---

## 5. One observation outside scope

`site/assets/diagrams/pump-reading/law.en.svg:1` and `:12,13` carry a Russian `aria-label` and Russian text ("единственная сходящаяся тройка", "Исправление цифры…") inside the **English** diagram file. This is a content/localization defect, not an animation one, so it is recorded here rather than touched. It would surface if any of R2/R5 animate the law diagram. Owned by nothing I can see in this review's scope; the owning surface is the `/pump-reading/` article copy.

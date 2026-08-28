# Tankbook – The Marketing Site

*Single authority for `tankbook.app`: the public landing page, the legal pages, and the SEO
surface. Companion to `VISION.md` (what may be claimed), `DESIGN.md` (how it looks),
`SECURITY.md`/`LOGGING.md`/`SYNC.md`/`API.md` (what the privacy policy must say), and `TASKS.md`
(the build rows). Written 2026-08-28.*

## Why this exists now, and the blocker it closes

The site is not only marketing. `CONFIG.md` records an **open release blocker**: `HostAllowlist.allowedDomain`
and `Config.default.json` both carry `tankbook.app` as a **placeholder for a domain nobody owns**, and
an allowlist naming a domain we do not control is worse than no allowlist - anyone may register it and
inherit every guardrail's trust. Registering the apex for this site is what closes that hole, so the
first task here is a purchase, not a page.

Once registered: **apex `tankbook.app` serves this site**, `api.tankbook.app` stays the backend. The
allowlist matches domain suffixes, so both live under one registration.

## The copy rule, and it is the important part of this document

**The site may not promise what the corpus says we cannot deliver.** Hard rule 15 is a product
decision with measurements behind it: capture is a **head start, not an answer**, and typing is a
**peer path of equal standing**. The numbers that forced it - receipts **38.3%**, pump displays
**0%**, a fiscal QR present on **9 of 16** receipts and carrying 2 of 5 fields, Vision misreading a
digit at **confidence 1.00** - have not moved.

So:

| Never say | Say instead |
|---|---|
| "Zero typing" / "just snap a photo and you're done" | "Snap it or type it - both take seconds" |
| "Scans any receipt" / "AI reads your receipt perfectly" | "A scan fills in what it can read. You correct the rest, and it remembers" |
| "Automatic" as the headline verb | "Fast" - the honest claim, and the one the design actually delivers |

`VISION.md` §2 ("Camera is the primary input; the form is the fallback") **predates hard rule 15 and
is stale** - fix it there rather than copying it here. This table exists because a landing page is the
one artefact where an over-promise reaches a customer directly, and because every competitor's store
page in `COMPETITORS.md` over-promises exactly here.

### What we may claim, because it is true and nearly unowned

Straight from `VISION.md` §1's "genuinely unowned" list, and each is checkable in the app today:

- **Works with no account at all.** Every incumbent pushes a login; Fuelly's forced migration lost
  users years of data. Ours is the only "no login wall, ever" in the category.
- **Works offline.** No screen is sync-gated (hard rule 1).
- **Export is always free.** Drivvo paywalls paper reports and its reviews resent it.
- **The arithmetic cross-check, shown.** Litres x price = total, visible, as trust rather than magic.
- **Pump-display and dashboard photo capture.** Nobody else attempts it. Ships **off** today
  (P2.7), so it belongs on a roadmap page, not the hero.
- **True multi-currency with historical rates** - the rate on the day of the fill-up, both amounts kept.
- **Petrol, diesel, hybrid and EV in one history.**

Anything else needs evidence in `docs/` before it reaches a page.

## Where it lives and what builds it

`site/` in this monorepo, **not** a separate repository. The reason is drift: `design/tokens.json`
already generates `Theme.generated.swift`, and the same file must generate the site's CSS custom
properties, so the palette cannot diverge from the app. `design/screenshots/` holds the real,
committed EN+RU captures - the site uses those, and never a fabricated mockup. **The screenshot
partial takes explicit filenames and never globs**: the directory also holds
`P1.1-shell-dark-rejected-accent-tabbar.png`, a capture kept as the record of a hard-rule-5
violation, and a glob would ship it. The count is deliberately not written here - it was stale
within a day (116 recorded, 133 on disk), and an unmaintained number is this repo's most expensive
recurring bug.

- **Hugo extended** (v0.153.4 is installed), no third-party theme. A theme would fight the Night
  Drive palette harder than writing the layouts.
- **No JavaScript framework.** A landing page is documents. Progressive enhancement only.
- **`design/tokens.json` -> `site/assets/css/tokens.generated.css`** via a small generator beside the
  Swift one. Hand-editing that file is the same bug as hand-editing `Theme.generated.swift`.
- Hosting: static, on any CDN (Cloudflare Pages is the default assumption). The site is public and
  has no backend of its own.

## Information architecture

Bilingual **EN + RU from day one** (hard rule 10 applies to the product; the site follows it for the
same reason - the RU market is half the corpus). `defaultContentLanguage: en`, RU under `/ru/`,
**hand-written, never machine-translated**, because Russian runs 20-30% longer and short strings
expand worst - the same constraint that broke tab labels in the app will break nav items here.

| Path | Purpose | Notes |
|---|---|---|
| `/` | The landing page | Structure below |
| `/privacy/` | Privacy policy | Generated from real behaviour - see below. **Required** by App Store review |
| `/terms/` | Terms of use | Plain-language; no subscription terms while the Pro tier is deferred |
| `/support/` | How to get help, and the feedback route | `POST /feedback` is the in-app channel; this page is the out-of-app one. **Required** by App Store review. The address is **`to@belyaev.live`** (product owner, 2026-08-28) - it is also the App Store listing's support contact, so the two must never disagree |
| `/delete-account/` | How to delete an account and what happens | Apple requires an in-app route **and** a discoverable explanation. Ours is a tombstone: devices learn via `410`, **local data stays local** |
| `/roadmap/` | What is shipped, what is next, what was deliberately cut | Cheap honesty, and it is where pump capture and CarPlay belong |
| `/press/` | Name, icon, screenshots, one-paragraph description | Saves answering the same email twice |
| `/404.html` | | |
| favicon, `icon.svg`, `apple-touch-icon.png` | Tab and home-screen identity | Needed for the Lighthouse best-practices target; `DESIGN.md` already specifies the app icon, so the source art exists |

Deliberately **not** in v1: a blog (nothing to say yet, and an empty blog reads worse than none), a
newsletter, and any tracking-based personalisation.

### The landing page, in order

1. **Hero.** One sentence saying what it is, one line saying what it costs, two CTAs of **equal
   weight** - and this is a design rule, not a preference: the page must not make one entry path
   look like the other's fallback, exactly as the app must not. Below it, one real screenshot
   (dark, EN), not a device render with invented content.
2. **The two doors.** Snap it / type it, side by side. This is the product's spine and the section
   most likely to be diluted into "AI-powered scanning" by a well-meaning edit. It is the section
   the copy rule above exists to protect.
3. **The cross-check, shown.** Litres x price = total with the tick - a screenshot and one sentence.
   Trust that is visible is the thing incumbents cannot copy quickly.
4. **Your data, yours.** No account needed, works offline, export always free, nothing logged that
   is yours. Links to `/privacy/`.
5. **Every powertrain, every currency.** Petrol/diesel/hybrid/EV; the border story with both amounts.
6. **Roadmap teaser** -> `/roadmap/`.
7. **FAQ.** Five to seven real questions, marked up as `FAQPage` structured data.
8. **Footer.** Legal, support, language switch, and the honest pre-launch status.

**Pre-launch state matters:** there is no App Store listing yet, so a "Download on the App Store"
badge would be a lie. Until P6.6 ships a TestFlight ring the CTA is *"TestFlight is opening soon"*
with a single `mailto:to@belyaev.live`. No fake badges, no fake ratings, no invented review quotes.

**One caveat on that address, recorded rather than argued.** It is a personal mailbox published on
a public page, so it will be scraped and it will attract spam, and it is the address App Store
review will show as the support contact. Nothing here is blocked by that - it is the owner's
decision and it removes a launch dependency. The cheap upgrade path, whenever it is wanted, is an
alias on the registered domain forwarding to the same inbox: the published address changes, the
mailbox does not, and no page or listing has to be rewritten twice.

## Visual design

Night Drive, dark by default, from `design/tokens.json` - `midnight #101318`, `dash #1A1F27`,
`ink #EAEDF2`, `inkSoft #98A2B3`, `taillight #F4503A`, `headlight #4FC3E8`, `warn #F0A030`. Palette
semantics carry over unchanged (hard rule 5): **taillight is fuel and primary, headlight is
electric, amber is attention only**. Light mode ships too, from the same tokens' `light` values,
honouring `prefers-color-scheme`.

**Typography, and there is a licensing trap here.** The app's numerals are `DINAlternate-Bold`,
an **Apple system font that cannot be served on the web**, and SF Pro cannot be self-hosted either.

- **UI text: the system stack** (`-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, ...`). On
  Apple devices this *is* SF Pro, rendered natively, at zero download cost - a better match than any
  webfont substitute.
- **Numerals: one self-hosted OFL face** with a DIN-like condensed character and **tabular figures**,
  subset to digits and punctuation. Digits are script-independent, so a Latin-only face is fine for
  numbers - but **any face used for RU headings must carry Cyrillic**, which most DIN clones do not.
  Check that before choosing, not after.
- `font-display: swap`, self-hosted, preloaded. No Google Fonts request - it is a third-party
  connection on a page whose whole pitch is privacy.

Layout follows `DESIGN.md`'s rules where they apply: 20 px screen margin scaled up for desktop,
12 px card radius, hairline borders, generous vertical rhythm. Accessibility is the app's floor, not
lower: **AA contrast minimum**, visible focus rings, real landmarks, `prefers-reduced-motion`
respected, and every screenshot carrying a description rather than `alt="screenshot"`.

## SEO

**Technical, all of it cheap and all of it required:**

- One `<title>` and `<meta name="description">` per page per language, written by hand.
- **`hreflang` pairs on every page** including `x-default`, and a self-referencing `canonical`.
  This is the single most-missed item on bilingual sites and the one that actually costs rankings.
- `sitemap.xml` (Hugo built-in, multilingual-aware) and a `robots.txt` naming it.
- **Structured data**: `SoftwareApplication` on `/` (name, operating system, category, and a price
  of 0 while the free tier is the product), `FAQPage` on the FAQ, `Organization` in the footer.
  **Calibrate the FAQ expectation**: since 2023 Google shows FAQ rich results almost only for
  government and health sites, so this validates without earning a snippet there. Keep it - it
  costs nothing, and Yandex, which serves half our audience, still consumes it.
- **OpenGraph and Twitter cards** with a per-language OG image generated from a real screenshot.
- `apple-itunes-app` smart banner meta - **only once an App Store id exists**, not before.
- Performance is an SEO input and this stack makes it nearly free: no framework, Hugo-processed
  responsive images (**WebP with a PNG fallback**, `srcset`), inline critical CSS, everything else
  deferred. **Not AVIF**: Hugo's pipeline encodes JPEG/PNG/WebP/GIF and cannot emit AVIF, so
  "AVIF/WebP" would be a spec nobody can implement. WebP alone reaches the target here.
  **Target Lighthouse 100/100/100/100**, and treat anything less as a defect.

**Search consoles, both of them.** Google Search Console for the EN side; **Yandex.Webmaster for the
RU side** - Yandex is where the Russian-language audience actually searches, and the RU pages are
half the point of the site. Register both at launch, submit both sitemaps.

**Analytics: cookieless, and the choice is still open.** A privacy-first product that ships a cookie
banner has argued against itself on its own landing page. But the obvious pick carries a trap: this
document bans Google Fonts *because a third-party connection undercuts a privacy pitch*, and a
hosted analytics beacon is a third-party connection by exactly that test - while "self-hosted"
contradicts "the site has no backend of its own". Three honest options, and it is the product
owner's call: **(a) no analytics in v1** - most consistent, and the two search consoles still report
impressions and queries; **(b) the CDN operator's own analytics** - no new data processor, since it
already terminates every request; **(c) a hosted cookieless service** - a new processor that
`/privacy/` must then disclose. Ship nothing here until this is answered.

**Content SEO** is thin by design at launch: the honest long-tail is comparison and how-to material
("fuel log without an account", "track fuel costs offline", the importer paths from Fuelio/Drivvo/
Spritmonitor that `VISION.md` already calls table stakes). Those are real pages with real answers -
and none of them should be written before the app ships.

## The legal pages are generated from behaviour, not from a template

A privacy policy copied from a generator will contradict the app, and the contradiction is what App
Store review catches. Every statement below has a source in this repo, and **the App Store privacy
labels (P6.6) must match this page exactly**:

| The page must say | Source |
|---|---|
| The app is fully usable **with no account**; the local database is authoritative | Hard rule 1, `VISION.md` §2 |
| Sign-in is optional and enables sync, restore and the LLM gateway; we store the account id, email and the synced record stream, TLS + encrypted at rest, **no E2E in v1** | `SYNC.md` (signed off) |
| **We never log domain values** - amounts, stations, notes, coordinates, payloads, tokens and images, at any level, in any build | Hard rule 12, `LOGGING.md` |
| Images sent to the cloud extraction gateway are **processed transiently and never retained** | `API.md` LLM gateway |
| **Import parsing is the one exception**: an uploaded file and its parse result **are stored**, deliberately, for **30 days** - the same window as tombstones and undo | Hard rule 9, `SECURITY.md` (a written commitment) |
| Deleting an account is a **tombstone**: devices learn via `410`, and the user's log **stays on their phone** | `API.md` account, `SYNC.md` |
| Export is always free, CSV/JSON | `VISION.md` §2 |
| No ads, no server-side analytics, no content analytics | `VISION.md` §2 |

Open question for the product owner, flagged rather than answered here: **RU 152-ФЗ** obligations if
Russian users' data is processed, alongside GDPR. That is a legal decision, not an engineering one.

## Build phases, each with a gate that can fail

| Phase | Contents | Exit gate |
|---|---|---|
| **S0** | Register `tankbook.app`; set the real domain in `HostAllowlist.allowedDomain` and `Config.default.json` | The `CONFIG.md` release blocker is struck out and the allowlist test passes against the real domain. **No mail setup blocks launch**: the support address is an existing mailbox (below), so S0 is a purchase and a two-line code change, nothing more |
| **S1** | `site/` skeleton: Hugo config, EN+RU trees, the token generator, base layout, dark/light | `hugo --minify` exits 0; `tokens.generated.css` matches `tokens.json`; a mutation - change a token, rebuild - moves the CSS |
| **S2** | The landing page, both languages, real screenshots | Every claim on the page traces to a row in the copy rule table; **RU read for grammar by a human**, not just for overflow |
| **S3** | `/privacy/`, `/terms/`, `/support/`, `/delete-account/` | Each row of the legal table appears, and contradicts nothing in `SECURITY.md`, `LOGGING.md`, `SYNC.md` or `API.md` |
| **S4** | SEO surface: hreflang, canonicals, sitemap, structured data, OG images | Structured data validates; **every page has an hreflang pair including `x-default`**; Lighthouse 100 across the four categories, measured locally |
| **S5** | Deploy, both search consoles, the analytics decision | The apex serves over HTTPS, `api.tankbook.app` still resolves for the app, both sitemaps submitted - and **Lighthouse re-run against the live apex**, because headers, redirects, compression and HSTS belong to the host, so an S4 pass on localhost can still ship a page that fails its own target |

**S0 gates everything**, and it is a purchase rather than a task an agent can do.

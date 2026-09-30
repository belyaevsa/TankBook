# SITE-ANIMATION-REVIEW - which animated elements are worth adding to tankbook.live

You are a senior UX and UI designer reviewing a small marketing site. The product owner asks one
question: **which animated elements are worth adding to the site, and which are not.** Answer as a
designer who has to defend every animation to an engineer who pays for it and to a user who did not
ask for it. This is a read-only review: you write one report and nothing else.

## What the site is

`tankbook.live` - the public site of Tankbook, an iOS car cost log (fill-ups, service, expenses),
local-first, no account needed. Hugo static site under `site/`, no JavaScript framework, English and
Russian. Read, in this order:

    docs/SITE.md                         the site's single authority: purpose, the copy rule (no over-promise:
                                         capture is "a head start the user checks, never automatic"), the page
                                         list, the landing page structure, performance and privacy stance,
                                         "No JavaScript framework. Progressive enhancement only."
    docs/DESIGN.md                       the visual language: the Night Drive palette and what each colour MEANS
                                         (taillight = fuel/primary, headlight = electric, amber = attention only),
                                         DIN numbers / SF text, the MOTION section, the accessibility floor
    site/layouts/                        home.html, baseof.html, _partials/sections/*.html (hero, doors,
                                         crosscheck, yourdata, powertrains, faq)
    site/content/_index.md, _index.ru.md the landing page's copy and which screenshot each section shows
    site/content/pump-reading.md         a new long article: how the app reads a pump display from a photo,
                                         with inline SVG diagrams (site/assets/diagrams/pump-reading/*.svg)
    site/assets/css/*.css                what is already styled or animated (grep for transition, animation,
                                         @keyframes, prefers-reduced-motion)

The product's strongest ideas, which an animation could show better than a static page:
the two peer ways in (camera and keyboard, "two doors", hard rule 15 - neither may look secondary);
the arithmetic cross-check (litres x price = total, shown with a tick when it closes, a highlight
when it does not); reading numbers off a pump display photo; one history for petrol, diesel and
electric; money kept in two currencies at the fill-up day's rate.

## What to answer

1. **What exists.** Every animation or transition on the site today (file and line), and whether it
   respects `prefers-reduced-motion`.
2. **Recommendations, ranked** - at most eight. For each:
   - where exactly (page, section, element);
   - what moves, how long, what triggers it (load, scroll into view, hover, tap), and when it stops;
   - **why it earns its place**: which product idea or user question it answers that the static
     version does not. "It looks modern" is not a reason;
   - how to build it within the site's rules: CSS-only, SVG/SMIL, or a small progressive-enhancement
     script (and its size); what the page shows with no JavaScript and with reduced motion;
   - its risks: the copy rule (an animation that implies "automatic" or "instant" is an over-promise),
     the palette's meanings (amber only for attention; colour is meaning, not decoration), both
     languages (Russian strings run 20-30 % longer), both themes, a 390 px phone, performance
     (Core Web Vitals: layout shift, main-thread cost), and accessibility.
   - effort: S / M / L.
3. **What NOT to animate**, with the reason - the tempting ideas you reject for this site.
4. **One sketch** of your top recommendation precise enough to build from: the states and their
   timing (a small timeline table), the elements involved (existing class names where they exist).

Be concrete and brief. Cite files and lines for every claim about the current site. Where you use a
general UX principle or a study, name it; do not invent numbers.

## Fences

- **Read-only.** Write exactly one file: `agents/reviews/SITE-ANIMATION-deepseek.md`. Create no other
  file, edit nothing, run no builds, no `hugo`, no servers.
- **Git is read-only for you** (`git log`, `git show`, `git diff`); never `commit`, `add`, `checkout`,
  `stash`, `reset`, `restore`. Other sessions have uncommitted work in this checkout.
- Never `pgrep -f`.

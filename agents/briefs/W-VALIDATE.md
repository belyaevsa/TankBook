# Validation: the Tankbook marketing site (W1 + W2 + W3)

Repo: **`/Users/sbelyaev/repos/fuel-counter-ios`**, branch `main`, at commit `d81e414`.

**You are validating, not building.** Do not fix what you find. **Write no files except one report
at `/private/tmp/claude-501/-Users-sbelyaev-repos-fuel-counter-ios/w-validate-report.md`.** Do not
commit. Do not modify `site/`, `docs/`, `ios/`, `backend/`, or `scripts/`.

Your value is in finding what the builders and the orchestrator missed. A validation that reports
"all good" without having tried to break anything is worth nothing.

## The authority

`docs/SITE.md` is the specification. `design/screens/SiteLanding.dc.html` is the design reference.
`CLAUDE.md` hard rules 1, 5, 7, 9, 10, 12, 15 apply. Read those first.

## Capture EXIT CODES, not impressions

Run each, record the **real** exit code, and paste the number:

```
cd site && hugo --minify --gc ; echo "hugo: $?"
bash scripts/check-site.sh    ; echo "check-site: $?"
swift scripts/generate-site-tokens.swift --check ; echo "tokens: $?"
```

Beware the pipe trap: `cmd | grep x; echo $?` reports **grep's** status, not `cmd`'s. This has
already misled two people on this project today. Use `${PIPESTATUS[0]}` or avoid the pipe.

## What to attack, in priority order

**1. Is `scripts/check-site.sh` honest?** It reports ~149 passing checks. One of its gates was
already found to be **vacuous** - it referenced an undefined `$PUBLIC`, so `find` ran on an empty
path and passed unconditionally. **Assume there are more.** For each check, ask: *if the thing it
tests were broken, would this actually fail?* Break things and find out. Named suspects:
   - checks that `grep` for a string in a file that may not exist (a missing file greps clean);
   - checks whose loop body never executes because the glob matched nothing;
   - `set -e` interactions that make a failing command silently skip a check;
   - any check that asserts presence but not correctness (a canonical tag that is present but points
     at the wrong URL).
   **Report every vacuous check you find, with the mutation that proves it.**

**2. Do the claims on the site survive the corpus?** `docs/SITE.md`'s copy rule forbids "zero
typing", "just snap a photo", "automatic" as a headline verb, and any promise that capture is an
answer rather than a head start. Hard rule 15 makes typing a **peer path**. Read the rendered EN
and RU pages and judge whether the promise matches what the app does: receipts extract at 38.3%,
pump displays at 0%, pump capture ships **off**. Flag anything a user could reasonably read as a
stronger promise than that.

**3. Is the privacy page true?** Every statement must trace to `docs/SECURITY.md`,
`docs/LOGGING.md`, `docs/SYNC.md` or `docs/API.md`. Check the hard ones specifically: no end-to-end
encryption in v1; `/extract` images never retained; `/import/parse` **does** store a file for 30
days; deletion is a tombstone where local data stays local; nothing domain-valued is ever logged.
**A statement that is more flattering than the docs is a defect.** So is one that contradicts them.

**4. Read the Russian as Russian.** Not for overflow - for grammar, case agreement, and register.
This project has shipped RU defects that no test could see: `"%@ расходы"` rendered
"АВГУСТ РАСХОДЫ"; `с вашего %1$@` produced "с вашего телефон Android". Known and already reported,
so do not re-report unless you disagree: `БЕСПЛАТНО … БЕСПЛАТНЫЙ` repeating a root, `Топливо,
зарядки, сервис и всё остальное хранится` taking a singular verb on a plural list, and `как удобно`
reading clipped. **Find the ones nobody has found.**

**5. Hard rule 15 in the layout.** In "the two doors", snap-it and type-it must be visually equal -
same card, same accent, same title size, same image treatment. Read the CSS, not just the markup:
equality asserted in HTML can be undone by one selector. Report any asymmetry.

**6. The SEO surface.** Verify independently of `check-site.sh`: every page has a self-referencing
canonical whose href equals its own URL, an hreflang set including `x-default`, JSON-LD that parses,
and sitemaps that list both languages. Check the RU pages specifically - it is the half people skip.

**7. Accessibility.** AA contrast against the actual token values in `design/tokens.json`, computed
not eyeballed - report the ratios as numbers. Focus states, landmarks, and `alt` text that describes
rather than labels.

## What is already known - do not spend time re-reporting

- DNS for `tankbook.live` does not resolve yet. Deployment is blocked; nothing else is.
- The analytics choice is an open product decision. The site currently ships none, deliberately.
- The JSON Schema `$id` URIs and the signed `parity.*` fixtures deliberately still say
  `tankbook.app`. Both are recorded decisions, not oversights.
- There is no App Store listing, so no badge and no ratings is correct, not missing.

## Report

Write `/private/tmp/claude-501/-Users-sbelyaev-repos-fuel-counter-ios/w-validate-report.md`:

1. The exit codes, verbatim.
2. **Vacuous checks found**, each with the mutation proving it.
3. Defects, ordered by severity, each with file, line, and why it matters.
4. Claims that outrun the evidence.
5. What you could NOT verify, and why. A named gap is worth more than a confident guess.

Be specific and adversarial. If you believe part of the brief is wrong, say so - on this project,
agents who pushed back on a brief have been right every time.

En-dashes only, never em-dashes.

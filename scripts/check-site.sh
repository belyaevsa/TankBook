#!/bin/sh
# Tankbook marketing site gate (W1: SITE.md phases S1 + S2; W2: S3 legal pages + S4 SEO surface).
# Run from anywhere: scripts/check-site.sh
# Exits non-zero if any check fails. Every check prints PASS/FAIL with its evidence.

set -u
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

failures=0
pass() { printf 'PASS  %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1"; failures=$((failures + 1)); }

# ── S1: the token generator and its hand-edit guard ──────────────────────

if swift scripts/generate-site-tokens.swift >/dev/null 2>&1; then
  pass "generator runs clean (swift scripts/generate-site-tokens.swift)"
else
  fail "generator runs clean (swift scripts/generate-site-tokens.swift)"
fi

if swift scripts/generate-site-tokens.swift --check >/dev/null 2>&1; then
  pass "--check: tokens.generated.css matches design/tokens.json"
else
  fail "--check: tokens.generated.css matches design/tokens.json"
fi

# ── S1/S2: hugo builds, output exists, both languages ────────────────────

hugo_out="$(cd site && hugo --minify 2>&1)"
if [ $? -eq 0 ] && [ -f site/public/index.html ] && [ -f site/public/ru/index.html ]; then
  pass "hugo --minify exits 0 and public/index.html + public/ru/index.html exist"
else
  fail "hugo --minify exits 0 and public/index.html + public/ru/index.html exist"
  printf '%s\n' "$hugo_out"
fi

if grep -q 'lang="ru"' site/public/ru/index.html; then
  pass "RU page carries lang=\"ru\""
else
  fail "RU page carries lang=\"ru\""
fi

count="$(grep -c 'rel="stylesheet"' site/public/index.html)"
if [ "$count" -eq 0 ]; then
  pass "zero <link rel=\"stylesheet\"> - CSS is inlined (count: $count)"
else
  fail "zero <link rel=\"stylesheet\"> - CSS is inlined (found: $count)"
fi

if grep -q -- '--midnight' site/public/index.html; then
  pass "generated tokens really inlined (--midnight present in output HTML)"
else
  fail "generated tokens really inlined (--midnight present in output HTML)"
fi

# ── hygiene: no literal hex in hand-written CSS ──────────────────────────

if grep -rnE '#[0-9A-Fa-f]{3,8}|(rgba?|hsla?)\(' site/assets/css/base.css site/assets/css/layout.css site/assets/css/sections.css >/dev/null 2>&1; then
  fail "no literal hex in base.css/layout.css/sections.css (violations below)"
  grep -rnE '#[0-9A-Fa-f]{3,8}|(rgba?|hsla?)\(' site/assets/css/base.css site/assets/css/layout.css site/assets/css/sections.css
else
  pass "no literal hex in base.css/layout.css/sections.css"
fi

# Positive control: the hex pattern itself must match where hex legitimately
# lives, proving the grep above is not silently broken.
if grep -qE '#[0-9A-Fa-f]{3,8}|(rgba?|hsla?)\(' site/assets/css/tokens.generated.css; then
  pass "hex-regex sanity: matches tokens.generated.css (the file allowed to hold hex)"
else
  fail "hex-regex sanity: matches tokens.generated.css (the file allowed to hold hex)"
fi

# ── hygiene: en-dashes only, honest copy only ────────────────────────────

if grep -rn '—' site/content site/layouts site/assets/css site/i18n site/hugo.toml site/public/index.html site/public/ru/index.html >/dev/null 2>&1; then
  fail "no em-dash anywhere in site sources or rendered landing pages (violations below)"
  grep -rn '—' site/content site/layouts site/assets/css site/i18n site/hugo.toml site/public/index.html site/public/ru/index.html
else
  pass "no em-dash in site sources or rendered landing pages"
fi

if grep -riEn 'zero typing|just snap|scans any|reads.{0,20}perfectly|\\bautomatic' site/content/ site/i18n/ >/dev/null 2>&1; then
  fail "copy rule: forbidden over-promises found (violations below)"
  grep -riEn 'zero typing|just snap|scans any|reads.{0,20}perfectly|\\bautomatic' site/content/ site/i18n/
else
  pass "copy rule: no over-promises in content"
fi

# Positive controls for the greps above: strings that must be present, so a
# wrong pattern can never read as "passed".
if grep -q 'TestFlight is opening soon' site/public/index.html; then
  pass "grep sanity: EN landing contains its hero CTA string"
else
  fail "grep sanity: EN landing contains its hero CTA string"
fi

if grep -q 'или введите цифры' site/public/ru/index.html; then
  pass "grep sanity: RU landing contains its hero accent string"
else
  fail "grep sanity: RU landing contains its hero accent string"
fi

# ── hard rule 15: both doors ship the same screenshot files by treatment ──

for f in P1.4-home.png P2.1-capture.png P2.3-confirm.png P2.5-confirm-foreign.png P1.3-confirm-manual.png; do
  if grep -q "$f" site/public/index.html; then
    pass "EN landing references real screenshot $f by explicit name"
  else
    fail "EN landing references real screenshot $f by explicit name"
  fi
done

if find site/public -name '*.html' -exec grep -l 'rejected' {} + 2>/dev/null | grep -q .; then
  fail "no screenshot whose name contains 'rejected' is ever referenced (pages below)"
  find site/public -name '*.html' -exec grep -l 'rejected' {} + 2>/dev/null
else
  pass "no screenshot whose name contains 'rejected' is ever referenced (all built pages)"
fi

# ── S3: the legal pages exist, and the privacy table is all there ─────────

for page in privacy terms support delete-account roadmap press; do
  if [ -f "site/public/$page/index.html" ] && [ -f "site/public/ru/$page/index.html" ]; then
    pass "S3: /$page/ and /ru/$page/ built"
  else
    fail "S3: /$page/ and /ru/$page/ built"
  fi
done

# Every row of SITE.md's legal table, in both languages. Greps are per-language
# exact substrings of the shipped copy, so a rewrite that drops a claim fails.
privacy_claims() {
  # label                      EN pattern                       RU pattern
  check_claim "no account needed"          "with no account"                "без аккаунта"
  check_claim "sign-in optional"           "Sign-in is optional"            "Вход необязателен"
  check_claim "TLS in transit"             "TLS"                            "TLS"
  check_claim "encrypted at rest"          "encrypted at rest"              "зашифрованы на стороне хранилища"
  check_claim "no E2E in v1"               "end-to-end encryption"          "Сквозного шифрования"
  check_claim "never log domain values"    "domain values"                  "никогда не пишем в журналы"
  check_claim "gateway images transient"   "transiently"                    "на лету"
  check_claim "gateway images not retained" "never retained"                "не сохраняются"
  check_claim "import parse stored 30 days" "deliberately"                  "сознательно"
  check_claim "import parse 30-day window" "30 days"                        "30 дней"
  check_claim "import needs no sign-in"    "No sign-in is required"         "Аккаунт не нужен"
  check_claim "deletion is a tombstone"    "tombstone"                      "надгробие"
  check_claim "devices learn via 410"      "410"                            "410"
  check_claim "local log stays local"      "stays on your phone"            "остаётся на вашем телефоне"
  check_claim "export free CSV JSON"       "CSV"                            "CSV"
  check_claim "export free JSON"           "JSON"                           "JSON"
  check_claim "no ads"                     "no ads"                         "Никакой рекламы"
  check_claim "no server-side analytics"   "server-side analytics"          "серверной аналитики"
  check_claim "site: no cookies"           "no cookies"                     "не ставит cookie"
  check_claim "site: no third-party analytics" "third-party analytics"      "сторонней аналитик"
}
check_claim() {
  label="$1"; en="$2"; ru="$3"
  # Newlines survive minification inside paragraphs, so match against
  # whitespace-flattened HTML - a soft wrap must not hide a real claim.
  en_html="$(tr '\n' ' ' < site/public/privacy/index.html)"
  ru_html="$(tr '\n' ' ' < site/public/ru/privacy/index.html)"
  if printf '%s' "$en_html" | grep -qi "$en" && printf '%s' "$ru_html" | grep -q "$ru"; then
    pass "S3 privacy claim: $label (EN + RU)"
  else
    fail "S3 privacy claim: $label (EN: '$en', RU: '$ru')"
  fi
}
privacy_claims

# Positive control for the claim greps: they must be able to fail.
if grep -qi 'claim that was never written' site/public/privacy/index.html; then
  fail "privacy-claim grep sanity: pattern matched nothing yet returned success"
else
  if grep -qi 'domain values' site/public/privacy/index.html; then
    pass "privacy-claim grep sanity: real claim matches, absent pattern does not"
  else
    fail "privacy-claim grep sanity: real claim does not match - greps are broken"
  fi
fi

# Terms: the Pro tier is deferred - the word may not appear at all, EN or RU.
if grep -in 'subscription' site/public/terms/index.html >/dev/null 2>&1; then
  fail "S3 terms: no subscription clauses while Pro is deferred (matches below)"
  grep -in 'subscription' site/public/terms/index.html
else
  pass "S3 terms: 'subscription' appears nowhere (case-insensitive)"
fi
if grep -in 'подписк' site/public/ru/terms/index.html >/dev/null 2>&1; then
  fail "S3 terms RU: no subscription clauses while Pro is deferred (matches below)"
  grep -in 'подписк' site/public/ru/terms/index.html
else
  pass "S3 terms RU: 'подписк' appears nowhere"
fi

# ── S4: SEO surface ───────────────────────────────────────────────────────

baseurl="$(cd site && hugo config | sed -n "s/^baseurl = '\\(.*\\)'\$/\1/p")"
if [ -n "$baseurl" ]; then
  pass "S4: baseurl read from hugo config ($baseurl)"
else
  baseurl="https://tankbook.app/"
  fail "S4: could not read baseurl from hugo config - falling back to $baseurl"
fi

# Canonical self-reference + full hreflang set on EVERY built page. Redirect
# aliases (Hugo's http-equiv refresh stubs, e.g. /en/) are skipped and counted:
# a redirect is not a page, and grepping only the home page is the classic
# vacuous check this loop exists to prevent.
alias_pages=0
page_count=0
for f in $(find site/public -name '*.html' | sort); do
  if grep -q 'http-equiv="refresh"' "$f"; then
    alias_pages=$((alias_pages + 1))
    continue
  fi
  page_count=$((page_count + 1))
  rel="${f#site/public}"
  dir="${rel%/*}"
  base="${rel##*/}"
  if [ "$base" = "index.html" ]; then
    if [ -z "$dir" ]; then url="$baseurl"; else url="$baseurl$(printf '%s' "$dir" | sed 's|^/||')/"; fi
  else
    url="$baseurl$(printf '%s' "$rel" | sed 's|^/||')"
  fi
  label="${rel#/}"
  can="$(sed -n 's/.*<link rel="canonical" href="\([^"]*\)".*/\1/p' "$f")"
  if [ "$can" = "$url" ]; then
    pass "S4 canonical == own URL: $label"
  else
    fail "S4 canonical == own URL: $label (expected $url, got $can)"
  fi
  for lang in en ru x-default; do
    if grep -q "hreflang=\"$lang\"" "$f"; then
      pass "S4 hreflang $lang present: $label"
    else
      fail "S4 hreflang $lang present: $label"
    fi
  done
  xd="$(grep -o '<link rel="alternate" hreflang="x-default" href="[^"]*"' "$f" | sed 's/.*href="//;s/"$//')"
  enhref="$(grep -o '<link rel="alternate" hreflang="en" href="[^"]*"' "$f" | sed 's/.*href="//;s/"$//')"
  if [ -n "$xd" ] && [ "$xd" = "$enhref" ]; then
    pass "S4 x-default points at the EN page: $label"
  else
    fail "S4 x-default points at the EN page: $label (x-default: $xd, en: $enhref)"
  fi
  # V4: presence is not correctness. A wrong hreflang href on every page tells
  # search engines the translation lives at a 404, and the presence check above
  # cannot see it - a validator proved exactly that by pointing ru at /ru-wrong/
  # and watching 149 checks stay green.
  for lang in en ru; do
    href="$(grep -o "<link rel=\"alternate\" hreflang=\"$lang\" href=\"[^\"]*\"" "$f" | sed 's/.*href="//;s/"$//')"
    rel="$(printf '%s' "$href" | sed 's|https\{0,1\}://[^/]*||; s|/$||')"
    target="site/public${rel}"
    if [ -f "${target}/index.html" ] || [ -f "$target" ] || { [ -z "$rel" ] && [ -f site/public/index.html ]; }; then
      pass "S4 hreflang $lang resolves to a built page: $label"
    else
      fail "S4 hreflang $lang resolves to a built page: $label (href $href -> $target)"
    fi
  done
done
if [ "$page_count" -ge 16 ] && [ "$alias_pages" -ge 1 ]; then
  pass "S4 hreflang loop covered $page_count pages ($alias_pages redirect alias(es) skipped)"
else
  fail "S4 hreflang loop covered only $page_count page(s) with $alias_pages alias(es) - page count suspiciously low"
fi

# JSON-LD: extract every ld+json block from every built page and parse each one
# with python3 -m json.tool. Grepping for a type name without parsing is the
# trap this replaces: malformed JSON containing the word would pass it.
tmpdir="$(mktemp -d /tmp/check-site.XXXXXX)"
find site/public -name '*.html' -print0 | xargs -0 awk -v d="$tmpdir" '
  BEGIN { RS = "</script>"; n = 0 }
  /<script type="application\/ld\+json">/ {
    s = $0
    sub(/.*<script type="application\/ld\+json">/, "", s)
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
    printf "%s", s > (d "/ld." sprintf("%03d", ++n) ".json")
  }
  END { printf "%d\n", n > (d "/count") }'
ld_total="$(cat "$tmpdir/count")"
ld_bad=0
for j in "$tmpdir"/ld.*.json; do
  if ! python3 -m json.tool "$j" > "$tmpdir/parsed" 2>/dev/null; then
    ld_bad=$((ld_bad + 1))
    fail "S4 JSON-LD parses: $j (contents below)"
    cat "$j"
  fi
done
if [ "$ld_bad" -eq 0 ] && [ "$ld_total" -ge 6 ]; then
  pass "S4 JSON-LD parses: all $ld_total block(s) via python3 -m json.tool"
else
  if [ "$ld_total" -lt 6 ]; then
    fail "S4 JSON-LD parses: only $ld_total block(s) found - expected at least 6 (3 per language home)"
  fi
fi
for typ in SoftwareApplication FAQPage Organization; do
  if grep -q "\"@type\": *\"$typ\"\|\"@type\":\"$typ\"" "$tmpdir"/ld.*.json 2>/dev/null; then
    pass "S4 JSON-LD home carries $typ (inside parsed blocks)"
  else
    fail "S4 JSON-LD home carries $typ (inside parsed blocks)"
  fi
done
rm -rf "$tmpdir"

# Multilingual sitemap: an index plus one sitemap per language, all well-formed.
for s in sitemap.xml en/sitemap.xml ru/sitemap.xml; do
  if [ -f "site/public/$s" ] && xmllint --noout "site/public/$s" 2>/dev/null; then
    pass "S4 sitemap well-formed: $s"
  else
    fail "S4 sitemap well-formed: $s"
  fi
done
if grep -q 'en/sitemap.xml\|en.sitemap.xml' site/public/sitemap.xml && grep -q 'ru/sitemap.xml\|ru.sitemap.xml' site/public/sitemap.xml; then
  pass "S4 sitemap index lists both language sitemaps"
else
  fail "S4 sitemap index lists both language sitemaps"
fi

# OG images: per-language, exist on disk, 1200 px wide, and actually different.
og_en="$(sed -n 's/.*<meta property="og:image" content="\([^"]*\)".*/\1/p' site/public/index.html)"
og_ru="$(sed -n 's/.*<meta property="og:image" content="\([^"]*\)".*/\1/p' site/public/ru/index.html)"
check_og() {
  lang="$1"; og="$2"
  file="site/public/${og#"$baseurl"}"
  w="$(sips -g pixelWidth "$file" 2>/dev/null | awk '/pixelWidth/{print $2}')"
  if [ -f "$file" ] && [ "$w" = "1200" ]; then
    pass "S4 OG image $lang exists on disk and is 1200 px wide ($og)"
  else
    fail "S4 OG image $lang exists on disk and is 1200 px wide (file: $file, width: ${w:-none})"
  fi
}
check_og EN "$og_en"
check_og RU "$og_ru"
if [ -n "$og_en" ] && [ -n "$og_ru" ] && [ "$og_en" != "$og_ru" ]; then
  pass "S4 OG images are per-language (EN and RU URLs differ)"
else
  fail "S4 OG images are per-language (EN: $og_en, RU: $og_ru)"
fi

# Smart banner: nothing emitted while params.appStoreId is empty - and the gate
# itself must exist in the partial, or the absence would be vacuous.
if grep -rn 'apple-itunes-app' site/public >/dev/null 2>&1; then
  fail "S4 apple-itunes-app: must emit nothing while params.appStoreId is empty (matches below)"
  grep -rn 'apple-itunes-app' site/public
else
  pass "S4 apple-itunes-app: emitted nowhere in the built site"
fi
if grep -q 'apple-itunes-app' site/layouts/_partials/head/seo.html; then
  pass "S4 apple-itunes-app gate exists in head/seo.html (so the absence above is the gate working)"
else
  fail "S4 apple-itunes-app gate missing from head/seo.html - the absence above is vacuous"
fi

# Favicon and touch icon: linked from the head, present in the output.
if grep -q 'rel="icon"' site/public/index.html && [ -f site/public/icon.svg ]; then
  pass "S4 favicon linked and built (icon.svg)"
else
  fail "S4 favicon linked and built (icon.svg)"
fi
touch_w="$(sips -g pixelWidth site/public/apple-touch-icon.png 2>/dev/null | awk '/pixelWidth/{print $2}')"
touch_h="$(sips -g pixelHeight site/public/apple-touch-icon.png 2>/dev/null | awk '/pixelHeight/{print $2}')"
if grep -q 'rel="apple-touch-icon"' site/public/index.html && [ -f site/public/apple-touch-icon.png ] \
   && [ "$touch_w" = "180" ] && [ "$touch_h" = "180" ]; then
  pass "S4 apple-touch-icon linked and built (measured ${touch_w}x${touch_h})"
else
  fail "S4 apple-touch-icon linked and built (180x180 png)"
fi

# W3: favicon.ico is linked, present, and a real multi-size ICO - parsed from
# the ICONDIR header, not trusted from the filename.
if grep -q 'favicon.ico' site/public/index.html && [ -f site/public/favicon.ico ]; then
  if python3 -c "
import struct, sys
d = open(sys.argv[1], 'rb').read()
assert d[:4] == b'\x00\x00\x01\x00', 'not an ICO file'
n = struct.unpack('<H', d[4:6])[0]
assert n >= 1, 'empty ICO directory'
sizes = sorted({(d[6 + 16 * i] or 256, d[7 + 16 * i] or 256) for i in range(n)})
assert (16, 16) in sizes and (32, 32) in sizes, 'missing 16/32 entries: %s' % (sizes,)
print('ICO entries: %s' % (sizes,))
" site/public/favicon.ico; then
    pass "S4 favicon.ico linked, present and a valid multi-size ICO"
  else
    fail "S4 favicon.ico linked, present and a valid multi-size ICO"
  fi
else
  fail "S4 favicon.ico linked, present and a valid multi-size ICO"
fi

# ── W2 hygiene: no em-dash anywhere under site/, no raw <img> in layouts ──

# Every text file under site/, built output included. Binary artefacts (png)
# and the empty lock file are the only exclusions.
em_dash_hits="$(find site -type f ! -name '*.png' ! -name '.hugo_build.lock' -exec grep -l '—' {} + 2>/dev/null)"
if [ -n "$em_dash_hits" ]; then
  fail "W2 hygiene: no em-dash anywhere under site/ (violations below)"
  printf '%s\n' "$em_dash_hits"
else
  pass "W2 hygiene: no em-dash anywhere under site/"
fi

# screenshot.html is the only path to an <img>; the shortcode delegates to it
# and must not own an img tag of its own.
img_files="$(grep -rln '<img' site/layouts 2>/dev/null)"
img_bad="$(printf '%s' "$img_files" | grep -v '_partials/screenshot.html' | grep -v '^$' || true)"
if [ -z "$img_bad" ] && printf '%s' "$img_files" | grep -q '_partials/screenshot.html'; then
  pass "W2 hygiene: <img exists only in _partials/screenshot.html"
else
  fail "W2 hygiene: <img outside _partials/screenshot.html (violations below)"
  printf '%s\n' "$img_bad"
fi

# --- V1: the privacy page's STANCE, not just its topics --------------------
# The claim checks above grep for topics ("end-to-end encryption", "TLS", "410").
# A validator proved they pass when the sentence is INVERTED: rewriting the page
# to say "We use end-to-end encryption" or "plain HTTP with no TLS" kept all 149
# checks green. Those are the two directions an App Store reviewer and a user
# would care about most, so the stance is asserted negatively here: these
# sentences must NOT appear, in either language.
stance_bad_en='we use end-to-end|is end-to-end|end-to-end encrypted|fully encrypted end|plain http|without tls|no tls|we do not use tls'
stance_bad_ru='мы используем сквозное|сквозное шифрование применяется|без tls|обычный http'
stance_hits=""
for pg in site/public/privacy/index.html site/public/ru/privacy/index.html; do
  [ -f "$pg" ] || continue
  case "$pg" in
    *ru*) pat="$stance_bad_ru" ;;
    *)    pat="$stance_bad_en" ;;
  esac
  h="$(grep -inE "$pat" "$pg" || true)"
  [ -n "$h" ] && stance_hits="${stance_hits}${pg}: ${h}"$'\n'
done
if [ -z "$stance_hits" ]; then
  pass "V1 privacy stance: no inverted E2E or TLS claim in either language"
else
  fail "V1 privacy stance: the page claims the OPPOSITE of the docs"
  printf '%s' "$stance_hits"
fi

# Positive control: the negative patterns must be capable of matching. If this
# fails, the stance check above is passing because its regex is broken, not
# because the page is honest.
if printf 'We use end-to-end encryption.\n' | grep -qiE "$stance_bad_en"; then
  pass "V1 stance-pattern sanity: the EN inversion pattern matches a known-bad line"
else
  fail "V1 stance-pattern sanity: pattern cannot match its own example - the check above is vacuous"
fi

# --- W3: asset weight -------------------------------------------------------
# This gate exists because 147 checks passed while the site shipped a 2.1 MB and
# a 1.2 MB PNG: the generated grounds were referenced with .RelPermalink, so
# Hugo served the originals untouched. Correct content, ruinous delivery, and
# nothing here could see it. A cap is the cheapest thing that would have.
ASSET_CAP_KB=800
too_big=$(find site/public -type f \( -name '*.png' -o -name '*.jpg' -o -name '*.jpeg' -o -name '*.webp' \) -size +$((ASSET_CAP_KB))k 2>/dev/null || true)
if [ -z "$too_big" ]; then
  pass "W3 asset weight: no image over ${ASSET_CAP_KB} KB"
else
  fail "W3 asset weight: image(s) over ${ASSET_CAP_KB} KB"
  printf '%s\n' "$too_big" | while IFS= read -r f; do
    [ -n "$f" ] && printf '        %6s KB  %s\n' "$(( $(wc -c < "$f") / 1024 ))" "$f"
  done
fi

# Generated ambience must always go through the image pipeline. A raw .png under
# generated/ means someone used .RelPermalink on the source again.
raw_generated=$(find site/public/generated -type f ! -name '*.webp' 2>/dev/null || true)
if [ -z "$raw_generated" ]; then
  pass "W3 generated ambience is processed (webp only, never the source PNG)"
else
  fail "W3 generated ambience served raw - use .Resize/.Process, not .RelPermalink"
  printf '%s\n' "$raw_generated"
fi

printf '\n'
if [ "$failures" -eq 0 ]; then
  echo "check-site: all checks passed"
  exit 0
fi
echo "check-site: $failures check(s) FAILED"
exit 1

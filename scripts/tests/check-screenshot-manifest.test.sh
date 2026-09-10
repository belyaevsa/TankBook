#!/usr/bin/env bash
# Tests for the screenshot-manifest gate (RV.176 + PR.28).
#
# Runs the real check against synthetic trees, so the failure directions are
# proven without a simulator. Covers:
#   * a clean tree exits 0
#   * a planted orphan PNG exits non-zero and names the file
#   * a deleted capture line (the RV.150 mutation) exits non-zero and names it
#   * a missing / incomplete manifest entry exits non-zero
#   * an alias_shot frame is required to have an entry too
#   * a reasoned legacy entry is accepted; an unreasoned one is not
#   * the manifest helper records file, runtime, device and commit per frame,
#     merges rather than clobbers, and clears a frame from legacy when a line
#     now produces it
#
# Usage: scripts/tests/check-screenshot-manifest.test.sh
# Exit 0 when every case behaves; 1 otherwise.

set -u

root="$(cd "$(dirname "$0")/../.." && pwd)"
CHECK="$root/scripts/check-screenshot-manifest.sh"
HELPER="$root/scripts/screenshot-manifest.py"

tmp="$(mktemp -d -t tankbook-manifest-test)"
trap 'rm -rf "$tmp"' EXIT

pass=0
fail=0
check() { # <description> <expected-exit> <observed-exit> [<output> <needle>]
    local desc="$1" want="$2" got="$3" out="${4:-}" needle="${5:-}"
    if [ "$want" != "$got" ]; then
        echo "FAIL: $desc (want exit $want, got $got)"
        [ -n "$out" ] && printf '%s\n' "$out" | sed 's/^/    /'
        fail=$((fail + 1))
        return 1
    fi
    if [ -n "$needle" ] && ! printf '%s' "$out" | grep -Fq -- "$needle"; then
        echo "FAIL: $desc (output does not mention '$needle')"
        printf '%s\n' "$out" | sed 's/^/    /'
        fail=$((fail + 1))
        return 1
    fi
    echo "ok:   $desc"
    pass=$((pass + 1))
}

# --- synthetic tree ---------------------------------------------------------
make_tree() {
    local dir="$1"
    rm -rf "$dir"; mkdir -p "$dir/shots"
    cat > "$dir/capture.sh" <<'SH'
#!/usr/bin/env bash
capture alpha    en -seedX
capture alpha-ru ru -seedX
capture beta     en -seedY
alias_shot beta beta-alias
SH
    local name
    for name in alpha alpha-ru beta beta-alias; do
        printf '\x89PNG\r\n\x1a\n' > "$dir/shots/$name.png"
    done
    python3 - "$dir/manifest.json" <<'PY'
import json, sys
names = ["alpha", "alpha-ru", "beta", "beta-alias"]
json.dump({"frames": {n: {"runtime": "iOS.26.5", "device": "iPhone 17", "commit": "abc1234"} for n in names},
           "legacy": {}}, open(sys.argv[1], "w"))
PY
}

run_check() { # <dir> -> sets out, code
    out="$(SCREENSHOT_SCRIPT="$1/capture.sh" SCREENSHOT_DIR="$1/shots" \
        SCREENSHOT_MANIFEST="$1/manifest.json" bash "$CHECK" 2>&1)"
    code=$?
}

# 1. clean tree
make_tree "$tmp/clean"
run_check "$tmp/clean"
check "clean tree exits 0" 0 "$code" "$out" "PASS"

# 2. planted orphan PNG with no capture line
make_tree "$tmp/orphan"
printf '\x89PNG\r\n\x1a\n' > "$tmp/orphan/shots/gamma.png"
run_check "$tmp/orphan"
check "planted orphan PNG exits non-zero and names it" 1 "$code" "$out" "gamma: no capture line"

# 3. deleted capture line, PNG stays committed (the RV.150 mutation)
make_tree "$tmp/mutation"
python3 - "$tmp/mutation/capture.sh" <<'PY'
import sys
path = sys.argv[1]
lines = [l for l in open(path) if "capture alpha " not in l and "capture alpha-ru " not in l]
open(path, "w").writelines(lines)
PY
run_check "$tmp/mutation"
check "deleted capture line exits non-zero and names the frame" 1 "$code" "$out" "alpha: no capture line"

# 4. committed frame missing its manifest entry
make_tree "$tmp/missing"
python3 - "$tmp/missing/manifest.json" <<'PY'
import json, sys
data = json.load(open(sys.argv[1])); del data["frames"]["beta"]
json.dump(data, open(sys.argv[1], "w"))
PY
run_check "$tmp/missing"
check "missing manifest entry exits non-zero and names the frame" 1 "$code" "$out" "beta: no manifest entry"

# 5. manifest entry missing a field
make_tree "$tmp/field"
python3 - "$tmp/field/manifest.json" <<'PY'
import json, sys
data = json.load(open(sys.argv[1])); data["frames"]["beta"]["commit"] = ""
json.dump(data, open(sys.argv[1], "w"))
PY
run_check "$tmp/field"
check "manifest entry missing commit exits non-zero" 1 "$code" "$out" "missing commit"

# 6. alias frame must have an entry too
make_tree "$tmp/alias"
python3 - "$tmp/alias/manifest.json" <<'PY'
import json, sys
data = json.load(open(sys.argv[1])); del data["frames"]["beta-alias"]
json.dump(data, open(sys.argv[1], "w"))
PY
run_check "$tmp/alias"
check "alias_shot frame without an entry exits non-zero" 1 "$code" "$out" "beta-alias"

# 7. stale frames entry whose line is gone
make_tree "$tmp/stale"
python3 - "$tmp/stale/manifest.json" <<'PY'
import json, sys
data = json.load(open(sys.argv[1])); data["frames"]["ghost"] = {"runtime": "iOS.26.5", "device": "iPhone 17", "commit": "abc"}
json.dump(data, open(sys.argv[1], "w"))
PY
run_check "$tmp/stale"
check "stale frames entry exits non-zero" 1 "$code" "$out" "ghost"

# 8. reasoned legacy entry for an unreproducible frame
make_tree "$tmp/legacy"
printf '\x89PNG\r\n\x1a\n' > "$tmp/legacy/shots/delta.png"
python3 - "$tmp/legacy/manifest.json" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
data["legacy"]["delta"] = {"reason": "a springboard capture no line can produce"}
json.dump(data, open(sys.argv[1], "w"))
PY
run_check "$tmp/legacy"
check "reasoned legacy entry is accepted" 0 "$code" "$out" "PASS"

# 9. legacy entry with no reason fails
make_tree "$tmp/legacybad"
printf '\x89PNG\r\n\x1a\n' > "$tmp/legacybad/shots/delta.png"
python3 - "$tmp/legacybad/manifest.json" <<'PY'
import json, sys
data = json.load(open(sys.argv[1])); data["legacy"]["delta"] = {"reason": ""}
json.dump(data, open(sys.argv[1], "w"))
PY
run_check "$tmp/legacybad"
check "unreasoned legacy entry exits non-zero" 1 "$code" "$out" "delta: legacy entry has no reason"

# --- manifest helper: the writer the script calls ---------------------------
printf 'alpha\tiOS.26.5\tiPhone 17\tabc1234\nbeta-alias\tiOS.26.5\tiPhone 17\tabc1234\n' > "$tmp/entries.tsv"
python3 - "$tmp/manifest.json" "$tmp/entries.tsv" <<'PY'
import json, sys
json.dump({"frames": {}, "legacy": {"alpha": {"reason": "was legacy"}}}, open(sys.argv[1], "w"))
PY
python3 "$HELPER" merge "$tmp/manifest.json" "$tmp/entries.tsv" >/dev/null 2>&1
merge_code=$?
check "manifest helper merge exits 0" 0 "$merge_code"
helper_out="$(python3 - "$tmp/manifest.json" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
ok = []
for name in ("alpha", "beta-alias"):
    entry = data["frames"].get(name, {})
    if all(entry.get(k) for k in ("runtime", "device", "commit")):
        ok.append(name)
print("recorded %d/2" % len(ok))
print("legacy-cleared %s" % ("alpha" not in data.get("legacy", {})))
PY
)"
check "manifest helper records file/runtime/device/commit per frame" 0 "$(printf '%s' "$helper_out" | grep -c 'recorded 2/2' >/dev/null && echo 0 || echo 1)" "$helper_out" "recorded 2/2"
check "manifest helper clears a frame from legacy" 0 "$(printf '%s' "$helper_out" | grep -c 'legacy-cleared True' >/dev/null && echo 0 || echo 1)" "$helper_out" "legacy-cleared True"

# merge must preserve entries the run did not touch
printf 'gamma\tiOS.18.0\tiPhone 12\tdef5678\n' > "$tmp/entries2.tsv"
python3 "$HELPER" merge "$tmp/manifest.json" "$tmp/entries2.tsv" >/dev/null 2>&1
preserved="$(python3 - "$tmp/manifest.json" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
print("preserved" if data["frames"].get("alpha", {}).get("commit") == "abc1234" else "lost")
PY
)"
check "manifest helper preserves untouched entries" 0 "$(printf '%s' "$preserved" | grep -q preserved && echo 0 || echo 1)" "$preserved" "preserved"

# --- real tree: the check must pass on the shipped manifest -----------------
out="$(bash "$CHECK" 2>&1)"; code=$?
check "the real tree passes the check" 0 "$code" "$out" "PASS"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]

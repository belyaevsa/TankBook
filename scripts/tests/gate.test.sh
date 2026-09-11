#!/usr/bin/env bash
# Tests for scripts/gate.sh (RV.174).
#
# The gate's whole claim is that package-green is not app-green: the app-target
# `xcodebuild` step must run, and its exit code must stop the gate. The real
# toolchain is replaced with logging stubs so both directions are proven
# without a simulator:
#   * every step passes -> exit 0, in package -> lint -> app -> tests order
#   * each step's failure exits with that step's code and stops the ones after
#   * a non-zero xcodebuild is not ignored (the named vacuous trap)
#   * RELEASE=1 adds the Release app build; without it there is none
#
# Usage: scripts/tests/gate.test.sh
# Exit 0 when every case behaves; 1 otherwise.

set -u

root="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$root/scripts/gate.sh"

tmp="$(mktemp -d -t tankbook-gate-test)"
trap 'rm -rf "$tmp"' EXIT

bindir="$tmp/bin"
log="$tmp/log"
mkdir -p "$bindir"
export GATE_TEST_LOG="$log"

cat > "$bindir/swift" <<'SH'
#!/usr/bin/env bash
echo "swift $*" >> "$GATE_TEST_LOG"
case "${1:-}" in
  build) exit "${GATE_TEST_SWIFT_BUILD_EXIT:-0}" ;;
  test)  exit "${GATE_TEST_SWIFT_TEST_EXIT:-0}" ;;
esac
exit 0
SH

cat > "$bindir/swiftlint" <<'SH'
#!/usr/bin/env bash
echo "swiftlint $*" >> "$GATE_TEST_LOG"
exit "${GATE_TEST_SWIFTLINT_EXIT:-0}"
SH

cat > "$bindir/xcodegen" <<'SH'
#!/usr/bin/env bash
echo "xcodegen $*" >> "$GATE_TEST_LOG"
exit "${GATE_TEST_XCODEGEN_EXIT:-0}"
SH

cat > "$bindir/xcodebuild" <<'SH'
#!/usr/bin/env bash
echo "xcodebuild $*" >> "$GATE_TEST_LOG"
case "$*" in
  *"-configuration Release"*) exit "${GATE_TEST_XCODEBUILD_RELEASE_EXIT:-0}" ;;
  *) exit "${GATE_TEST_XCODEBUILD_EXIT:-0}" ;;
esac
SH
chmod +x "$bindir"/*

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

run_gate() { # <VAR=value...> -> sets code, out
    : > "$log"
    out="$(env PATH="$bindir:$PATH" "$@" bash "$GATE" 2>&1)"
    code=$?
}

# true when every needle appears in the log in the given order
in_order() {
    local prev=0 needle n
    for needle in "$@"; do
        n="$(grep -n -F -- "$needle" "$log" | head -1 | cut -d: -f1)"
        [ -n "$n" ] && [ "$n" -gt "$prev" ] || return 1
        prev="$n"
    done
    return 0
}

# assert a command never ran
absent() { # <description> <needle>
    if grep -q -F -- "$2" "$log"; then
        echo "FAIL: $1 (log still has '$2')"
        sed 's/^/    /' "$log"
        fail=$((fail + 1))
    else
        echo "ok:   $1"
        pass=$((pass + 1))
    fi
}

# assert a command ran
present() { # <description> <needle>
    if grep -q -F -- "$2" "$log"; then
        echo "ok:   $1"
        pass=$((pass + 1))
    else
        echo "FAIL: $1 (log has no '$2')"
        sed 's/^/    /' "$log"
        fail=$((fail + 1))
    fi
}

# 1. all steps pass
run_gate
check "all steps pass exits 0" 0 "$code" "$out" "all steps passed"
if in_order "swift build" "swiftlint lint" "xcodegen generate" "xcodebuild" "swift test"; then
    echo "ok:   step order is package -> lint -> app -> tests"
    pass=$((pass + 1))
else
    echo "FAIL: step order is not package -> lint -> app -> tests"
    sed 's/^/    /' "$log"
    fail=$((fail + 1))
fi
if [ "$(grep -c '^xcodebuild ' "$log")" = "1" ] && grep -q -- "-configuration Debug" "$log"; then
    echo "ok:   Debug app build runs exactly once"
    pass=$((pass + 1))
else
    echo "FAIL: Debug app build did not run exactly once"
    sed 's/^/    /' "$log"
    fail=$((fail + 1))
fi

# 2. swift build fails: the first step, nothing else runs
run_gate GATE_TEST_SWIFT_BUILD_EXIT=7
check "package failure exits with its code" 7 "$code" "$out" "exit 7"
absent "package failure stops the gate" "swiftlint"

# 3. swiftlint fails: package ran, nothing after lint
run_gate GATE_TEST_SWIFTLINT_EXIT=9
check "lint failure exits with its code" 9 "$code" "$out" "exit 9"
absent "lint failure stops before the app build" "xcodebuild"

# 4. xcodegen fails: no app build
run_gate GATE_TEST_XCODEGEN_EXIT=11
check "xcodegen failure exits with its code" 11 "$code" "$out" "exit 11"
absent "xcodegen failure stops before xcodebuild" "xcodebuild"

# 5. xcodebuild fails: its exit code is not ignored, tests do not run
run_gate GATE_TEST_XCODEBUILD_EXIT=13
check "app-build failure exits with its code" 13 "$code" "$out" "exit 13"
absent "app-build failure stops before the tests" "swift test"

# 6. swift test fails: all earlier steps ran
run_gate GATE_TEST_SWIFT_TEST_EXIT=17
check "test failure exits with its code" 17 "$code" "$out" "exit 17"
present "test failure means the app build had already run" "xcodebuild"

# 7. RELEASE=1 adds the Release build, between the Debug build and the tests
run_gate RELEASE=1
check "RELEASE=1 exits 0 when all steps pass" 0 "$code" "$out" "all steps passed"
if [ "$(grep -c '^xcodebuild ' "$log")" = "2" ] && \
   in_order "swift build" "xcodebuild" "-configuration Release" "swift test"; then
    echo "ok:   RELEASE=1 adds the Release app build after the Debug one"
    pass=$((pass + 1))
else
    echo "FAIL: RELEASE=1 did not add the Release app build in order"
    sed 's/^/    /' "$log"
    fail=$((fail + 1))
fi

# 8. a failing Release build fails the gate
run_gate RELEASE=1 GATE_TEST_XCODEBUILD_RELEASE_EXIT=19
check "Release failure exits with its code" 19 "$code" "$out" "exit 19"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]

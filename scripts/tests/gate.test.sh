#!/usr/bin/env bash
# Tests for scripts/gate.sh (RV.174, RV.250).
#
# The gate's whole claim is that package-green is not app-green: the app-target
# `xcodebuild` step must run, and its exit code must stop the gate. It now also
# runs the app-target unit bundle (`-only-testing:TankbookTests`), which
# `swift test` never touches. The real toolchain is replaced with logging stubs
# so every direction is proven without a simulator:
#   * every step passes -> exit 0, in package -> lint -> app -> package-tests ->
#     app-tests order
#   * each step's failure exits with that step's code and stops the ones after
#   * a non-zero xcodebuild is not ignored (the named vacuous trap), for both the
#     app build and the app-target unit tests
#   * RELEASE=1 adds the Release and Beta app builds and the experiments check
#     (absent from Release, present in Beta); without it there are none, and a
#     failing check fails the gate
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
case "$*" in
  *"-showBuildSettings"*)
    config="$(printf '%s\n' "$@" | awk 'prev == "-configuration" {print; exit} {prev = $0}')"
    echo "    TARGET_BUILD_DIR = /stub/${config}-iphonesimulator"
    echo "    WRAPPER_NAME = Tankbook.app"
    exit 0 ;;
esac
echo "xcodebuild $*" >> "$GATE_TEST_LOG"
case "$*" in
  *"-only-testing:TankbookTests"*) exit "${GATE_TEST_APPTESTS_EXIT:-0}" ;;
  *"-configuration Release"*) exit "${GATE_TEST_XCODEBUILD_RELEASE_EXIT:-0}" ;;
  *"-configuration Beta"*) exit "${GATE_TEST_XCODEBUILD_BETA_EXIT:-0}" ;;
  *) exit "${GATE_TEST_XCODEBUILD_EXIT:-0}" ;;
esac
SH
cat > "$bindir/experiments-check" <<'SH'
#!/usr/bin/env bash
echo "experiments-check $*" >> "$GATE_TEST_LOG"
exit "${GATE_TEST_EXPERIMENTS_EXIT:-0}"
SH
chmod +x "$bindir"/*
export GATE_EXPERIMENTS_CHECK="$bindir/experiments-check"

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
if in_order "swift build" "swiftlint lint" "xcodegen generate" "xcodebuild" "swift test" "-only-testing:TankbookTests"; then
    echo "ok:   step order is package -> lint -> app -> package-tests -> app-tests"
    pass=$((pass + 1))
else
    echo "FAIL: step order is not package -> lint -> app -> package-tests -> app-tests"
    sed 's/^/    /' "$log"
    fail=$((fail + 1))
fi
if [ "$(grep -c '^xcodebuild .* build$' "$log")" = "1" ] && grep -q -- "-configuration Debug" "$log"; then
    echo "ok:   Debug app build runs exactly once"
    pass=$((pass + 1))
else
    echo "FAIL: Debug app build did not run exactly once"
    sed 's/^/    /' "$log"
    fail=$((fail + 1))
fi
if [ "$(grep -c 'only-testing:TankbookTests' "$log")" = "1" ] && \
   grep -q -- "-only-testing:TankbookTests test$" "$log"; then
    echo "ok:   app-target unit bundle runs exactly once, in its own invocation"
    pass=$((pass + 1))
else
    echo "FAIL: app-target unit bundle did not run exactly once"
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
absent "app-build failure stops before the app-target tests" "only-testing:TankbookTests"

# 6. swift test fails: all earlier steps ran, the app-target bundle does not
run_gate GATE_TEST_SWIFT_TEST_EXIT=17
check "package-test failure exits with its code" 17 "$code" "$out" "exit 17"
present "package-test failure means the app build had already run" "xcodebuild"
absent "package-test failure stops before the app-target tests" "only-testing:TankbookTests"

# 7. app-target unit test fails: its exit code is not ignored (the RV.250 trap)
run_gate GATE_TEST_APPTESTS_EXIT=23
check "app-target test failure exits with its code" 23 "$code" "$out" "exit 23"
present "app-target test failure means the package tests had run" "swift test"

# 8. RELEASE=1 adds the Release and Beta builds and the experiments check,
# between the Debug build and the tests
run_gate RELEASE=1
check "RELEASE=1 exits 0 when all steps pass" 0 "$code" "$out" "all steps passed"
if [ "$(grep -c '^xcodebuild ' "$log")" = "4" ] && \
   in_order "swift build" "xcodebuild" "-configuration Release" "-configuration Beta" \
     "experiments-check /stub/Release-iphonesimulator/Tankbook.app absent" \
     "experiments-check /stub/Beta-iphonesimulator/Tankbook.app present" \
     "swift test" "-only-testing:TankbookTests"; then
    echo "ok:   RELEASE=1 adds Release, Beta and the experiments check (absent, then present) after the Debug build"
    pass=$((pass + 1))
else
    echo "FAIL: RELEASE=1 did not add Release, Beta and the experiments check in order"
    sed 's/^/    /' "$log"
    fail=$((fail + 1))
fi

# 8b. without RELEASE=1 neither the Beta build nor the check runs
run_gate
absent "no Beta build without RELEASE=1" "-configuration Beta"
absent "no experiments check without RELEASE=1" "experiments-check"

# 9. a failing Release build fails the gate
run_gate RELEASE=1 GATE_TEST_XCODEBUILD_RELEASE_EXIT=19
check "Release failure exits with its code" 19 "$code" "$out" "exit 19"

# 10. a failing Beta build fails the gate before the check
run_gate RELEASE=1 GATE_TEST_XCODEBUILD_BETA_EXIT=29
check "Beta failure exits with its code" 29 "$code" "$out" "exit 29"
absent "Beta failure stops before the experiments check" "experiments-check"

# 11. an experiment in the store build fails the gate before the tests
run_gate RELEASE=1 GATE_TEST_EXPERIMENTS_EXIT=1
check "experiments-check failure exits with its code" 1 "$code" "$out" "experiments"
absent "experiments-check failure stops before the tests" "swift test"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]

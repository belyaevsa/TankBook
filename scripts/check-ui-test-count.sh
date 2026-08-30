#!/usr/bin/env bash
# The UI-suite under-run gate (P2.16).
#
# xcodebuild can print "Test Suite 'X' passed" and "Executed N tests, with 0
# failures" while some of X's tests never ran at all - a green result that
# measured nothing. This is the sibling of the "a --filter matching nothing
# prints 'Test run with 0 tests ... passed'" trap (docs/TESTING.md), and it makes
# every green run untrustworthy until it is caught.
#
# The summary line ("Executed N tests") is what lies; the only trustworthy record
# is the observed test cases themselves. So this script counts the
#   Test Case '-[TankbookUITests.<Suite> <test>]' started.
# lines - one per test that actually began executing - and compares that observed
# count against the number of `func test` declarations in the suite's source
# file. It deliberately does NOT read the "Executed N tests" summary.
#
# Usage:
#   scripts/check-ui-test-count.sh <xcodebuild-log>
#   scripts/check-ui-test-count.sh <xcodebuild-log> <Suite> [<Suite> ...]
#
# With no suite arguments, every suite the log says "started" (and which exists
# as ios/App/UITests/<suite>.swift) is checked against its own source. With suite
# arguments, only those suites are checked - use this to assert that a specific
# -only-testing: selection ran its full count. A named suite that never appears
# in the log counts as 0 observed, so it fails.
#
# Exit status:
#   0   every checked suite ran exactly as many tests as it declares
#   1   some suite under-ran (observed < declared), a named suite is missing
#       from the log, or no suites at all were observed
#   2   usage error (missing log file, missing source directory)

set -u

UI_TESTS_DIR="${UI_TESTS_DIR:-ios/App/UITests}"
BUNDLE="${BUNDLE:-TankbookUITests}"

if [ "$#" -lt 1 ]; then
    echo "usage: $0 <xcodebuild-log> [<Suite> ...]" >&2
    exit 2
fi

log="$1"
shift
named_suites=("$@")

[ -f "$log" ] || { echo "error: log not found: $log" >&2; exit 2; }
[ -d "$UI_TESTS_DIR" ] || { echo "error: UI tests directory not found: $UI_TESTS_DIR" >&2; exit 2; }

# Resolve the suites to check. Explicit names win; otherwise derive them from the
# log's class-level "Test Suite 'X' started" lines, keeping only suites that also
# exist as a source file (this drops the scaffolding suites "All tests",
# "Selected tests" and "TankbookUITests.xctest").
if [ "${#named_suites[@]}" -gt 0 ]; then
    suites=("${named_suites[@]}")
else
    suites=()
    while IFS= read -r name; do
        [ -f "$UI_TESTS_DIR/$name.swift" ] && suites+=("$name")
    done < <(grep -oE "Test Suite '[^']+' started" "$log" \
        | sed -E "s/Test Suite '([^']+)' started/\1/" | sort -u)
fi

if [ "${#suites[@]}" -eq 0 ]; then
    echo "FAIL: no UI test suites observed in the log." >&2
    echo "      A filter matching nothing prints 'Test run with 0 tests ... passed'" >&2
    echo "      and exits 0 - that is an under-run and must not pass." >&2
    exit 1
fi

overall=0
for suite in "${suites[@]}"; do
    file="$UI_TESTS_DIR/$suite.swift"
    if [ ! -f "$file" ]; then
        echo "FAIL: $suite has no source file at $file" >&2
        overall=1
        continue
    fi

    expected=$(grep -c "func test" "$file")
    # Observed = the number of "Test Case ... started" lines for this suite.
    # This is the ground truth; the "Executed N tests" summary is not consulted.
    observed=$(grep -cE "Test Case '-\[$BUNDLE\.$suite [^]]+\]' started\." "$log")

    if [ "$observed" -lt "$expected" ]; then
        echo "FAIL: $suite under-ran: $observed executed of $expected declared"
        overall=1
    elif [ "$observed" -gt "$expected" ]; then
        echo "WARN: $suite over-ran: $observed executed of $expected declared (stale log vs source?)"
    else
        echo "ok:   $suite $observed/$expected"
    fi
done

if [ "$overall" -eq 0 ]; then
    echo "PASS: every checked suite executed its full declared count."
else
    echo "UNDER-RUN: one or more suites executed fewer tests than they declare."
fi
exit "$overall"

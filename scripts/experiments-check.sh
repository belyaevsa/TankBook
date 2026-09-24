#!/usr/bin/env bash
# Proves the store build carries no beta experiment (docs/CONFIG.md ->
# "Build channels and experiments").
#
# Code behind `#if EXPERIMENTS` compiles into Debug and Beta and must be absent
# from Release. A missed guard compiles and runs fine - the store build simply
# ships the experiment - so the check reads the built binary itself: Swift keeps
# type names in the binary's reflection metadata, and each experiment's types
# are named below.
#
# Usage:
#   scripts/experiments-check.sh <binary-or-.app> absent    # Release: exit 1 if any marker is found
#   scripts/experiments-check.sh <binary-or-.app> present   # Beta: exit 1 if a marker is missing
# The `present` form is what keeps the `absent` form honest - a check that can
# no longer see the names would pass every Release build.
set -euo pipefail

# One entry per BetaExperiment case: a type name only that experiment's code
# declares. BetaExperiment itself is always listed.
MARKERS=(BetaExperiment CaptureLabView CaptureLabRunner CaptureLabLogStore)

target="${1:?usage: experiments-check.sh <binary-or-.app> absent|present}"
mode="${2:?usage: experiments-check.sh <binary-or-.app> absent|present}"
if [ -d "$target" ]; then
  name="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$target/Info.plist")"
  target="$target/$name"
fi
[ -f "$target" ] || { echo "experiments-check: no such binary: $target" >&2; exit 2; }

status=0
for marker in "${MARKERS[@]}"; do
  if LC_ALL=C grep -aq "$marker" "$target"; then found=1; else found=0; fi
  case "$mode" in
    absent)  [ "$found" -eq 0 ] || { echo "experiments-check: ${marker} is in ${target} - an experiment reached the store build" >&2; status=1; } ;;
    present) [ "$found" -eq 1 ] || { echo "experiments-check: ${marker} is missing from ${target} - the check can no longer see experiments, or the Beta build lost one" >&2; status=1; } ;;
    *) echo "experiments-check: mode is absent or present, not '${mode}'" >&2; exit 2 ;;
  esac
done
[ "$status" -eq 0 ] && echo "experiments-check: ${mode} - ${#MARKERS[@]} markers checked in ${target}"
exit "$status"

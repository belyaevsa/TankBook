#!/usr/bin/env bash
# The screenshot-manifest gate (RV.176 + PR.28).
#
# `design/screenshots/` is the visual record - the only check that catches
# colour, truncation and layout. A committed PNG that no capture line produces
# is evidence nobody can regenerate: a shared change invalidates it silently and
# it ages into confident proof of code that no longer exists.
#
# The script already fails when two names produce one frame (`4bbb302`). This is
# the mirror: a committed name that no line produces. It is a pure function over
# the tree - it does not need a simulator - so it runs in CI on every push.
#
# For every committed `design/screenshots/*.png`:
#   * it must be produced by a `capture` or `alias_shot` line in the script, and
#     carry a `frames` manifest entry with runtime, device and commit; or
#   * it must be a reasoned `legacy` entry, for a frame whose producing code is
#     gone. A legacy entry must carry a non-empty reason, and the check prints
#     every legacy entry on each run - so the list cannot grow quietly, and the
#     reason is what a reviewer holds it to. It is a narrow, deliberate
#     exception, never a place to park an orphan.
# A `frames` entry whose name is no longer produced by a line is stale and
# fails: that is the RV.150 shape, a capture line deleted while its PNG stays
# committed.
#
# Exit status:
#   0   every committed frame is produced by a line and recorded, or reasoned
#   1   an orphan, a missing/stale manifest entry, or a bad legacy entry
#   2   usage error (missing script or directory)

set -u

root="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="${SCREENSHOT_SCRIPT:-$root/scripts/capture-screenshots.sh}"
OUT="${SCREENSHOT_DIR:-$root/design/screenshots}"
MANIFEST="${SCREENSHOT_MANIFEST:-$OUT/manifest.json}"

if [ ! -f "$SCRIPT" ]; then
    echo "error: capture script not found: $SCRIPT" >&2
    exit 2
fi
if [ ! -d "$OUT" ]; then
    echo "error: screenshots directory not found: $OUT" >&2
    exit 2
fi

python3 - "$SCRIPT" "$OUT" "$MANIFEST" <<'PYEOF'
import glob
import json
import os
import re
import sys

script_path, out_dir, manifest_path = sys.argv[1:4]

# --- the names the script produces ------------------------------------------
# Join line continuations first: a `capture` line may wrap, and the frame name
# is the second token on the logical line.
with open(script_path, encoding="utf-8") as handle:
    logical = []
    buffer = ""
    for raw in handle:
        line = raw.rstrip("\n")
        if line.endswith("\\"):
            buffer += line[:-1] + " "
            continue
        logical.append(buffer + line)
        buffer = ""
    if buffer:
        logical.append(buffer)

declared = {}
for line in logical:
    stripped = line.strip()
    if not stripped or stripped.startswith("#"):
        continue
    match = re.match(r"capture\s+(\S+)", stripped)
    if match:
        declared[match.group(1)] = "capture"
        continue
    match = re.match(r"alias_shot\s+(\S+)\s+(.*)", stripped)
    if match:
        for name in match.group(2).split():
            if not name.startswith("-"):
                declared[name] = "alias of %s" % match.group(1)

# --- the committed frames ----------------------------------------------------
committed = sorted(
    os.path.basename(path)[:-4]
    for path in glob.glob(os.path.join(out_dir, "*.png"))
)

# --- the manifest ------------------------------------------------------------
if os.path.exists(manifest_path):
    with open(manifest_path, encoding="utf-8") as handle:
        manifest = json.load(handle)
else:
    manifest = {}
frames = manifest.get("frames", {})
legacy = manifest.get("legacy", {})

failures = []


def fail(message):
    failures.append(message)


# Every committed frame is either produced by a line (with a manifest entry) or
# a reasoned legacy exception.
for name in committed:
    if name in legacy:
        entry = legacy[name] or {}
        reason = entry.get("reason", "") if isinstance(entry, dict) else ""
        if not reason.strip():
            fail("%s: legacy entry has no reason" % name)
        if name in declared:
            fail("%s: has a capture line and a legacy entry - drop the legacy entry" % name)
        if name in frames:
            fail("%s: is in both frames and legacy - it cannot be both" % name)
        continue
    if name not in declared:
        fail("%s: no capture line produces this frame (add a line or delete the file)" % name)
        continue
    entry = frames.get(name)
    if not isinstance(entry, dict):
        fail("%s: no manifest entry (run capture-screenshots.sh)" % name)
        continue
    for field in ("runtime", "device", "commit"):
        if not str(entry.get(field, "")).strip():
            fail("%s: manifest entry is missing %s" % (name, field))

# A frames entry whose name no line produces is stale - the RV.150 mutation:
# the line was deleted while the PNG stayed committed.
for name in sorted(frames):
    if name not in declared:
        fail("%s: manifest frames entry has no producing capture line" % name)
    if name not in committed:
        fail("%s: manifest frames entry has no committed PNG" % name)

# Legacy entries must be real files with a reason; the script must not also
# produce them (if it does, the entry is stale).
for name in sorted(legacy):
    if name not in committed:
        fail("%s: legacy entry has no committed PNG" % name)
    entry = legacy[name] or {}
    reason = entry.get("reason", "") if isinstance(entry, dict) else ""
    if not reason.strip():
        fail("%s: legacy entry has no reason" % name)
    if name in declared:
        fail("%s: legacy entry has a producing capture line - remove the legacy entry" % name)

if failures:
    print("FAIL: screenshot manifest is out of sync (%d problem(s)):" % len(failures))
    for message in failures:
        print("  - %s" % message)
    sys.exit(1)

print(
    "PASS: %d committed frame(s), %d produced by a line, %d reasoned legacy."
    % (len(committed), len(committed) - len(legacy), len(legacy))
)
for name in sorted(legacy):
    reason = legacy[name].get("reason", "") if isinstance(legacy[name], dict) else ""
    print("  legacy: %s - %s" % (name, reason))
sys.exit(0)
PYEOF

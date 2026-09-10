#!/usr/bin/env python3
"""Screenshot manifest helper (RV.176 + PR.28).

`design/screenshots/manifest.json` records, for every committed frame, the
runtime, device and commit it was last captured on. The runtime matters because
snapshot baselines recorded on iOS 26.5 are not valid for iOS 18 (CLAUDE.md), so
a frame's runtime is part of what it proves.

Two sections, and the difference is deliberate:

  frames  - written by `capture-screenshots.sh`, one entry per frame the script
            produces (`capture` and `alias_shot` alike). Overwritten on each run
            for the frames that run produced; entries for frames a FILTER did
            not touch are preserved, so a filtered run updates rather than
            clobbers the record.
  legacy  - hand-maintained, for a committed frame that no capture line can
            reproduce because the code that produced it is gone. Each entry
            carries a reason and must be referenced by a doc, the site or the
            store build. This is the narrow exception, not a dumping ground;
            `check-screenshot-manifest.sh` enforces the reference.

Usage:
  screenshot-manifest.py merge <manifest.json> <entries.tsv>
      entries.tsv lines are `name<TAB>runtime<TAB>device<TAB>commit`.
  screenshot-manifest.py keys <manifest.json>
      prints `frame <name>` and `legacy <name>` lines, for shell consumers.
"""

import json
import os
import sys


def load(path):
    if not os.path.exists(path):
        return {"frames": {}, "legacy": {}}
    try:
        with open(path, encoding="utf-8") as handle:
            data = json.load(handle)
    except (ValueError, OSError):
        return {"frames": {}, "legacy": {}}
    data.setdefault("frames", {})
    data.setdefault("legacy", {})
    return data


def save(path, data):
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    with open(path, "w", encoding="utf-8") as handle:
        json.dump(data, handle, indent=2, sort_keys=True)
        handle.write("\n")


def merge(manifest_path, tsv_path):
    data = load(manifest_path)
    frames = data["frames"]
    with open(tsv_path, encoding="utf-8") as handle:
        for line in handle:
            line = line.rstrip("\n")
            if not line:
                continue
            name, runtime, device, commit = line.split("\t")
            frames[name] = {
                "runtime": runtime,
                "device": device,
                "commit": commit,
            }
            # A frame the script now produces is no longer a legacy exception.
            data["legacy"].pop(name, None)
    data["frames"] = frames
    save(manifest_path, data)
    return 0


def keys(manifest_path):
    data = load(manifest_path)
    for name in sorted(data["frames"]):
        print("frame\t%s" % name)
    for name in sorted(data["legacy"]):
        print("legacy\t%s" % name)
    return 0


def main(argv):
    if len(argv) < 2:
        sys.stderr.write(__doc__)
        return 2
    command = argv[1]
    if command == "merge":
        if len(argv) != 4:
            sys.stderr.write("usage: screenshot-manifest.py merge <manifest.json> <entries.tsv>\n")
            return 2
        return merge(argv[2], argv[3])
    if command == "keys":
        if len(argv) != 3:
            sys.stderr.write("usage: screenshot-manifest.py keys <manifest.json>\n")
            return 2
        return keys(argv[2])
    sys.stderr.write("unknown command: %s\n" % command)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))

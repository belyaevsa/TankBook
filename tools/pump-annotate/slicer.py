"""The resident slicer behind the annotator's live overlay.

`pump-read --slice-serve` keeps one process up, reads a JSON request per stdin
line and answers with the slicer's cells per window - no model, the last decoded
image cached - so a reply costs the warp and the column profiles (about 20 ms
for three windows on an optimised build, 600 ms on a plain debug one). This
module owns that process: it starts it lazily, serialises requests (one in
flight; a drag's later request replaces an earlier one that has not started),
and restarts it after a crash.

The optimised binary is built with `swift build --product pump-read -Xswiftc -O
--scratch-path .build/opt` in `ios/` (inside `.build`, so lint and git ignore it) - the debug configuration keeps
`@testable import` working and `-O` makes the pixel loops fast; `server.py`
builds it on first use when it is missing.
"""
from __future__ import annotations

import json
import subprocess
import threading
import time
from pathlib import Path


class ResidentSlicer:
    def __init__(self, binary: Path, build: "callable[[], bool] | None" = None, cwd: Path | None = None):
        self.binary = binary
        self.build = build
        self.cwd = cwd
        self.proc: subprocess.Popen | None = None
        self.lock = threading.Lock()
        self.pending: dict | None = None      # the latest request waiting its turn
        self.pending_cv = threading.Condition(self.lock)
        self.busy = False
        self.last_error: str | None = None

    def _ensure(self) -> bool:
        if self.proc and self.proc.poll() is None:
            return True
        if not self.binary.exists() and self.build and not self.build():
            self.last_error = "pump-read did not build"
            return False
        try:
            self.proc = subprocess.Popen([str(self.binary), "--slice-serve"], cwd=self.cwd,
                                         stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                                         text=True, bufsize=1)
        except OSError as exc:
            self.last_error = str(exc)
            return False
        return True

    def slice(self, request: dict, timeout: float = 5.0) -> dict:
        """Answer one request. While another request is running, a newer one
        waits and an older waiter is superseded (its caller gets
        `{"superseded": true}`), so a fast drag never queues up stale work."""
        my = {"request": request}
        with self.lock:
            if self.pending is not None:
                self.pending["superseded"] = True
                self.pending_cv.notify_all()
            self.pending = my
            while self.busy and not my.get("superseded"):
                self.pending_cv.wait(timeout=timeout)
            if my.get("superseded"):
                return {"superseded": True}
            self.pending = None
            self.busy = True
        try:
            return self._run(request, timeout)
        finally:
            with self.lock:
                self.busy = False
                self.pending_cv.notify_all()

    def _run(self, request: dict, timeout: float) -> dict:
        if not self._ensure():
            return {"error": self.last_error or "slicer unavailable"}
        assert self.proc and self.proc.stdin and self.proc.stdout
        started = time.time()
        try:
            self.proc.stdin.write(json.dumps(request) + "\n")
            self.proc.stdin.flush()
            line = self.proc.stdout.readline()
        except (BrokenPipeError, OSError) as exc:
            self.proc = None
            return {"error": f"slicer died: {exc}"}
        if not line:
            self.proc = None
            return {"error": "slicer exited"}
        try:
            reply = json.loads(line)
        except json.JSONDecodeError:
            return {"error": "slicer replied with something that is not JSON"}
        reply["roundTripMs"] = int((time.time() - started) * 1000)
        return reply

    def stop(self) -> None:
        if self.proc and self.proc.poll() is None:
            try:
                self.proc.stdin.close()
                self.proc.wait(timeout=2)
            except Exception:
                self.proc.kill()
        self.proc = None

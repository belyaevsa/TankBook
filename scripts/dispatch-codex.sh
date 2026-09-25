#!/usr/bin/env bash
# Dispatch one brief to a Codex agent (the OpenAI CLI), the same shape as
# scripts/dispatch.sh for opencode: brief + standing preamble on stdin, launched
# detached with its own log, health-checked by log bytes, retried ONCE.
#
#   scripts/dispatch-codex.sh <task-id> [model]     # model defaults to gpt-5.6-sol
#
# Prints "PID=<pid>" on success so the orchestrator can arm a monitor on it.
# The agent's final message also lands in /tmp/agentlogs/<id>.last.md.
#
# Sandbox: none, and approvals bypassed - the same standing as `opencode run
# --auto`; the brief's fences and the orchestrator's verification are the
# controls (agents/briefs/README.md). xcodebuild writes DerivedData outside the
# workspace, which is why workspace-write would not do.
set -u
id="${1:?task id}"; model="${2:-gpt-5.6-sol}"
root="$(cd "$(dirname "$0")/.." && pwd)"
brief="$root/agents/briefs/$id.md"; pre="$root/agents/briefs/PREAMBLE.md"
[ -f "$brief" ] || { echo "no brief at $brief" >&2; exit 2; }
mkdir -p /tmp/agentlogs
launch() {
  local log="/tmp/agentlogs/$id-codex.log"
  [ -f "$log" ] && mv "$log" "$log.$(date +%H%M%S).prev"
  rm -f "/tmp/agentlogs/$id.last.md"
  { cat "$brief"; printf '\n\n---\n\n'; cat "$pre"; } | nohup codex exec \
    -m "$model" -C "$root" --dangerously-bypass-approvals-and-sandbox \
    -o "/tmp/agentlogs/$id.last.md" - > "$log" 2>&1 &
  echo $!
}
for attempt in 1 2; do
  pid=$(launch); sleep 60
  bytes=$(wc -c < "/tmp/agentlogs/$id-codex.log" | tr -d ' ')
  if kill -0 "$pid" 2>/dev/null && [ "$bytes" -gt 2000 ]; then
    echo "attempt $attempt healthy: $bytes bytes in 60 s"; echo "PID=$pid"; exit 0
  fi
  # A short task can finish inside the first minute: an exited run that wrote its final message
  # is done, not dead - retrying it would run the task twice.
  if ! kill -0 "$pid" 2>/dev/null && [ -s "/tmp/agentlogs/$id.last.md" ] && [ "$bytes" -gt 2000 ]; then
    echo "attempt $attempt finished within 60 s: $bytes bytes, final message in /tmp/agentlogs/$id.last.md"
    echo "PID=$pid"; exit 0
  fi
  echo "attempt $attempt dead or silent ($bytes bytes); killing $pid" >&2
  kill "$pid" 2>/dev/null; sleep 2
done
echo "both attempts dead" >&2; exit 1

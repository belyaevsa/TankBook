#!/usr/bin/env bash
# Dispatch one brief to an opencode agent: concatenate the brief with the standing
# preamble, launch detached, health-check by log bytes at 60 s, retry ONCE on a dead
# run (about one dispatch in four comes up with no network and writes nothing).
#
#   scripts/dispatch.sh <task-id> [model]      # model defaults to deepseek/deepseek-v4-flash
#
# Prints "PID=<pid>" on success so the orchestrator can arm a monitor on it.
set -u
id="${1:?task id}"; model="${2:-deepseek/deepseek-v4-flash}"
root="$(cd "$(dirname "$0")/.." && pwd)"
brief="$root/agents/briefs/$id.md"; pre="$root/agents/briefs/PREAMBLE.md"
[ -f "$brief" ] || { echo "no brief at $brief" >&2; exit 2; }
mkdir -p /tmp/agentlogs
launch() {
  local log="/tmp/agentlogs/$id.log"
  [ -f "$log" ] && mv "$log" "$log.$(date +%H%M%S).prev"
  nohup opencode run --auto --thinking -m "$model" --title "$id" \
    "$(cat "$brief"; printf '\n\n---\n\n'; cat "$pre")" > "$log" 2>&1 < /dev/null &
  echo $!
}
for attempt in 1 2; do
  pid=$(launch); sleep 60
  bytes=$(wc -c < "/tmp/agentlogs/$id.log" | tr -d ' ')
  if kill -0 "$pid" 2>/dev/null && [ "$bytes" -gt 8000 ]; then
    echo "attempt $attempt healthy: $bytes bytes in 60 s"; echo "PID=$pid"; exit 0
  fi
  echo "attempt $attempt dead or silent ($bytes bytes); killing $pid" >&2
  kill "$pid" 2>/dev/null; sleep 2
done
echo "both attempts dead - provider down?" >&2; exit 1

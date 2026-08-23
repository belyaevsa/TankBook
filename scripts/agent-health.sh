#!/usr/bin/env bash
# Is a dispatched opencode agent working, or silently wedged?
#
# Usage: scripts/agent-health.sh <title> <logfile>
#   e.g. scripts/agent-health.sh P1.5 /path/to/p15-run.log
#
# Run it ~5 minutes after every dispatch (CLAUDE.md -> Conventions). Roughly one
# dispatch in four on this project has come up dead: the process exists, holds
# NO network connection, burns almost no CPU and never writes a byte of log. It
# stays that way indefinitely - one such run sat for six hours - so without a
# check you lose the whole slot. Both times, an immediate re-dispatch of the
# same brief worked, so this is provider flakiness, not a bad brief: kill and
# retry rather than rewriting anything.
#
# The signals, in order of how fast they tell you:
#   log bytes   - decisive within ~60s. A healthy run writes KBs immediately;
#                 a wedged one is still at 0 after 25 minutes.
#   connections - a working agent holds 1+ TCP connections to the provider,
#                 EXCEPT while it waits on a build (xcodebuild test is ~4 min
#                 of legitimate zero). Never judge on this alone.
#   CPU time    - climbs steadily when working. Slow to read but hard to fake.
#
# Log freshness on its own means nothing: nothing is written during model
# inference, so multi-minute quiet stretches are normal on a healthy run.

set -uo pipefail

TITLE="${1:?usage: agent-health.sh <title> <logfile>}"
LOG="${2:?usage: agent-health.sh <title> <logfile>}"

# Anchor on the opencode binary. A bare `pgrep -f "title <id>"` also matches
# the shell wrapper running THIS script - its argv contains the title too - and
# `head -1` then reports the wrapper's ~0 CPU as a wedged agent. Same trap
# HANDOVER.md warns about for wait-loops.
PID="$(pgrep -f "^opencode run.*--title ${TITLE}( |$)" | head -1)"

if [ -z "${PID}" ]; then
    echo "EXITED    ${TITLE} is not running - it finished, or it was killed."
    echo "          Verify its work before assuming success."
    exit 2
fi

ELAPSED="$(ps -o etime= -p "${PID}" | tr -d ' ')"
CPU="$(ps -o time= -p "${PID}" | tr -d ' ')"
STAT="$(ps -o stat= -p "${PID}" | tr -d ' ')"
CONNS="$(lsof -p "${PID}" 2>/dev/null | grep -cE 'TCP' | head -1)"
CONNS="${CONNS:-0}"
BYTES="$(stat -f %z "${LOG}" 2>/dev/null || echo 0)"
# grep -c prints "0" AND exits 1 when there are no matches, so `|| echo 0`
# would print a second zero. Take the first line and ignore the status.
WRITES="$(grep -c 'Wrote file successfully' "${LOG}" 2>/dev/null | head -1)"
WRITES="${WRITES:-0}"
CPU_SECS="$(awk -F: '{ if (NF==3) print $1*3600+$2*60+$3; else print $1*60+$2 }' <<<"${CPU}")"

echo "${TITLE}  pid=${PID}  elapsed=${ELAPSED}  cpu=${CPU}  stat=${STAT}"
echo "          log=${BYTES}B  writes=${WRITES}  connections=${CONNS}"

# The decisive test. An agent past its first minute with an empty log has never
# recovered on this project.
if [ "${BYTES}" -eq 0 ]; then
    echo
    echo "WEDGED    Empty log. Kill it and re-dispatch the same brief:"
    echo "          pkill -f 'title ${TITLE}'"
    exit 1
fi

# Corroborating check: real work costs CPU. Under ~30s of CPU after 5 minutes
# means it is not thinking, whatever the log says.
if [ "${CPU_SECS%.*}" -lt 30 ] && [ "${CONNS}" -eq 0 ]; then
    echo
    echo "SUSPECT   Low CPU and no connection. If it is not mid-xcodebuild,"
    echo "          re-run this in a minute; if unchanged, treat it as wedged."
    exit 1
fi

echo
echo "WORKING   Log is growing and CPU is accumulating."
exit 0

#!/bin/bash
# Launches Sitch and fails if it exits within a few seconds, to catch crashes at launch.
# Usage: scripts/smoke-test.sh PATH_TO_BINARY [SECONDS]
set -uo pipefail

BINARY="${1:?usage: $0 PATH_TO_BINARY [SECONDS]}"
WAIT_SECONDS="${2:-10}"

"$BINARY" >/dev/null 2>&1 &
PID=$!
sleep "$WAIT_SECONDS"

if kill -0 "$PID" 2>/dev/null; then
    kill "$PID"
    echo "Sitch was still running after ${WAIT_SECONDS}s"
else
    STATUS=0
    wait "$PID" || STATUS=$?
    echo "Sitch exited during launch with status $STATUS" >&2
    exit 1
fi

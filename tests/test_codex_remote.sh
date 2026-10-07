#!/usr/bin/env bash
set -euo pipefail
repo=$(cd -- "$(dirname -- "$0")/.." && pwd -P)
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
mkdir "$fixture/bin"
export REMOTE_LOG="$fixture/log" REMOTE_MODE=normal
cat > "$fixture/bin/codex" <<'MOCK'
#!/bin/bash
printf '%s\n' "$*" >> "$REMOTE_LOG"
case "$*" in
    'login status') [[ $REMOTE_MODE != login-failure ]] ;;
    *'remote-control start') [[ $REMOTE_MODE != start-failure ]] ;;
    'remote-control stop') [[ $REMOTE_MODE != stop-failure ]] ;;
    *) exit 2 ;;
esac
MOCK
cat > "$fixture/bin/timeout" <<'MOCK'
#!/bin/bash
[[ $1 == --kill-after=2s && $2 == 10s ]] || exit 2
shift 2
if [[ $REMOTE_MODE == timeout ]]; then
    printf 'stop-timeout\n' >> "$REMOTE_LOG"
    exit 124
fi
exec "$@"
MOCK
cat > "$fixture/bin/touch" <<'MOCK'
#!/bin/bash
[[ $1 == /tmp/devcontainer-codex-remote.ready ]] || exit 2
printf 'ready\n' >> "$REMOTE_LOG"
MOCK
chmod +x "$fixture/bin/"*
export PATH="$fixture/bin:$PATH"
for REMOTE_MODE in login-failure start-failure; do
    export REMOTE_MODE
    : > "$REMOTE_LOG"
    if /bin/bash "$repo/scripts/codex-remote.sh" >"$fixture/output" 2>&1; then exit 1; fi
    if grep -q '^ready$' "$REMOTE_LOG"; then exit 1; fi
    if [[ $REMOTE_MODE == start-failure ]]; then [[ $(tail -n 1 "$REMOTE_LOG") == 'remote-control stop' ]]; fi
done
for REMOTE_MODE in normal stop-failure timeout; do
    export REMOTE_MODE
    : > "$REMOTE_LOG"
    /bin/bash "$repo/scripts/codex-remote.sh" </dev/null >"$fixture/output" 2>&1 &
    pid=$!
    ready=0
    for ((i=0; i<100; i++)); do
        if grep -q '^ready$' "$REMOTE_LOG"; then ready=1; break; fi
        sleep 0.02
    done
    if (( ! ready )); then kill -TERM "$pid"; wait "$pid" || true; exit 1; fi
    # EOF does not end the detached server, and startup never issues a code.
    kill -0 "$pid"
    if grep -q 'remote-control pair' "$REMOTE_LOG"; then exit 1; fi
    kill -TERM "$pid"
    status=0
    wait "$pid" || status=$?
    [[ $status == 143 ]]
    if [[ $REMOTE_MODE == timeout ]]; then grep -q 'did not stop cleanly' "$fixture/output"
    else [[ $(tail -n 1 "$REMOTE_LOG") == 'remote-control stop' ]]; fi
done
printf 'Detached server startup, EOF survival, failure cleanup, and bounded shutdown passed\n'

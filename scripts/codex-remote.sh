#!/usr/bin/env bash
set -euo pipefail

wait_pid=
started=0
cleanup() {
    status=$?
    trap - EXIT INT TERM HUP
    if [[ -n $wait_pid ]]; then kill -TERM "$wait_pid" 2>/dev/null || true; fi
    if (( started )); then
        if ! timeout --kill-after=2s 10s codex remote-control stop; then
            printf 'error: Codex remote control did not stop cleanly; the container will exit\n' >&2
            if (( status == 0 )); then status=1; fi
        fi
    fi
    exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

codex login status
devcontainer-codex-prepare
# Also attempt cleanup if startup fails after partially creating the daemon.
started=1
codex -c 'sandbox_mode="danger-full-access"' \
    -c 'approval_policy="on-request"' remote-control start
touch /tmp/devcontainer-codex-remote.ready
# Pairing is requested through docker exec, never recorded in container logs.
while :; do
    sleep 3600 &
    wait_pid=$!
    wait "$wait_pid"
    wait_pid=
done

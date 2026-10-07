#!/usr/bin/env bash
set -euo pipefail
repo=$(cd -- "$(dirname -- "$0")/.." && pwd -P)
docker=${DOCKER:-docker}
image=${IMAGE_REF:-devcontainer-images:ubuntu-26.04}
name="devcontainer-remote-smoke-$$-$RANDOM"
cleanup() { "$docker" rm -f "$name" >/dev/null 2>&1 || true; }
trap cleanup EXIT
wrapper=$(cat "$repo/scripts/codex-remote.sh")
# Use a fake CLI so the test neither authenticates nor registers a remote host.
harness=$(cat <<'HARNESS'
set -euo pipefail
test "$(id -u)" != 0
fixture=$(mktemp -d)
export PATH="$fixture:$PATH"
cat > "$fixture/codex" <<'MOCK'
#!/bin/bash
case "$*" in
    'login status') exit 0 ;;
    *'remote-control start') printf 'smoke-ready\n' ;;
    'remote-control stop') printf 'smoke-stopped\n' ;;
    *) exit 2 ;;
esac
MOCK
chmod +x "$fixture/codex"
exec bash -c "$1"
HARNESS
)
# Start with no interactive stdin, then deliver SIGTERM through Docker's init.
"$docker" run -d --name "$name" --init --network none --cap-drop ALL \
    --security-opt=no-new-privileges "$image" bash -c "$harness" -- "$wrapper" >/dev/null
ready=0
for ((i=0; i<100; i++)); do
    output=$("$docker" logs "$name" 2>&1)
    if [[ $output == *smoke-ready* ]]; then ready=1; break; fi
    sleep 0.1
done
if (( ! ready )); then printf 'FAIL: remote wrapper did not start\n' >&2; exit 1; fi
"$docker" exec "$name" test -f /tmp/devcontainer-codex-remote.ready
[[ $("$docker" inspect --format '{{.State.Running}}' "$name") == true ]]
"$docker" stop --time 15 "$name" >/dev/null
output=$("$docker" logs "$name" 2>&1)
[[ $output == *smoke-stopped* ]]
[[ $("$docker" inspect --format '{{.State.ExitCode}}' "$name") == 143 ]]
printf 'Detached container startup and SIGTERM remote cleanup passed (mock CLI, no credentials)\n'

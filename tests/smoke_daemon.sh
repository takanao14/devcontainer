#!/usr/bin/env bash
# Commands are evaluated inside the container.
# shellcheck disable=SC2016

set -euo pipefail
image=${IMAGE_REF:?IMAGE_REF is required}
docker=${DOCKER:-docker}
identifier="devcontainer-ci-$(date +%s)-$$-$RANDOM"
project="$identifier-project"
reference="$identifier-reference"
cleanup() {
    "$docker" volume rm "$project" "$reference" >/dev/null 2>&1 || true
}
trap cleanup EXIT
# Named volumes work when the runner job and Docker daemon have separate filesystems.
"$docker" run --rm --network none --cap-drop ALL --security-opt no-new-privileges \
    --mount "type=volume,source=$reference,target=/home/developer/.claude" \
    "$image" bash -ec 'printf reference > "$CLAUDE_CONFIG_DIR/fixture.txt"'
"$docker" run --rm --network none --cap-drop ALL --security-opt no-new-privileges \
    --mount "type=volume,source=$project,target=/home/developer/.codex" \
    --mount "type=volume,source=$reference,target=/home/developer/.claude,readonly" \
    "$image" bash -ec '
      test "$(id -u)" = 1000
      test ! -S /var/run/docker.sock
      test -z "$(ip route)"
      if sudo -n true 2>/dev/null; then exit 1; fi
      if touch "$CLAUDE_CONFIG_DIR/forbidden" 2>/dev/null; then exit 1; fi
      test "$(cat "$CLAUDE_CONFIG_DIR/fixture.txt")" = reference
      printf persisted > "$CODEX_HOME/smoke.txt"
      codex --sandbox danger-full-access --ask-for-approval on-request --help >/dev/null
      claude --permission-mode default --version
    '
"$docker" run --rm --network none --cap-drop ALL --security-opt no-new-privileges \
    --mount "type=volume,source=$project,target=/home/developer/.codex" \
    "$image" bash -ec 'test "$(cat "$CODEX_HOME/smoke.txt")" = persisted'
printf 'Daemon-side permissions, read-only volume, CLI options, and persistence passed\n'

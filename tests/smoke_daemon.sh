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
      mkdir -p "$CODEX_HOME/packages/app-server-daemon/old/bin" "$CODEX_HOME/app-server-daemon"
      printf "#!/bin/sh\nexit 99\n" > "$CODEX_HOME/packages/app-server-daemon/old/bin/codex"
      chmod +x "$CODEX_HOME/packages/app-server-daemon/old/bin/codex"
      ln -s old "$CODEX_HOME/packages/app-server-daemon/current"
      printf "{\"shutdownGraceSeconds\":3,\"updater\":{\"autoUpdateEnabled\":true,\"updateIntervalMinutes\":42}}\n" > "$CODEX_HOME/app-server-daemon/settings.json"
      devcontainer-codex-prepare
      test "$(readlink "$CODEX_HOME/packages/app-server-daemon/current")" = /usr/local/share/devcontainer-images/codex-package
      jq -e ".updater.autoUpdateEnabled == false and .updater.updateIntervalMinutes == 42 and .shutdownGraceSeconds == 3" "$CODEX_HOME/app-server-daemon/settings.json" >/dev/null
      test -f "$CODEX_HOME/packages/app-server-daemon/old/bin/codex"
      codex app-server daemon start
      trap "codex app-server daemon stop" EXIT
      version=$(codex app-server daemon version)
      printf "%s\n" "$version" | jq -e --arg expected "$(codex --version | cut -d " " -f 2)" ".managedCodexVersion == \$expected and .appServerVersion == \$expected and .cliVersion == \$expected" >/dev/null
      test -z "$(find "$CODEX_HOME/app-server-daemon" -name "*updater.pid")"
      codex --sandbox danger-full-access --ask-for-approval on-request --help >/dev/null
      claude --permission-mode default --version
    '
"$docker" run --rm --network none --cap-drop ALL --security-opt no-new-privileges \
    --mount "type=volume,source=$project,target=/home/developer/.codex" \
    "$image" bash -ec '
      test "$(cat "$CODEX_HOME/smoke.txt")" = persisted
      devcontainer-codex-prepare
      test "$(readlink -f "$CODEX_HOME/packages/app-server-daemon/current/bin/codex")" = "$(readlink -f /usr/local/share/devcontainer-images/codex-package/bin/codex)"
      jq -e ".updater.autoUpdateEnabled == false" "$CODEX_HOME/app-server-daemon/settings.json" >/dev/null
    '
printf 'Daemon image package, disabled updater, settings persistence, and permissions passed\n'

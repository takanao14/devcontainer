#!/usr/bin/env bash
set -euo pipefail
repo=$(cd -- "$(dirname -- "$0")/.." && pwd -P)
fixture=$(mktemp -d)
fixture=$(cd -- "$fixture" && pwd -P)
export PROJECT="$fixture/project with spaces" MOUNTS="$fixture/mounts.yaml" NETWORK=none DRY_RUN=0
mkdir -p "$PROJECT" "$fixture/reference"
printf reference > "$fixture/reference/fixture.txt"
printf 'readOnly: ["%s"]\n' "$fixture/reference" > "$MOUNTS"
if command -v sha256sum >/dev/null; then
    identifier=$(printf '%s' "$PROJECT" | sha256sum)
else
    identifier=$(printf '%s' "$PROJECT" | shasum -a 256)
fi
identifier=${identifier:0:24}
cleanup() {
    for cli in codex claude; do
        "${DOCKER:-docker}" volume rm "devcontainer-$identifier-$cli" >/dev/null 2>&1 || true
    done
    rm -rf "$fixture"
}
trap cleanup EXIT
bash "$repo/scripts/launch.sh" shell -- -ec '
    test "$(id -u)" = 1000
    test ! -S /var/run/docker.sock
    test "$DISABLE_UPDATES" = 1
    if sudo -n true 2>/dev/null; then exit 1; fi
    if touch /workspace/reference/forbidden 2>/dev/null; then exit 1; fi
    test "$(cat /workspace/reference/fixture.txt)" = reference
    test -z "$(ip route)"
    printf changed > host-edit.txt
    printf codex-state > "$CODEX_HOME/smoke.txt"
    printf claude-state > "$CLAUDE_CONFIG_DIR/smoke.txt"
    codex --sandbox danger-full-access --ask-for-approval on-request --help >/dev/null
    claude --permission-mode default --version
'
[[ $(cat "$PROJECT/host-edit.txt") == changed && ! -e $fixture/reference/forbidden ]]
bash "$repo/scripts/launch.sh" shell -- -ec '
    test "$(cat "$CODEX_HOME/smoke.txt")" = codex-state
    test "$(cat "$CLAUDE_CONFIG_DIR/smoke.txt")" = claude-state
'
printf 'Container permissions, read-only mounts, host edits, CLI options, and state persistence passed\n'

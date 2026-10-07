#!/usr/bin/env bash
set -euo pipefail
repo=$(cd -- "$(dirname -- "$0")/.." && pwd -P)
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
fixture=$(cd -- "$fixture" && pwd -P)
mkdir -p "$fixture/main project" "$fixture/reference" "$fixture/parent/main project" "$fixture/main project/child"
cat > "$fixture/docker" <<'MOCK'
#!/usr/bin/env bash
jq -n --args '$ARGS.positional' -- "$@"
MOCK
chmod +x "$fixture/docker"
export PROJECT="$fixture/main project" DOCKER="$fixture/docker" NETWORK=none DRY_RUN=0
config="$fixture/mounts.yaml"
export MOUNTS="$config"
reject() {
    printf '%s\n' "$1" > "$config"
    if bash "$repo/scripts/launch.sh" shell >/dev/null 2>&1; then
        printf 'FAIL: accepted invalid config: %s\n' "$1" >&2
        exit 1
    fi
}
for invalid in '[]' 'null' 'unknown: []' 'readOnly: hello' 'readOnly: [42]' 'readOnly: [relative]' 'readOnly: [/missing/path]' 'readOnly: [' 'readOnly: null'; do
    reject "$invalid"
done
reject $'readOnly: []\nreadOnly: []'
reject $'readOnly: []\n---\nreadWrite: []'
reject "readOnly: [\"$PROJECT\"]"
ln -s "$PROJECT" "$fixture/alias"
reject "readOnly: [\"$fixture/alias\"]"
reject "readOnly: [\"$fixture/parent/main project\"]"
reject "readOnly: [\"$PROJECT/child\"]"
reject "readOnly: [\"$fixture\"]"
reject "readOnly: [\"$fixture/reference\"]
readWrite: [\"$fixture/reference\"]"
reject 'readOnly: ["/path\nwith-newline"]'
reject '{1: []}'
printf 'readOnly: ["%s"]\n' "$fixture/reference" > "$config"
args=$(bash "$repo/scripts/launch.sh" codex)
printf '%s' "$args" | jq -e --arg source "source=$PROJECT" '
  index("--cap-drop=ALL") != null and
  index("--security-opt=no-new-privileges") != null and
  any(.[]; contains($source)) and
  any(.[]; endswith(",readonly")) and
  .[-5:] == ["codex", "--sandbox", "danger-full-access", "--ask-for-approval", "on-request"]
' >/dev/null
first=$(printf '%s' "$args" | jq -c '[.[] | select(startswith("type=volume"))]')
second=$(bash "$repo/scripts/launch.sh" shell | jq -c '[.[] | select(startswith("type=volume"))]')
[[ $first == "$second" ]]
third=$(PROJECT="$fixture/parent/main project" MOUNTS="" bash "$repo/scripts/launch.sh" shell | jq -c '[.[] | select(startswith("type=volume"))]')
[[ $first != "$third" ]]
mkdir -p "$fixture/comma,quote\"/project"
args=$(PROJECT="$fixture/comma,quote\"/project" MOUNTS="" bash "$repo/scripts/launch.sh" shell)
printf '%s' "$args" | jq -e 'any(.[]; contains("quote\"\"/project"))' >/dev/null
if bash "$repo/scripts/launch.sh" codex-remote >/dev/null 2>&1; then
    printf 'FAIL: accepted remote control without networking\n' >&2
    exit 1
fi
dry=$(NETWORK=bridge DRY_RUN=1 bash "$repo/scripts/launch.sh" codex-remote)
eval "set -- $dry"
args=$(jq -n --args '$ARGS.positional' -- "$@")
printf '%s' "$args" | jq -e '
  .[index("--network") + 1] == "bridge" and
  .[-3:-1] == ["bash", "-c"] and
  index("--detach") != null and
  (.[-1] | contains("approval_policy=\"on-request\"") and contains("remote-control stop") and
    (contains("remote-control pair") | not))
' >/dev/null
remote_volumes=$(printf '%s' "$args" | jq -c '[.[] | select(startswith("type=volume"))]')
shell_volumes=$(bash "$repo/scripts/launch.sh" shell | jq -c '[.[] | select(startswith("type=volume"))]')
[[ $remote_volumes == "$shell_volumes" ]]
printf 'Launcher schema, duplicate/overlap/collision checks, quoting, and stable volumes passed\n'

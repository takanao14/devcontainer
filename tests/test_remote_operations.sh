#!/usr/bin/env bash
set -euo pipefail
repo=$(cd -- "$(dirname -- "$0")/.." && pwd -P)
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
mkdir "$fixture/project" "$fixture/reference"
export PROJECT="$fixture/project" NETWORK=bridge DRY_RUN=0 MOUNTS=""
export MOCK_STATE="$fixture/state" MOCK_CALLS="$fixture/calls" MOCK_MODE=normal
cat > "$fixture/docker" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
jq -cn --args '$ARGS.positional' -- "$@" >> "$MOCK_CALLS"
case "$1" in
    container)
        if [[ -f $MOCK_STATE ]]; then jq -r '.[0].Name' "$MOCK_STATE"; fi
        ;;
    inspect)
        [[ -f $MOCK_STATE ]] || exit 1
        if [[ $2 == --format ]]; then
            [[ $MOCK_MODE != startup-failure ]] || { printf 'false\n'; exit; }
            printf 'true\n'
        else cat "$MOCK_STATE"; fi
        ;;
    run)
        [[ $MOCK_MODE != run-failure ]] || exit 1
        labels='{}'
        name=
        shift
        while (( $# )); do
            case "$1" in
                --label)
                    key=${2%%=*}; value=${2#*=}
                    labels=$(printf '%s' "$labels" | jq --arg key "$key" --arg value "$value" '.[$key]=$value')
                    shift
                    ;;
                --name) name=$2; shift ;;
            esac
            shift
        done
        jq -n --argjson labels "$labels" --arg name "$name" '[{Name:$name, Config:{Labels:$labels}, State:{Running:true,Status:"running"}}]' > "$MOCK_STATE"
        printf 'mock-id\n'
        ;;
    exec)
        [[ $MOCK_MODE != startup-failure ]] || exit 1
        if [[ ${3:-} == timeout && $MOCK_MODE == stop-failure ]]; then exit 1; fi
        ;;
    stop) rm -f "$MOCK_STATE" ;;
    *) exit 2 ;;
esac
MOCK
chmod +x "$fixture/docker"
export DOCKER="$fixture/docker"
launch() { bash "$repo/scripts/launch.sh" "$1" > "$fixture/output" 2>&1; }
launch codex-remote-start
[[ -f $MOCK_STATE ]]
launch codex-remote-start
[[ $(jq -s '[.[] | select(.[0]=="run")] | length' "$MOCK_CALLS") == 1 ]]
launch codex-remote-shell
[[ -f $MOCK_STATE ]]
launch codex-remote-pair
jq -se 'any(.[]; .[0] == "exec" and .[-3:] == ["codex","remote-control","pair"])' "$MOCK_CALLS" >/dev/null
launch codex-remote-status
[[ $(cat "$fixture/output") == running ]]
if IMAGE_REF=changed-image launch codex-remote-start; then exit 1; fi
[[ -f $MOCK_STATE ]]
cp "$MOCK_STATE" "$fixture/saved"
jq '.[0].Config.Labels["devcontainer-images.role"]="unmanaged"' "$fixture/saved" > "$MOCK_STATE"
if launch codex-remote-stop; then exit 1; fi
[[ -f $MOCK_STATE ]]
cp "$fixture/saved" "$MOCK_STATE"
# Stop and inspection do not require the startup mount configuration.
MOUNTS=/missing/file launch codex-remote-stop
[[ ! -f $MOCK_STATE ]]
launch codex-remote-stop
launch codex-remote-status
[[ $(cat "$fixture/output") == stopped ]]
if launch codex-remote-pair; then exit 1; fi
for MOCK_MODE in startup-failure run-failure; do
    export MOCK_MODE
    if launch codex-remote-start; then exit 1; fi
    [[ ! -f $MOCK_STATE ]]
done
export MOCK_MODE=normal
launch codex-remote-start
export MOCK_MODE=stop-failure
if launch codex-remote-stop; then exit 1; fi
[[ ! -f $MOCK_STATE ]]
rg -q 'did not stop cleanly' "$fixture/output"
printf 'Remote reuse, independent pairing/shell/stop, ownership checks, and startup cleanup passed\n'

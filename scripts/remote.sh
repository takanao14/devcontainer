#!/usr/bin/env bash
# Sourced by launch.sh after the project identity has been validated.
# shellcheck disable=SC2154
remote_name="devcontainer-$identifier-codex-remote"

remote_print() { printf '%q ' "$@"; printf '\n'; }
remote_inspect() {
    local names
    names=$("$docker" container ls --all --format '{{.Names}}') || fail 'Cannot list remote containers'
    case $'\n'"$names"$'\n' in
        *$'\n'"$remote_name"$'\n'*) ;;
        *) return 1 ;;
    esac
    remote_info=$("$docker" inspect --type container "$remote_name") || fail 'Cannot inspect remote container'
    printf '%s' "$remote_info" | jq -e --arg project "$project" '
      .[0].Config.Labels["devcontainer-images.project"] == $project and
      .[0].Config.Labels["devcontainer-images.role"] == "codex-remote"
    ' >/dev/null || fail 'Container name belongs to an unmanaged container'
}

remote_operation() {
    local exists=0
    if [[ ${DRY_RUN:-0} != 1 ]]; then
        if remote_inspect; then exists=1; fi
        if [[ $action == codex-remote-status ]]; then
            if (( exists )); then printf '%s' "$remote_info" | jq -r '.[0].State.Status'
            else printf 'stopped\n'; fi
            return
        fi
        if (( ! exists )); then
            if [[ $action == codex-remote-stop ]]; then printf 'Already stopped\n'; return; fi
            fail 'Remote container is not running; use codex-remote-start first'
        fi
        printf '%s' "$remote_info" | jq -e '.[0].State.Running' >/dev/null || fail 'Remote container is not running'
    fi
    local operation=("$docker")
    case "$action" in
        codex-remote-stop)
            local stop_status=0
            local graceful=("$docker" exec "$remote_name" timeout --kill-after=2s 10s codex remote-control stop)
            if [[ ${DRY_RUN:-0} == 1 ]]; then remote_print "${graceful[@]}"
            elif ! "${graceful[@]}"; then
                printf 'error: Codex did not stop cleanly; stopping the container\n' >&2
                stop_status=1
            fi
            operation+=(stop --time 15 "$remote_name")
            ;;
        codex-remote-pair|codex-remote-shell)
            operation+=(exec -i)
            if [[ -t 0 && -t 1 ]]; then operation+=(-t); fi
            operation+=("$remote_name")
            if [[ $action == codex-remote-pair ]]; then operation+=(codex remote-control pair)
            else operation+=(bash); fi
            ;;
        codex-remote-status) operation+=(inspect --format '{{.State.Status}}' "$remote_name") ;;
    esac
    if [[ ${DRY_RUN:-0} == 1 ]]; then remote_print "${operation[@]}"
    else
        "${operation[@]}"
        if [[ $action == codex-remote-stop ]]; then return "$stop_status"; fi
    fi
}

remote_start() {
    local fingerprint created ready=0 i
    if command -v sha256sum >/dev/null; then
        fingerprint=$(printf '%s\0' "${cmd[@]}" | sha256sum)
    else fingerprint=$(printf '%s\0' "${cmd[@]}" | shasum -a 256); fi
    fingerprint=${fingerprint%% *}
    cmd=("${cmd[@]:0:2}" --label "devcontainer-images.config=$fingerprint" "${cmd[@]:2}")
    if [[ ${DRY_RUN:-0} == 1 ]]; then remote_print "${cmd[@]}"; return; fi
    if remote_inspect; then
        printf '%s' "$remote_info" | jq -e --arg fingerprint "$fingerprint" '
          .[0].State.Running and .[0].Config.Labels["devcontainer-images.config"] == $fingerprint
        ' >/dev/null || fail 'Remote configuration changed; stop the existing environment before starting it again'
        printf 'Already running: %s\n' "$remote_name"
        return
    fi
    created=$("${cmd[@]}") || fail 'Could not start remote container'
    remote_created=$created
    trap '"$docker" stop --time 15 "$remote_created" >/dev/null 2>&1 || true' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    trap 'exit 129' HUP
    # Use the ID on failure so cleanup never removes a replacement container.
    for ((i=0; i<300; i++)); do
        if "$docker" exec "$created" test -f /tmp/devcontainer-codex-remote.ready >/dev/null 2>&1; then ready=1; break; fi
        if [[ $("$docker" inspect --format '{{.State.Running}}' "$created" 2>/dev/null) != true ]]; then break; fi
        sleep 0.2
    done
    if (( ! ready )); then
        fail 'Codex remote startup failed; check project authentication with make shell'
    fi
    trap - EXIT INT TERM HUP
    printf 'Running: %s\n' "$remote_name"
}

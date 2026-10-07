#!/usr/bin/env bash
set -euo pipefail

fail() { printf 'error: %s\n' "$*" >&2; exit 2; }
canonical_directory() {
    [[ $1 == /* && -d $1 ]] || fail "Expected an existing absolute directory: $1"
    [[ $1 != *[$'\n\r\t']* ]] || fail 'Control characters are not supported in paths'
    resolved=$(cd -- "$1" && pwd -P)
    [[ $resolved != *[$'\n\r\t']* ]] || fail 'Control characters are not supported in paths'
    printf '%s\n' "$resolved"
}

command -v jq >/dev/null || fail 'jq is required'
action=${1:-shell}
if (( $# )); then shift; fi
case "$action" in shell|codex|claude) ;; *) fail "Unknown action: $action" ;; esac
if [[ ${1:-} == -- ]]; then shift; fi
project=$(canonical_directory "${PROJECT:-$PWD}")
paths=("$project")
readonly_modes=(false)
config=${MOUNTS:-}
if [[ -n $config ]]; then
    command -v yq >/dev/null || fail 'Mike Farah yq v4 is required for MOUNTS'
    [[ $(yq --version) == *'github.com/mikefarah/yq/'*'version v4.'* ]] || fail 'Mike Farah yq v4 is required'
    [[ -f $config ]] || fail "Missing mount configuration: $config"
    # Retain YAML entries until duplicate keys have been checked.
    entries=$(yq -o=json '{"kind": tag, "entries": to_entries}' -- "$config") || fail 'Invalid YAML mount configuration'
    data=$(printf '%s' "$entries" | jq -se '
      if length != 1 then error("Expected one YAML document") else .[0] end
      | if .kind != "!!map" then error("Expected a mapping") else .entries end
      | if (map(.key) | length) != (map(.key) | unique | length)
        then error("Duplicate YAML keys") else . end
      | if all(.[]; (.key == "readOnly" or .key == "readWrite") and
          (.value | type == "array") and
          (.value | all(.[]; type == "string" and (explode | all(.[]; . > 31 and . != 127)))))
        then from_entries else error("Expected readOnly/readWrite path lists") end
    ') || fail 'Invalid mount configuration'
    while IFS= read -r item; do
        path=$(printf '%s' "$item" | jq -r '.path')
        paths+=("$(canonical_directory "$path")")
        readonly_modes+=("$(printf '%s' "$item" | jq -r '.readonly')")
    done < <(printf '%s' "$data" | jq -c '
      (.readOnly // [])[] | {path: ., readonly: true}, empty
    '; printf '%s' "$data" | jq -c '(.readWrite // [])[] | {path: ., readonly: false}')
fi

for ((i=0; i<${#paths[@]}; i++)); do
    [[ ${paths[i]} != / ]] || fail 'The filesystem root cannot be mounted as a project'
    for ((j=0; j<i; j++)); do
        [[ ${paths[i]} != "${paths[j]}" ]] || fail "Duplicate mount: ${paths[i]}"
        [[ ${paths[i]##*/} != "${paths[j]##*/}" ]] || fail "Destination name collision: ${paths[i]##*/}"
        if [[ ${readonly_modes[i]} != "${readonly_modes[j]}" ]]; then
            [[ ${paths[i]} != "${paths[j]}/"* && ${paths[j]} != "${paths[i]}/"* ]] || fail 'Overlapping mounts with conflicting permissions'
        fi
    done
done
network=${NETWORK:-none}
case "$network" in none|bridge) ;; *) fail 'NETWORK must be none or bridge' ;; esac
if command -v sha256sum >/dev/null; then
    identifier=$(printf '%s' "$project" | sha256sum)
else
    identifier=$(printf '%s' "$project" | shasum -a 256)
fi
identifier=${identifier:0:24}
cmd=("${DOCKER:-docker}" run --rm --init --cap-drop=ALL --security-opt=no-new-privileges --network "$network" -i)
if [[ -t 0 && -t 1 ]]; then cmd+=(-t); fi
for ((i=0; i<${#paths[@]}; i++)); do
    path=${paths[i]}
    source_field="source=$path"
    target_field="target=/workspace/${path##*/}"
    # Docker --mount is CSV, independently of shell argument quoting.
    spec="type=bind,\"${source_field//\"/\"\"}\",\"${target_field//\"/\"\"}\""
    if [[ ${readonly_modes[i]} == true ]]; then spec+=,readonly; fi
    cmd+=(--mount "$spec")
done
for cli in codex claude; do
    cmd+=(--mount "type=volume,source=devcontainer-$identifier-$cli,target=/home/developer/.$cli")
done
cmd+=(--workdir "/workspace/${project##*/}" "${IMAGE_REF:-devcontainer-images:ubuntu-26.04}")
case "$action" in
    codex) cmd+=(codex --sandbox danger-full-access --ask-for-approval on-request) ;;
    claude) cmd+=(claude --permission-mode default) ;;
    shell) cmd+=(bash) ;;
esac
cmd+=("$@")
if [[ ${DRY_RUN:-0} == 1 ]]; then
    printf '%q ' "${cmd[@]}"
    printf '\n'
else
    exec "${cmd[@]}"
fi

#!/usr/bin/env bash
# shellcheck disable=SC2016
set -euo pipefail

kind=${1:-common}
mode=${2:-build}
case "$kind" in common|dns|go|rust) ;; *) echo 'KIND must be common, dns, go, or rust' >&2; exit 1 ;; esac
case "$mode" in build|rebuild) ;; *) echo 'UPDATE_MODE must be build or rebuild' >&2; exit 1 ;; esac
docker_command=${DOCKER:-docker}
make_command=${MAKE:-make}
image=${IMAGE:-devcontainer-images}
record_root=${BUILD_RECORD_DIR:-.local-builds}
commit=$(git rev-parse HEAD)
dirty=false
if test -n "$(git status --porcelain --untracked-files=normal)"; then dirty=true; fi
architecture=$("$docker_command" info --format '{{.Architecture}}')
case "$architecture" in aarch64|arm64) architecture=arm64 ;; x86_64|amd64) architecture=amd64 ;; *) echo "Unsupported Docker architecture: $architecture" >&2; exit 1 ;; esac
mkdir -p "$record_root"
record_dir=$(mktemp -d "$record_root/${commit:0:12}-${architecture}-XXXXXXXX")
build_id=${record_dir##*/}
base_ref="$image:local-$build_id"
selected_ref=$base_ref
if [[ $kind != common ]]; then selected_ref="$image:$kind-local-$build_id"; fi
status=failed
write_record() {
    jq -n --arg commit "$commit" --argjson dirty "$dirty" --arg architecture "$architecture" \
        --arg kind "$kind" --arg mode "$mode" --arg base "$base_ref" --arg selected "$selected_ref" \
        --arg status "$status" --arg id "$image_id" --rawfile versions "$record_dir/versions.txt" \
        '{commit:$commit,dirty:$dirty,architecture:$architecture,kind:$kind,mode:$mode,
          base_ref:$base,selected_ref:$selected,image_id:$id,status:$status,versions:$versions}' > "$record_dir/result.json"
}
image_id=''
: > "$record_dir/versions.txt"
trap write_record EXIT
export IMAGE_REF="$base_ref"
"$make_command" "$mode" IMAGE_REF="$base_ref"
"$make_command" verify-local IMAGE_REF="$base_ref"
if [[ $kind != common ]]; then
    variable="$(printf '%s' "$kind" | tr '[:lower:]' '[:upper:]')_IMAGE_REF"
    "$make_command" "build-$kind" IMAGE_REF="$base_ref" "$variable=$selected_ref"
    "$make_command" "verify-$kind" "$variable=$selected_ref"
    if [[ $kind == dns || $kind == rust ]]; then
        "$make_command" "verify-$kind-lock" "$variable=$selected_ref"
    fi
fi
image_id=$("$docker_command" image inspect "$selected_ref" --format '{{.Id}}')
"$docker_command" run --rm --network none --cap-drop ALL --security-opt no-new-privileges \
    "$selected_ref" bash -ec 'cat /usr/local/share/devcontainer-images/versions.txt; for file in /usr/local/share/devcontainer-images/*version*.txt; do case "$file" in */versions.txt) continue ;; esac; test ! -f "$file" || cat "$file"; done' \
    > "$record_dir/versions.txt"
status=verified
printf 'Verified candidate: %s\nBuild record: %s/result.json\n' "$selected_ref" "$record_dir"

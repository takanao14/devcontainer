#!/usr/bin/env bash
# shellcheck disable=SC2016
set -euo pipefail
mode=${1:-check}
case "$mode" in check|update) ;; *) echo 'Usage: lock-tools.sh [check|update]' >&2; exit 2 ;; esac
docker=${DOCKER:-docker}
image=${LOCK_IMAGE_REF:-devcontainer-images:lock-tools}
fixture=$(mktemp -d)
container=
cleanup() {
    if [[ -n "$container" ]]; then "$docker" rm -f "$container" >/dev/null; fi
    rm -rf "$fixture"
}
trap cleanup EXIT
paths=(tools/common images/go/tools images/rust/tools images/dns/tools)
for path in "${paths[@]}"; do
    mkdir -p "$fixture/input/$path"
    cp -R "$path/." "$fixture/input/$path/"
done
# Bootstrap uv from its reviewed lock, independently of the Rust toolchain.
mkdir -p "$fixture/input/uv"
yq -p toml -o toml '.tools |= with_entries(select(.key == "aqua:astral-sh/uv"))' images/rust/tools/config.toml > "$fixture/input/uv/config.toml"
yq -p toml -o toml '.tools |= with_entries(select(.key == "aqua:astral-sh/uv"))' images/rust/tools/mise.lock > "$fixture/input/uv/mise.lock"
container=$("$docker" create --user "$(id -u):$(id -g)" -e HOME=/tmp --network bridge --cap-drop ALL --security-opt no-new-privileges \
    "$image" bash -ec '
      export MISE_CONFIG_FILE=/work/uv/config.toml
      mise install --yes --locked
      export PATH="$(dirname "$(mise which uv)"):$PATH"
      for path in tools/common images/go/tools images/rust/tools images/dns/tools; do
        export MISE_CONFIG_FILE="/work/$path/config.toml"
        mise --yes lock --global --platform linux-x64,linux-arm64
      done
    ')
"$docker" cp -a "$fixture/input" "$container:/work"
"$docker" start -a "$container"
status=$("$docker" inspect --format '{{.State.ExitCode}}' "$container")
[[ "$status" == 0 ]] || exit "$status"
mkdir -p "$fixture/output"
"$docker" cp "$container:/work/." "$fixture/output/"
for path in "${paths[@]}"; do
    bash tests/check_tool_lock.sh "$fixture/output/$path"
done
changed=0
for path in "${paths[@]}"; do
    if ! diff -ru "$fixture/input/$path" "$fixture/output/$path"; then changed=1; fi
done
if [[ "$mode" == check ]]; then
    if [[ "$changed" == 1 ]]; then
        echo 'Tool locks differ; run make update-locks and review the changes.' >&2
        exit 1
    fi
else
    for path in "${paths[@]}"; do
        rsync -r --delete "$fixture/output/$path/" "$path/"
        chmod -R a+rX "$path"
    done
fi

#!/usr/bin/env bash
# Commands are evaluated inside the container.
# shellcheck disable=SC2016
set -euo pipefail
"${DOCKER:-docker}" run --rm --network none --cap-drop ALL --security-opt no-new-privileges \
    "${RUST_IMAGE_REF:?RUST_IMAGE_REF is required}" bash -ec '
      fixture=$(mktemp -d)
      trap "rm -rf \"$fixture\"" EXIT
      cp -a /usr/local/share/devcontainer-images/rust-tools/. "$fixture/"
      export MISE_CONFIG_FILE="$fixture/config.toml" MISE_DATA_DIR="$fixture/data" MISE_CACHE_DIR="$fixture/cache"
      export UV_CACHE_DIR="$fixture/uv-cache" UV_PYTHON_DOWNLOADS=never
      sidecar=$(yq -p toml -o yaml -r ".tools.\"pipx:ansible-core\"[0].uv.path" "$fixture/mise.lock")
      sed -i -E "s/sha256:[a-f0-9]+/sha256:0000000000000000000000000000000000000000000000000000000000000000/g" "$fixture/$sidecar/uv.lock"
      if mise install --yes --locked pipx:ansible-core > "$fixture/output" 2>&1; then
        printf "error: mise accepted a corrupted Python dependency graph\n" >&2; exit 1
      fi
      if ! grep -Eqi "digest|hash|checksum|sidecar.*(changed|mismatch)" "$fixture/output"; then
        cat "$fixture/output" >&2; exit 1
      fi
    '
printf 'mise rejects a corrupted Python dependency graph offline\n'

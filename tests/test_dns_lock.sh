#!/usr/bin/env bash
# Commands are evaluated inside the container.
# shellcheck disable=SC2016
set -euo pipefail
docker=${DOCKER:-docker}
"$docker" run --rm --network bridge --cap-drop ALL --security-opt no-new-privileges \
    "${DNS_IMAGE_REF:?DNS_IMAGE_REF is required}" bash -ec '
      fixture=$(mktemp -d)
      trap "rm -rf \"$fixture\"" EXIT
      source=/usr/local/share/devcontainer-images/dns-tools
      export MISE_CONFIG_FILE="$fixture/config.toml" MISE_DATA_DIR="$fixture/data" MISE_CACHE_DIR="$fixture/cache"
      yq -p toml -o toml ".tools |= with_entries(select(.key == \"aqua:direnv/direnv\"))" "$source/config.toml" > "$MISE_CONFIG_FILE"
      yq -p toml -o toml "del(.tools)" "$source/mise.lock" > "$fixture/mise.lock"
      if mise install --yes --locked > "$fixture/output" 2>&1; then
        printf "error: mise accepted a missing lock entry\n" >&2; exit 1
      fi
      grep -Eqi "lock|locked" "$fixture/output"
      yq -p toml -o toml ".tools |= with_entries(select(.key == \"aqua:direnv/direnv\"))" "$source/mise.lock" > "$fixture/mise.lock"
      sed -i -E "s/^checksum = \"sha256:[a-f0-9]+\"/checksum = \"sha256:0000000000000000000000000000000000000000000000000000000000000000\"/" "$fixture/mise.lock"
      if mise install --yes --locked > "$fixture/output" 2>&1; then
        printf "error: mise accepted an invalid checksum\n" >&2; exit 1
      fi
      if ! grep -Eqi "checksum.*(mismatch|failed|invalid)|mismatch.*checksum" "$fixture/output"; then
        cat "$fixture/output" >&2; exit 1
      fi
    '
printf 'mise rejects missing locks and corrupted artifact checksums\n'

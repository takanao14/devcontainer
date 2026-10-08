#!/usr/bin/env bash
# Commands are evaluated inside the container.
# shellcheck disable=SC2016
set -euo pipefail
docker=${DOCKER:-docker}
image=${RUST_IMAGE_REF:?RUST_IMAGE_REF is required}
project=$(cd -- "${PROJECT:?PROJECT is required}" && pwd -P)
[[ -f $project/Cargo.lock && -f $project/led-image-api/api/proto/image/v1/image_service.proto ]] || {
    printf 'error: PROJECT needs Cargo.lock and initialized led-image-api sources\n' >&2
    exit 1
}
[[ $project != *','* ]] || { printf 'error: PROJECT cannot contain a comma\n' >&2; exit 1; }
cache="devcontainer-rust-check-$$-$RANDOM"
trap '"$docker" volume rm "$cache" >/dev/null 2>&1 || true' EXIT
"$docker" run --rm --network bridge --cap-drop ALL --security-opt no-new-privileges \
    --mount "type=bind,source=$project,target=/source,readonly" \
    --mount "type=volume,source=$cache,target=/home/developer/.cargo" \
    "$image" bash -ec '
      mkdir /tmp/project
      rsync -a --exclude=.git --exclude=target --exclude=assets /source/ /tmp/project/
      cd /tmp/project
      cargo fetch --locked
    '
"$docker" run --rm --network none --cap-drop ALL --security-opt no-new-privileges \
    --mount "type=bind,source=$project,target=/source,readonly" \
    --mount "type=volume,source=$cache,target=/home/developer/.cargo" \
    "$image" bash -ec '
      mkdir /tmp/project
      rsync -a --exclude=.git --exclude=target --exclude=assets /source/ /tmp/project/
      cd /tmp/project
      export CARGO_NET_OFFLINE=true
      cargo fmt --all -- --check
      cargo clippy --locked --all-targets --no-default-features --features emulator -- -D warnings
      cargo test --locked --no-default-features --features emulator
      cargo build --locked --bins --no-default-features --features emulator
      python3 -m unittest discover -s scripts -p "test_*.py"
      python3 -m unittest discover -s ansible/tests -p "test_*.py"
      ANSIBLE_CONFIG="$PWD/ansible/ansible.cfg" ansible-lint --offline ansible/
    '
printf 'Rust emulator build, Clippy, tests, Python tests, and Ansible lint passed offline\n'

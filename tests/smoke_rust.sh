#!/usr/bin/env bash
# Commands are evaluated inside the container.
# shellcheck disable=SC2016
set -euo pipefail
"${DOCKER:-docker}" run --rm --network none --cap-drop ALL --security-opt no-new-privileges \
    "${RUST_IMAGE_REF:?RUST_IMAGE_REF is required}" bash -ec '
      test "$(id -u)" != 0
      test ! -w /opt/dev-tools/mise
      rustup --version 2>/dev/null | grep -q "^rustup 1.29.1 "
      test "$(yq -p toml -o yaml -r ".auto_self_update" "$RUSTUP_HOME/settings.toml")" = disable
      fixture=$(mktemp -d)
      trap "rm -rf \"$fixture\"" EXIT
      cd "$fixture"
      printf "[tools]\nrust = \"0.0.0\"\n" > mise.toml
      printf "[toolchain]\nchannel = \"0.0.0\"\n" > rust-toolchain.toml
      test "$(rustc --version | cut -d " " -f 2)" = 1.99.0
      test "$(cargo --version | cut -d " " -f 2)" = 1.99.0
      lint_python=$(dirname "$(readlink -f "$(command -v ansible-lint)")")/python
      "$lint_python" -c "import ansible.release; assert ansible.release.__version__ == \"2.21.5\""
    '
printf 'Rust image paths and Ansible dependency constraint passed offline\n'

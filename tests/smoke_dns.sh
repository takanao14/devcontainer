#!/usr/bin/env bash
# Commands are evaluated inside the container.
# shellcheck disable=SC2016
set -euo pipefail
docker=${DOCKER:-docker}
"$docker" run --rm --network none --cap-drop ALL --security-opt no-new-privileges \
    "${DNS_IMAGE_REF:?DNS_IMAGE_REF is required}" bash -ec '
      test "$(id -u)" != 0
      mise --version | grep -q "^2026.10.3 "
      diff /usr/local/share/devcontainer-images/dns-versions.txt <(dnscontrol version; sops --version --disable-version-check; age --version; direnv version)
      dnscontrol version | grep -q "5.3.1"
      test ! -w /opt/dev-tools/mise
      fixture=$(mktemp -d)
      trap "rm -rf \"$fixture\"" EXIT
      cd "$fixture"
      printf "[tools]\n\"github:DNSControl/dnscontrol\" = \"0.0.0\"\n" > mise.toml
      dnscontrol version | grep -q "5.3.1"
      age-keygen -o key.txt >/dev/null 2>&1
      printf "{\"fixture\":\"dummy\"}\n" > plain.json
      sops --encrypt --age "$(age-keygen -y key.txt)" plain.json > encrypted.json
      SOPS_AGE_KEY_FILE="$fixture/key.txt" sops --decrypt encrypted.json | jq -e ".fixture == \"dummy\"" >/dev/null
      printf "export DNS_IMAGE_FIXTURE=working\n" > .envrc
      direnv allow . >/dev/null 2>&1
      direnv exec . bash -ec "test \"\$DNS_IMAGE_FIXTURE\" = working" >/dev/null 2>&1
    '
printf 'DNS tools, dummy age/SOPS encryption, and direnv passed offline\n'

#!/usr/bin/env bash
set -euo pipefail
# Read the committed lock without depending on an existing yq implementation.
lock=tools/common/mise.lock
artifact=$(awk '
  /^\[tools\./ { active = ($0 == "[tools.\"aqua:mikefarah/yq\".\"platforms.linux-x64\"]") }
  active && /^(url|checksum) = / { print }
' "$lock")
url=$(printf '%s\n' "$artifact" | sed -n 's/^url = "\(.*\)"$/\1/p')
checksum=$(printf '%s\n' "$artifact" | sed -n 's/^checksum = "sha256:\([a-f0-9]*\)"$/\1/p')
[[ $url == https://github.com/mikefarah/yq/releases/download/*/yq_linux_amd64 && $checksum =~ ^[a-f0-9]{64}$ ]] ||
  { echo 'Missing or invalid Linux x64 yq lock' >&2; exit 1; }
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
curl --fail --location --retry 3 --output "$fixture/yq" "$url"
printf '%s  %s\n' "$checksum" "$fixture/yq" | sha256sum --check -
if [[ $(id -u) == 0 ]]; then
    install -m 0755 "$fixture/yq" /usr/local/bin/yq
else
    sudo install -m 0755 "$fixture/yq" /usr/local/bin/yq
fi
yq --version

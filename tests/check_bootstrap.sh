#!/usr/bin/env bash
set -euo pipefail
repo=${1:-.}
version=$(sed -n 's/^ARG MISE_VERSION=//p' "$repo/Dockerfile")
recorded=$(sed -n 's/^bootstrap: mise \([^;]*\);.*/\1/p' "$repo/tools/common/SOURCE")
if [[ -z $version || $version != "$recorded" ]]; then
    printf 'mise bootstrap version %s does not match reviewed SOURCE %s\n' "$version" "$recorded" >&2
    exit 1
fi
for pair in 'amd64 x64' 'arm64 arm64'; do
    read -r arch asset <<< "$pair"
    checksum=$(sed -n "s/^linux-$asset: //p" "$repo/tools/common/SOURCE")
    [[ $checksum =~ ^[a-f0-9]{64}$ ]]
    grep -F "$arch) asset=$asset; checksum=$checksum " "$repo/Dockerfile" >/dev/null ||
        { printf 'mise %s checksum differs from reviewed SOURCE\n' "$arch" >&2; exit 1; }
done
grep -F "^$version" "$repo/Makefile" >/dev/null ||
    { echo 'mise runtime verification version differs from bootstrap' >&2; exit 1; }
echo 'mise bootstrap version, checksums, and runtime verification match reviewed SOURCE'

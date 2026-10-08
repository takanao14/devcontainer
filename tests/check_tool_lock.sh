#!/usr/bin/env bash
set -euo pipefail
tools=${1:?Tool declarations directory is required}
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
yq -p toml -o json '.' "$tools/config.toml" > "$fixture/config.json"
yq -p toml -o json '.' "$tools/mise.lock" > "$fixture/lock.json"
jq -en --slurpfile config "$fixture/config.json" --slurpfile lock "$fixture/lock.json" '
  $config[0].tools as $tools | $lock[0].tools as $locked |
  $config[0].settings.minimum_release_age == "2d" and
  ($tools | keys) == ($locked | keys) and
  all($tools | to_entries[];
    . as $tool | $locked[$tool.key] as $entries |
    (if ($tool.value | type) == "object" then $tool.value.version else $tool.value end) as $version |
    ($entries | length) == 1 and
    ($entries[0] | .version == ($version | ltrimstr("v")) and
      (.backend == $tool.key or .backend == ("core:" + $tool.key)) and
      .specifiers == [$version] and
      if .backend == "core:rust" then
        .options.profile == $tool.value.profile and
        .options.components == ($tool.value.components | sort | join(","))
      elif (.backend | startswith("pipx:")) then
        (.uv.digest | test("^sha256:[a-f0-9]{64}$")) and
        (.uv.path | startswith(".mise/locks/") and (contains("..") | not)) and
        (($tool.value | type) != "object" or
          (.options.with | fromjson) == $tool.value.with)
      else all("platforms.linux-x64", "platforms.linux-arm64";
        . as $platform | $entries[0][$platform] |
        (.url | type == "string" and startswith("https://")) and
        (.checksum | type == "string" and test("^sha256:[a-f0-9]{64}$"))) end))
' > /dev/null
jq -r '.tools[][] | select(has("uv")) | .uv.path' "$fixture/lock.json" |
    while IFS= read -r sidecar; do
        test -f "$tools/$sidecar/pyproject.toml"
        test -f "$tools/$sidecar/uv.lock"
    done
printf '%s: declarations, platform artifacts, and dependency sidecars checked\n' "$tools"

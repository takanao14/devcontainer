#!/usr/bin/env bash
set -euo pipefail
tools=${1:?Tool declarations directory is required}
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
yq -p toml -o json '.' "$tools/config.toml" > "$fixture/config.json"
yq -p toml -o json '.' "$tools/mise.lock" > "$fixture/lock.json"
# Emit one message per mismatch so CI logs name the stale declaration or lock entry.
jq -rn --slurpfile config "$fixture/config.json" --slurpfile lock "$fixture/lock.json" '
  def fail(cond; msg): if cond then empty else msg end;
  def sha256: type == "string" and test("^sha256:[a-f0-9]{64}$");
  $config[0].tools as $tools | $lock[0].tools as $locked |
  fail($config[0].settings.minimum_release_age == "2d";
    "settings.minimum_release_age must be \"2d\""),
  ((($tools | keys) - ($locked | keys))[] | "\(.): declared but missing from mise.lock"),
  ((($locked | keys) - ($tools | keys))[] | "\(.): locked but not declared"),
  ($tools | to_entries[] | select($locked[.key] != null) |
    . as $tool | $locked[$tool.key] as $entries |
    (if ($tool.value | type) == "object" then $tool.value.version else $tool.value end) as $version |
    if ($entries | length) != 1 then
      "\($tool.key): expected one lock entry, found \($entries | length)"
    else
      $entries[0] as $entry |
      fail($entry.version == ($version | ltrimstr("v"));
        "\($tool.key): declared \($version) but locked \($entry.version) (run make update-locks)"),
      fail($entry.backend == $tool.key or $entry.backend == ("core:" + $tool.key);
        "\($tool.key): unexpected lock backend \($entry.backend)"),
      fail($entry.specifiers == [$version];
        "\($tool.key): lock specifiers \($entry.specifiers | tojson) do not match \($version)"),
      if $entry.backend == "core:rust" then
        fail($entry.options.profile == $tool.value.profile;
          "\($tool.key): lock profile does not match declaration"),
        fail($entry.options.components == ($tool.value.components | sort | join(","));
          "\($tool.key): lock components do not match declaration")
      elif ($entry.backend | startswith("pipx:")) then
        fail($entry.uv.digest | sha256; "\($tool.key): uv digest is missing or invalid"),
        fail($entry.uv.path | type == "string" and startswith(".mise/locks/") and (contains("..") | not);
          "\($tool.key): uv sidecar path is invalid"),
        fail(($tool.value | type) != "object" or (($entry.options.with // "null") | fromjson) == $tool.value.with;
          "\($tool.key): lock with options do not match declaration")
      else
        ("platforms.linux-x64", "platforms.linux-arm64") as $platform | $entry[$platform] as $artifact |
        fail($artifact.url | type == "string" and startswith("https://");
          "\($tool.key): \($platform) URL is missing or not HTTPS"),
        fail($artifact.checksum | sha256;
          "\($tool.key): \($platform) checksum is missing or invalid")
      end
    end)
' > "$fixture/errors"
if test -s "$fixture/errors"; then
    sed "s|^|$tools: |" "$fixture/errors" >&2
    exit 1
fi
jq -r '.tools[][] | select(has("uv")) | .uv.path' "$fixture/lock.json" |
    while IFS= read -r sidecar; do
        for file in pyproject.toml uv.lock; do
            test -f "$tools/$sidecar/$file" ||
                { printf '%s: missing dependency sidecar %s\n' "$tools" "$sidecar/$file" >&2; exit 1; }
        done
    done
printf '%s: declarations, platform artifacts, and dependency sidecars checked\n' "$tools"

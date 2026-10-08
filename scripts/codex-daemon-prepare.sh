#!/usr/bin/env bash
set -euo pipefail

package=${1:-/usr/local/share/devcontainer-images/codex-package}
home=${CODEX_HOME:?CODEX_HOME is required}
[[ -x $package/bin/codex && -f $package/codex-package.json ]] || {
    printf 'error: the image has no complete Codex daemon package\n' >&2
    exit 1
}
jq -e '.entrypoint == "bin/codex"' "$package/codex-package.json" >/dev/null
state="$home/app-server-daemon"
root="$home/packages/app-server-daemon"
mkdir -p "$state" "$root"
# Refuse to replace a directory; old release trees and user state remain intact.
if [[ -e $root/current && ! -L $root/current ]]; then
    printf 'error: Codex daemon current selection is not a symlink\n' >&2
    exit 1
fi
temporary=$(mktemp -d "$state/.image-selection.XXXXXX")
trap 'rm -rf "$temporary"' EXIT
settings="$state/settings.json"
if [[ -e $settings ]]; then
    jq '.updater.autoUpdateEnabled = false' "$settings" > "$temporary/settings.json"
else
    printf '{"updater":{"autoUpdateEnabled":false}}\n' > "$temporary/settings.json"
fi
chmod 600 "$temporary/settings.json"
mv "$temporary/settings.json" "$settings"
ln -s "$package" "$temporary/current"
mv -Tf "$temporary/current" "$root/current"

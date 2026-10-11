#!/usr/bin/env bash
set -euo pipefail
workflow=.forgejo/workflows/image.yml
yq -o=json '.' "$workflow" | jq -e '
  .jobs.checks.steps as $steps |
  all($steps[]; (has("env") | not)) and
  ($steps[-1].run == "make check") and ([ $steps[] | .run // "" ] | all(.[]; (test("docker|REGISTRY_|check-locks|make rebuild|make build") | not))) and
  $steps[0].with."persist-credentials" == false
' >/dev/null
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
cat > "$fixture/docker" <<'MOCK'
#!/usr/bin/env bash
echo 'Docker must not be called by static CI' >&2
exit 99
MOCK
chmod +x "$fixture/docker"
# Do not recursively invoke check: these are the Docker-independent CI targets.
make test check-common-lock check-go-lock check-rust-lock check-infra-lock DOCKER="$fixture/docker"
for kind in go rust infra; do
    commands=$(make -n "build-$kind" IMAGE_REF=devcontainer-images:reviewed-base)
    if printf '%s\n' "$commands" | grep -q ' build .* -t .*reviewed-base'; then
        echo 'Derivative rebuilds the selected base' >&2; exit 1
    fi
    printf '%s\n' "$commands" | grep -F 'image inspect "devcontainer-images:reviewed-base"' >/dev/null
    printf '%s\n' "$commands" | grep -F 'BASE_IMAGE=devcontainer-images:reviewed-base' >/dev/null
done

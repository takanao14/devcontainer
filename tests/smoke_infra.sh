#!/usr/bin/env bash
# shellcheck disable=SC2016
set -euo pipefail
"${DOCKER:-docker}" run --rm --network none --cap-drop ALL --security-opt no-new-privileges \
    "${INFRA_IMAGE_REF:-devcontainer-images:infra}" bash -ec '
      test "$(id -u)" != 0
      diff /usr/local/share/devcontainer-images/infra-versions.txt <(terraform version -json | jq -r .terraform_version; terragrunt --version; packer version)
      config=/usr/local/share/devcontainer-images/infra-tools/config.toml
      test "$(terraform version -json | jq -r .terraform_version)" = "$(yq -p toml -r ".tools.\"aqua:hashicorp/terraform\"" "$config")"
      test "$(terragrunt --version)" = "terragrunt version v$(yq -p toml -r ".tools.\"aqua:gruntwork-io/terragrunt\"" "$config")"
      packer version | grep -F "Packer v$(yq -p toml -r ".tools.\"aqua:hashicorp/packer\"" "$config")"
      test ! -w /opt/dev-tools/mise
      test "$CHECKPOINT_DISABLE" = 1
      fixture=$(mktemp -d)
      trap "rm -rf \"$fixture\"" EXIT
      cd "$fixture"
      printf "[tools]\nterraform = \"0.0.0\"\npacker = \"0.0.0\"\nterragrunt = \"0.0.0\"\n" > mise.toml
      printf "variable \"example\" {\n  type = string\n}\n" > main.tf
      terraform fmt -check .
      terraform init -backend=false -input=false -no-color
      terraform validate -no-color
      printf "locals {\n  example = \"fixture\"\n}\n" > terragrunt.hcl
      terragrunt hcl format --check --diff --working-dir "$fixture"
      printf "variable \"example\" {\n  type    = string\n  default = \"fixture\"\n}\n" > fixture.pkr.hcl
      packer fmt -check fixture.pkr.hcl
      packer validate -syntax-only fixture.pkr.hcl
    '
echo 'Infrastructure versions, fixed paths, permissions, and offline syntax checks passed'

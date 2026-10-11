#!/usr/bin/env bash
# shellcheck disable=SC2016
set -euo pipefail
project=${PROJECT:?Set PROJECT to the homelab checkout}
[[ $project == /* && -d $project/tf && -f $project/packer/image.pkr.hcl ]] ||
    { echo 'PROJECT needs homelab tf/ and packer/image.pkr.hcl' >&2; exit 1; }
"${DOCKER:-docker}" run --rm --network none --cap-drop ALL --security-opt no-new-privileges \
    --mount "type=bind,source=$project/tf,target=/source/tf,readonly" \
    --mount "type=bind,source=$project/packer,target=/source/packer,readonly" \
    "${INFRA_IMAGE_REF:-devcontainer-images:infra}" bash -ec '
      fixture=$(mktemp -d)
      trap "rm -rf \"$fixture\"" EXIT
      mkdir -p "$fixture/tf" "$fixture/packer"
      rsync -a --exclude=.terraform --exclude=.terragrunt-cache --exclude="*.tfstate*" --exclude="*.tfvars" /source/tf/ "$fixture/tf/"
      rsync -a --exclude=output --exclude="output-*" --exclude=images --exclude=keys --exclude=.envrc /source/packer/ "$fixture/packer/"
      terraform fmt -check -recursive "$fixture/tf"
      terragrunt hcl format --check --diff --working-dir "$fixture/tf"
      packer fmt -check -recursive "$fixture/packer"
      packer validate -syntax-only "$fixture/packer/image.pkr.hcl"
    '
echo 'Homelab formatting and Packer syntax passed offline; provider/plugin validation was not performed'

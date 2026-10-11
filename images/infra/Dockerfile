ARG BASE_IMAGE=devcontainer-images:ubuntu-26.04
FROM ${BASE_IMAGE}
USER root
COPY tools/ /usr/local/share/devcontainer-images/infra-tools/
RUN set -eu; \
    export MISE_CONFIG_FILE=/usr/local/share/devcontainer-images/infra-tools/config.toml; \
    export MISE_DATA_DIR=/opt/dev-tools/mise; \
    export MISE_CACHE_DIR=/tmp/mise-cache; \
    mise install --yes --locked; \
    for binary in terraform terragrunt packer dnscontrol sops age age-keygen direnv; do \
        executable=$(mise which "$binary"); \
        test -x "$executable"; \
        ln -s "$executable" "/usr/local/bin/$binary"; \
    done; \
    rm -rf /tmp/mise-cache
ENV CHECKPOINT_DISABLE=1 TF_IN_AUTOMATION=1 TF_INPUT=0
RUN set -eu; { terraform version -json | jq -r .terraform_version; terragrunt --version; packer version; } \
    > /usr/local/share/devcontainer-images/infra-versions.txt; \
    { dnscontrol version; sops --version --disable-version-check; age --version; direnv version; } \
      > /usr/local/share/devcontainer-images/dns-versions.txt
USER developer

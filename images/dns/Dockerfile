ARG BASE_IMAGE=devcontainer-images:ubuntu-26.04
FROM ${BASE_IMAGE} AS mise-bootstrap
USER root

FROM mise-bootstrap
COPY tools/ /usr/local/share/devcontainer-images/dns-tools/
RUN set -eu; \
    export MISE_CONFIG_FILE=/usr/local/share/devcontainer-images/dns-tools/config.toml; \
    export MISE_DATA_DIR=/opt/dev-tools/mise; \
    export MISE_CACHE_DIR=/tmp/mise-cache; \
    mise install --yes --locked; \
    for binary in dnscontrol sops age age-keygen direnv; do \
        executable=$(mise which "$binary"); \
        test -x "$executable"; \
        ln -s "$executable" "/usr/local/bin/$binary"; \
    done; \
    rm -rf /tmp/mise-cache; \
    { dnscontrol version; sops --version --disable-version-check; age --version; direnv version; } \
      > /usr/local/share/devcontainer-images/dns-versions.txt
USER developer

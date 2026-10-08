ARG BASE_IMAGE=devcontainer-images:ubuntu-26.04
FROM ${BASE_IMAGE} AS mise-bootstrap
USER root

FROM mise-bootstrap
COPY tools/ /usr/local/share/devcontainer-images/go-tools/
RUN set -eu; \
    export MISE_CONFIG_FILE=/usr/local/share/devcontainer-images/go-tools/config.toml; \
    export MISE_DATA_DIR=/opt/dev-tools/mise; \
    export MISE_CACHE_DIR=/tmp/mise-cache; \
    mise install --yes --locked; \
    go_binary=$(mise which go); \
    go_root=$(dirname "$(dirname "$go_binary")"); \
    ln -s "$go_root" /usr/local/go; \
    ln -s "$(mise which buf)" /usr/local/bin/buf; \
    rm -rf /tmp/mise-cache

# Fail on missing toolchains rather than downloading one during agent execution.
ENV PATH=/usr/local/go/bin:${PATH} GOTOOLCHAIN=local
RUN go version > /usr/local/share/devcontainer-images/go-version.txt
RUN buf --version > /usr/local/share/devcontainer-images/buf-version.txt
USER developer
RUN mkdir -p /home/developer/go

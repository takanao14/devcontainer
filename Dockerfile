FROM ubuntu:26.04 AS mise-bootstrap

# renovate: datasource=github-releases depName=jdx/mise
ARG MISE_VERSION=2026.10.10

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bash bash-completion build-essential ca-certificates curl \
        file git gnupg iproute2 iputils-ping jq less locales \
        nodejs npm openssh-client procps ripgrep rsync shellcheck sudo tar unzip vim-tiny wget zip \
    && locale-gen en_US.UTF-8 \
    && rm -rf /var/lib/apt/lists/*

# Bootstrap version and digests are recorded in tools/common/SOURCE.
RUN set -eu; \
    arch=$(dpkg --print-architecture); \
    case "$arch" in \
        amd64) asset=x64; checksum=7d79972e15549b286dcf9e25ef8c4fcef3d9fd7c0332d11cdfbc7d2842c418be ;; \
        arm64) asset=arm64; checksum=3978fbccfa2284b12e46cbf6df53cae118ec1f2fa780b6a204e6c9c792b620f6 ;; \
        *) echo "Unsupported mise architecture: $arch" >&2; exit 1 ;; \
    esac; \
    curl -fsSL --retry 3 "https://github.com/jdx/mise/releases/download/v${MISE_VERSION}/mise-v${MISE_VERSION}-linux-$asset" -o /tmp/mise; \
    printf '%s  /tmp/mise\n' "$checksum" | sha256sum -c -; \
    install -m 0755 /tmp/mise /usr/local/bin/mise; \
    rm /tmp/mise

FROM mise-bootstrap
ARG USERNAME=developer
ARG USER_UID=1000
ARG USER_GID=1000
COPY tools/common/ /usr/local/share/devcontainer-images/common-tools/
RUN set -eu; \
    export MISE_CONFIG_FILE=/usr/local/share/devcontainer-images/common-tools/config.toml; \
    export MISE_DATA_DIR=/opt/dev-tools/mise; \
    export MISE_CACHE_DIR=/tmp/mise-cache; \
    mise install --yes --locked; \
    ln -s "$(mise which yq)" /usr/local/bin/yq; \
    rm -rf /tmp/mise-cache

# Ubuntu's base image includes a user with UID 1000.
RUN if id ubuntu >/dev/null 2>&1; then userdel -r ubuntu; fi \
    && groupadd --gid "${USER_GID}" "${USERNAME}" \
    && useradd --uid "${USER_UID}" --gid "${USER_GID}" --create-home --shell /bin/bash "${USERNAME}" \
    && printf '%s ALL=(ALL) PASSWD:ALL\n' "${USERNAME}" > "/etc/sudoers.d/${USERNAME}" \
    && chmod 0440 "/etc/sudoers.d/${USERNAME}"

RUN set -eu; \
    build_epoch=$(date -u +%s); \
    cutoff=$(date -u -d "@$((build_epoch - 172800))" +%Y-%m-%dT%H:%M:%SZ); \
    npm install -g --before="$cutoff" @openai/codex@latest @anthropic-ai/claude-code@latest; \
    npm cache clean --force; \
    mkdir -p /usr/local/share/devcontainer-images; \
    printf '%s\n' "$cutoff" > /usr/local/share/devcontainer-images/npm-before.txt; \
    { codex --version; claude --version; node --version; } \
       > /usr/local/share/devcontainer-images/versions.txt

# Keep the complete native package (including helpers) owned by the image.
RUN set -eu; \
    manifest=$(find /usr/local/lib/node_modules/@openai/codex -name codex-package.json); \
    test -f "$manifest"; \
    package=$(dirname "$manifest"); \
    for executable in bin/codex bin/codex-code-mode-host codex-path/rg codex-resources/bwrap; do \
        test -x "$package/$executable"; \
    done; \
    ln -s "$package" /usr/local/share/devcontainer-images/codex-package
COPY --chmod=0755 scripts/codex-daemon-prepare.sh /usr/local/bin/devcontainer-codex-prepare

ENV LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 \
    MISE_MINIMUM_RELEASE_AGE=2d \
    CODEX_HOME=/home/developer/.codex \
    CLAUDE_CONFIG_DIR=/home/developer/.claude \
    DISABLE_UPDATES=1 DISABLE_AUTOUPDATER=1
USER ${USERNAME}
RUN mkdir -p /home/developer/.codex /home/developer/.claude
WORKDIR /workspace
CMD ["bash"]

FROM ubuntu:26.04

ARG USERNAME=developer
ARG USER_UID=1000
ARG USER_GID=1000

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bash bash-completion build-essential ca-certificates curl \
        file git gnupg iproute2 iputils-ping jq less locales \
        nodejs npm openssh-client procps ripgrep rsync shellcheck sudo tar unzip vim-tiny wget zip \
    && locale-gen en_US.UTF-8 \
    && rm -rf /var/lib/apt/lists/*

# Published asset digests: https://github.com/mikefarah/yq/releases/tag/v4.54.1
RUN set -eu; \
    arch=$(dpkg --print-architecture); \
    case "$arch" in \
        amd64) checksum=8e34fc298390875de416e6a4afcb8cabeceb25d9aa8506c1a2f9353cf702ea5f ;; \
        arm64) checksum=189088da0c6429ec5178dfaab1a114805f6cab0b61b165ab236efedf1d57a71b ;; \
        *) echo "Unsupported yq architecture: $arch" >&2; exit 1 ;; \
    esac; \
    curl -fsSL --retry 3 "https://github.com/mikefarah/yq/releases/download/v4.54.1/yq_linux_$arch" -o /tmp/yq; \
    printf '%s  /tmp/yq\n' "$checksum" | sha256sum -c -; \
    install -m 0755 /tmp/yq /usr/local/bin/yq; \
    rm /tmp/yq

# Ubuntu's base image includes a user with UID 1000.
RUN if id ubuntu >/dev/null 2>&1; then userdel -r ubuntu; fi \
    && groupadd --gid "${USER_GID}" "${USERNAME}" \
    && useradd --uid "${USER_UID}" --gid "${USER_GID}" --create-home --shell /bin/bash "${USERNAME}" \
    && printf '%s ALL=(ALL) PASSWD:ALL\n' "${USERNAME}" > "/etc/sudoers.d/${USERNAME}" \
    && chmod 0440 "/etc/sudoers.d/${USERNAME}"

RUN npm install -g @openai/codex@latest @anthropic-ai/claude-code@latest \
    && npm cache clean --force \
    && mkdir -p /usr/local/share/devcontainer-images \
    && { codex --version; claude --version; node --version; } \
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
    CODEX_HOME=/home/developer/.codex \
    CLAUDE_CONFIG_DIR=/home/developer/.claude \
    DISABLE_UPDATES=1 DISABLE_AUTOUPDATER=1
USER ${USERNAME}
RUN mkdir -p /home/developer/.codex /home/developer/.claude
WORKDIR /workspace
CMD ["bash"]

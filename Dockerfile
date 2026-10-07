FROM ubuntu:26.04

ARG USERNAME=developer
ARG USER_UID=1000
ARG USER_GID=1000

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bash bash-completion build-essential ca-certificates curl \
        file git gnupg iproute2 iputils-ping jq less locales \
        nodejs npm openssh-client procps ripgrep rsync sudo tar unzip vim-tiny wget zip \
    && locale-gen en_US.UTF-8 \
    && rm -rf /var/lib/apt/lists/*

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

ENV LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 \
    CODEX_HOME=/home/developer/.codex \
    CLAUDE_CONFIG_DIR=/home/developer/.claude \
    DISABLE_UPDATES=1 DISABLE_AUTOUPDATER=1
USER ${USERNAME}
RUN mkdir -p /home/developer/.codex /home/developer/.claude
WORKDIR /workspace
CMD ["bash"]

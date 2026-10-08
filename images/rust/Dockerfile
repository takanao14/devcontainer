ARG BASE_IMAGE=devcontainer-images:ubuntu-26.04
FROM ${BASE_IMAGE} AS mise-bootstrap
USER root

FROM mise-bootstrap
# renovate: datasource=github-releases depName=rust-lang/rustup
ARG RUSTUP_VERSION=1.29.1
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        pkg-config protobuf-compiler libasound2-dev \
        libx11-dev libxcursor-dev libxrandr-dev libxinerama-dev libxi-dev \
        libwayland-dev libxkbcommon-dev wayland-protocols \
        python3 python3-venv python-is-python3 \
    && rm -rf /var/lib/apt/lists/*

ENV RUSTUP_HOME=/opt/rustup CARGO_HOME=/opt/cargo
# Published digests: https://static.rust-lang.org/rustup/archive/1.29.1/
RUN set -eu; \
    arch=$(dpkg --print-architecture); \
    case "$arch" in \
        amd64) target=x86_64-unknown-linux-gnu; checksum=dda7234360b7f578ca8b0ddcb80145646fa61a67c1720a5abc7051b35c9fcb71 ;; \
        arm64) target=aarch64-unknown-linux-gnu; checksum=15f6e4ce9f583b929c996c91562bad6d4454f3281de858b02cdfdef615fac433 ;; \
        *) echo "Unsupported Rust architecture: $arch" >&2; exit 1 ;; \
    esac; \
    curl -fsSL --retry 3 "https://static.rust-lang.org/rustup/archive/${RUSTUP_VERSION}/$target/rustup-init" -o /tmp/rustup-init; \
    printf '%s  /tmp/rustup-init\n' "$checksum" | sha256sum -c -; \
    chmod 0755 /tmp/rustup-init; \
    /tmp/rustup-init -y --no-modify-path --profile minimal --default-toolchain none; \
    /opt/cargo/bin/rustup set auto-self-update disable; \
    rm /tmp/rustup-init

ENV PATH=/opt/cargo/bin:${PATH}
COPY tools/ /usr/local/share/devcontainer-images/rust-tools/
RUN set -eu; \
    export MISE_CONFIG_FILE=/usr/local/share/devcontainer-images/rust-tools/config.toml; \
    export MISE_DATA_DIR=/opt/dev-tools/mise; \
    export MISE_CACHE_DIR=/tmp/mise-cache; \
    export UV_CACHE_DIR=/tmp/uv-cache UV_PYTHON_DOWNLOADS=never; \
    mise install --yes --locked aqua:astral-sh/uv; \
    ln -s "$(mise which uv)" /usr/local/bin/uv; \
    mise install --yes --locked; \
    rustup default 1.99.0; \
    rustup set auto-self-update disable; \
    ln -s "$(dirname "$(dirname "$(rustup which --toolchain 1.99.0 rustc)")")" /opt/rust-toolchain; \
    for binary in ansible ansible-playbook ansible-galaxy ansible-vault ansible-config ansible-console ansible-doc ansible-inventory ansible-pull ansible-lint; do \
        executable=$(mise which "$binary"); \
        test -x "$executable"; \
        ln -s "$executable" "/usr/local/bin/$binary"; \
    done; \
    rm -rf /tmp/mise-cache /tmp/uv-cache

ENV PATH=/opt/rust-toolchain/bin:${PATH} RUSTUP_TOOLCHAIN=1.99.0 RUSTUP_AUTO_INSTALL=0
RUN { rustc --version; cargo --version; rustfmt --version; cargo clippy --version; } \
      > /usr/local/share/devcontainer-images/rust-versions.txt
ENV CARGO_HOME=/home/developer/.cargo
USER developer
RUN mkdir -p /home/developer/.cargo

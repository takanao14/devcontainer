ARG BASE_IMAGE
FROM ${BASE_IMAGE}
RUN apt-get update \
    && apt-get install -y --no-install-recommends python3 python3-venv python-is-python3 \
    && rm -rf /var/lib/apt/lists/*
ENV MISE_MINIMUM_RELEASE_AGE=2d MISE_DATA_DIR=/tmp/mise-data \
    MISE_CACHE_DIR=/tmp/mise-cache MISE_STATE_DIR=/tmp/mise-state \
    UV_CACHE_DIR=/tmp/uv-cache UV_PYTHON_DOWNLOADS=never

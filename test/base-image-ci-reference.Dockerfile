# syntax=docker/dockerfile:1
# check=skip=InvalidDefaultArgInFrom
# A reference repository layer over base-ci, for test/base-image-ci-reference.sh. A repository image's CI variant is its
# repository layers rebased onto base-ci, so the same instructions over base-ci give the same filesystem. The ENV and
# directories below mirror the `environment` stage of the Standards Package image recipe (image/Dockerfile) and its
# frozen copy in Rubio-Enterprises/.github (tests/fixtures/frozen-repository-image-v2.Dockerfile): change them together.
ARG BASE
FROM ${BASE}
# Test-only fault injection: the checks must fail on a broken image, or they prove nothing
ARG BREAK=
USER root
ENV MISE_PYTHON_COMPILE=0 \
    MISE_CACHE_DIR=/home/vscode/.cache/mise \
    UV_CACHE_DIR=/home/vscode/.cache/uv \
    UV_LINK_MODE=copy \
    UV_PYTHON_INSTALL_DIR=/home/vscode/.local/share/uv/python \
    CARGO_HOME=/home/vscode/.cache/cargo \
    RUSTUP_HOME=/home/vscode/.local/share/rustup \
    pnpm_config_store_dir=/home/vscode/.cache/pnpm-store \
    npm_config_cache=/home/vscode/.cache/npm \
    GOMODCACHE=/home/vscode/.cache/gomod \
    GOFLAGS=-modcacherw
RUN install -d -o vscode -g vscode /usr/local/share/mise /workspaces/reference \
 && runuser -u vscode -- mkdir -p \
    "$MISE_CACHE_DIR" "$UV_CACHE_DIR" "$pnpm_config_store_dir" "$npm_config_cache" "$GOMODCACHE" \
    "$CARGO_HOME" "$RUSTUP_HOME" "$UV_PYTHON_INSTALL_DIR"
ENV PATH=/usr/local/share/mise/shims:${PATH}
RUN case "$BREAK" in \
      "") ;; \
      root-owned-cache) chown -R root:root "$UV_CACHE_DIR" ;; \
      root-owned-runner) chown -R root:root /opt/actions-runner ;; \
      *) echo "unknown fault $BREAK" >&2; exit 1 ;; \
    esac
WORKDIR /workspaces/reference
USER vscode

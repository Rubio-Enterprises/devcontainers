# syntax=docker/dockerfile:1@sha256:4edf897a3ffa55b89f906fc8cc78afdb3f1834cc9c7083565e611a8a7d5fe99e
# check=skip=InvalidDefaultArgInFrom
ARG BASE
FROM ghcr.io/actions/actions-runner:2.337.0@sha256:e5496277be5d09bc968b3d64911b74e219ac4a3f2edce956a3ecf9271bea1ef4 AS runner
FROM ${BASE}
ARG BASE_DIGEST
LABEL org.opencontainers.image.base.name="ghcr.io/rubio-enterprises/devcontainers/base:latest" \
    org.opencontainers.image.base.digest="${BASE_DIGEST}"
USER root
ENV MISE_DATA_DIR=/home/vscode/.local/share/mise \
    MISE_CACHE_DIR=/home/vscode/.cache/mise \
    UV_LINK_MODE=copy
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      -o /usr/share/keyrings/githubcli-archive-keyring.gpg \
 && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
 && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends gh jq \
 && rm -rf /var/lib/apt/lists/* \
 && install -d -o vscode -g vscode /home/vscode/.local /home/vscode/.local/share \
      "$MISE_DATA_DIR" "$MISE_DATA_DIR/bin" /home/vscode/.cache "$MISE_CACHE_DIR" \
      /home/vscode/.local/state /home/vscode/.local/state/mise /var/cache/devcontainer \
 && ln -s /usr/local/bin/mise "$MISE_DATA_DIR/bin/mise"
COPY --link --from=runner --chown=1000:1000 /home/runner /opt/actions-runner
USER vscode
WORKDIR /opt/actions-runner

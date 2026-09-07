# syntax=docker/dockerfile:1.7

ARG GO_IMAGE=golang:1-bookworm
ARG NODE_IMAGE=node:22-bookworm-slim

FROM ${GO_IMAGE} AS multica-builder

ARG MULTICA_REPO=https://github.com/multica-ai/multica.git
ARG MULTICA_REF=main

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates git \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src/multica
RUN git init -q . \
    && git remote add origin "${MULTICA_REPO}" \
    && git fetch --depth 1 origin "${MULTICA_REF}" \
    && git checkout -q FETCH_HEAD \
    && git rev-parse --short HEAD > /tmp/multica.commit

WORKDIR /src/multica/server
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    go build -trimpath \
        -ldflags "-s -w -X main.version=${MULTICA_REF} -X main.commit=$(cat /tmp/multica.commit)" \
        -o /out/multica ./cmd/multica \
    && /out/multica --version


FROM ${NODE_IMAGE} AS runtime

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    APP_USER=node \
    MULTICA_BIN_DIR=/opt/multica/bin \
    CURSOR_ROOT=/opt/cursor

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bash \
        ca-certificates \
        curl \
        git \
        gosu \
        jq \
        less \
        openssh-client \
        procps \
        rsync \
        tini \
        unzip \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        -o /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends gh \
    && rm -rf /var/lib/apt/lists/*

ARG INSTALL_BROWSER_DEPS=false
RUN if [ "${INSTALL_BROWSER_DEPS}" = "true" ]; then \
        apt-get update \
        && apt-get install -y --no-install-recommends \
            chromium \
            fonts-liberation \
            fonts-noto-color-emoji \
        && rm -rf /var/lib/apt/lists/*; \
    fi
ENV CHROME_BIN=/usr/bin/chromium \
    PUPPETEER_SKIP_DOWNLOAD=1 \
    PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1

# codebase-memory-mcp : archive portable obligatoire sur Bookworm (glibc 2.36).
ARG TARGETARCH
ARG CBM_VERSION=0.10.8
ARG CBM_CHECKSUMS_SHA256=9d2e33bdf9c9dc8662079d5b9a1bbf716aa2e62e2ed6cc51cf4ae06d42498787
RUN set -eux; \
    case "${TARGETARCH}" in \
        amd64|arm64) cbm_arch="${TARGETARCH}" ;; \
        *) echo "Architecture non supportee: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    cbm_asset="codebase-memory-mcp-linux-${cbm_arch}-portable.tar.gz"; \
    cbm_base="https://github.com/DeusData/codebase-memory-mcp/releases/download/v${CBM_VERSION}"; \
    mkdir -p /tmp/cbm; \
    curl -fL --retry 3 "${cbm_base}/checksums.txt" -o /tmp/cbm/checksums.txt; \
    echo "${CBM_CHECKSUMS_SHA256}  /tmp/cbm/checksums.txt" | sha256sum -c -; \
    curl -fL --retry 3 "${cbm_base}/${cbm_asset}" -o "/tmp/cbm/${cbm_asset}"; \
    cd /tmp/cbm; \
    grep "  ${cbm_asset}\$" checksums.txt | sha256sum -c -; \
    tar -xzf "${cbm_asset}" -C /usr/local/bin codebase-memory-mcp; \
    chmod 0755 /usr/local/bin/codebase-memory-mcp; \
    codebase-memory-mcp --version | grep -F "${CBM_VERSION}"; \
    rm -rf /tmp/cbm

# Cursor s'installe sous $HOME. On l'ancre hors de /home/node pour qu'un volume
# monte sur le home ne masque jamais l'outillage livre par l'image.
RUN set -eux; \
    mkdir -p "${CURSOR_ROOT}"; \
    export HOME="${CURSOR_ROOT}"; \
    curl -fsS https://cursor.com/install | bash; \
    chmod -R a+rX "${CURSOR_ROOT}"; \
    ln -sf "${CURSOR_ROOT}/.local/bin/cursor-agent" /usr/local/bin/cursor-agent; \
    cursor-agent --version

ARG CLAUDE_CODE_VERSION=latest
ARG CODEX_VERSION=latest
RUN npm install --global --no-fund --no-audit \
        "@anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}" \
        "@openai/codex@${CODEX_VERSION}" \
    && npm cache clean --force \
    && claude --version \
    && codex --version

COPY --from=multica-builder /out/multica ${MULTICA_BIN_DIR}/multica

# Le daemon sait se mettre a jour tout seul : le repertoire du binaire doit donc
# appartenir a l'utilisateur applicatif, sinon l'auto-update echoue en silence.
RUN mkdir -p /workspace /data/workspaces /data/codebase-memory \
    && chown -R node:node /workspace /data/workspaces /data/codebase-memory /home/node "${MULTICA_BIN_DIR}"

ENV PATH=/home/node/.local/bin:${MULTICA_BIN_DIR}:/usr/local/bin:/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin \
    HOME=/home/node \
    GH_NO_UPDATE_NOTIFIER=1 \
    GH_PAGER=cat \
    NPM_CONFIG_FUND=false \
    NPM_CONFIG_UPDATE_NOTIFIER=false \
    MULTICA_WORKSPACES_ROOT=/data/workspaces \
    CBM_CACHE_DIR=/data/codebase-memory \
    CBM_RUNTIME_DIR=/tmp/codebase-memory-runtime \
    CBM_ALLOWED_ROOT=/data/workspaces

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod 0755 /usr/local/bin/docker-entrypoint.sh

WORKDIR /workspace

HEALTHCHECK --interval=30s --timeout=10s --start-period=90s --retries=3 \
    CMD gosu "$APP_USER" multica daemon status --output json > /dev/null || exit 1

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/docker-entrypoint.sh"]
CMD ["multica", "daemon", "start", "--foreground"]

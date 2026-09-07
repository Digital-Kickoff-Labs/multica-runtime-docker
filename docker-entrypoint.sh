#!/usr/bin/env bash
set -euo pipefail

log() { printf '[multica-runtime] %s\n' "$*" >&2; }
die() { log "ERREUR: $*"; exit 1; }

APP_USER="${APP_USER:-node}"
APP_GROUP="${APP_GROUP:-$APP_USER}"
APP_HOME="${HOME:-/home/$APP_USER}"
MULTICA_BIN_DIR="${MULTICA_BIN_DIR:-/opt/multica/bin}"

STATE_DIRS=(
    "$APP_HOME"
    "${MULTICA_WORKSPACES_ROOT:-/data/workspaces}"
    "${CBM_CACHE_DIR:-/data/codebase-memory}"
    "${CBM_RUNTIME_DIR:-/tmp/codebase-memory-runtime}"
    "$MULTICA_BIN_DIR"
)

run_as_root() {
    if [ -n "${PUID:-}" ] && [ "$PUID" != "$(id -u "$APP_USER")" ]; then
        log "Remappage uid $APP_USER -> $PUID"
        usermod -o -u "$PUID" "$APP_USER"
    fi
    if [ -n "${PGID:-}" ] && [ "$PGID" != "$(id -g "$APP_USER")" ]; then
        log "Remappage gid $APP_GROUP -> $PGID"
        groupmod -o -g "$PGID" "$APP_GROUP"
    fi

    local uid gid dir
    uid="$(id -u "$APP_USER")"
    gid="$(id -g "$APP_USER")"

    for dir in "${STATE_DIRS[@]}"; do
        mkdir -p "$dir"
        case "${MULTICA_FIX_PERMISSIONS:-shallow}" in
            off) ;;
            deep) chown -R "$uid:$gid" "$dir" ;;
            *)   gosu "$APP_USER" test -w "$dir" || chown "$uid:$gid" "$dir" ;;
        esac
    done

    chmod 700 "${CBM_CACHE_DIR:-/data/codebase-memory}" "${CBM_RUNTIME_DIR:-/tmp/codebase-memory-runtime}"

    exec gosu "$APP_USER" "$0" "$@"
}

register_mcp_json() {
    local config="$1"
    mkdir -p "$(dirname "$config")"
    [ -e "$config" ] || printf '{}\n' > "$config"
    jq -e . "$config" > /dev/null 2>&1 \
        || die "Configuration JSON invalide, abandon sans ecrasement : $config"

    local tmp="${config}.cbm.tmp"
    jq --arg cache "${CBM_CACHE_DIR:-/data/codebase-memory}" \
       --arg runtime "${CBM_RUNTIME_DIR:-/tmp/codebase-memory-runtime}" \
       --arg root "${CBM_ALLOWED_ROOT:-/data/workspaces}" \
       '.mcpServers["codebase-memory-mcp"] = {
            command: "/usr/local/bin/codebase-memory-mcp",
            args: [],
            env: { CBM_CACHE_DIR: $cache, CBM_RUNTIME_DIR: $runtime, CBM_ALLOWED_ROOT: $root }
        }' "$config" > "$tmp"
    mv "$tmp" "$config"
}

register_mcp_codex() {
    command -v codex > /dev/null 2>&1 || { log "codex absent, MCP non enregistre"; return 0; }
    codex mcp remove codebase-memory-mcp > /dev/null 2>&1 || true
    codex mcp add codebase-memory-mcp \
        --env "CBM_CACHE_DIR=${CBM_CACHE_DIR:-/data/codebase-memory}" \
        --env "CBM_RUNTIME_DIR=${CBM_RUNTIME_DIR:-/tmp/codebase-memory-runtime}" \
        --env "CBM_ALLOWED_ROOT=${CBM_ALLOWED_ROOT:-/data/workspaces}" \
        -- /usr/local/bin/codebase-memory-mcp
}

ensure_authenticated() {
    multica "${MULTICA_GLOBAL_FLAGS[@]}" auth status > /dev/null 2>&1 && return 0

    if [ -n "${MULTICA_TOKEN:-}" ]; then
        log "Authentification via MULTICA_TOKEN…"
        multica "${MULTICA_GLOBAL_FLAGS[@]}" login --token "$MULTICA_TOKEN" > /dev/null \
            || die "Echec de l'authentification avec MULTICA_TOKEN"
        return 0
    fi

    if [ "${MULTICA_WAIT_FOR_LOGIN:-true}" != "true" ]; then
        die "Non authentifie et MULTICA_TOKEN absent."
    fi

    log "-------------------------------------------------------------"
    log "Multica n'est pas authentifie."
    log "Option A : definir MULTICA_TOKEN=mcn_... puis redemarrer."
    log "Option B : docker compose exec multica-runtime multica login --token"
    log "Le conteneur reste en vie pour permettre le login interactif."
    log "-------------------------------------------------------------"
    exec sleep infinity
}

main() {
    [ "$(id -u)" = '0' ] && run_as_root "$@"

    MULTICA_GLOBAL_FLAGS=()
    [ -n "${MULTICA_PROFILE:-}" ] && MULTICA_GLOBAL_FLAGS+=(--profile "$MULTICA_PROFILE")

    command -v cursor-agent > /dev/null 2>&1 || log "AVERTISSEMENT: cursor-agent introuvable dans le PATH"

    register_mcp_json "$APP_HOME/.claude.json"
    register_mcp_json "$APP_HOME/.cursor/mcp.json"
    register_mcp_codex

    if [ -n "${GIT_USER_NAME:-}" ] && [ -n "${GIT_USER_EMAIL:-}" ]; then
        git config --global user.name "$GIT_USER_NAME"
        git config --global user.email "$GIT_USER_EMAIL"
    fi

    if [ "${1:-}" = "multica" ]; then
        ensure_authenticated
        set -- multica "${MULTICA_GLOBAL_FLAGS[@]}" "${@:2}"
    fi

    log "Demarrage : $*"
    exec "$@"
}

main "$@"

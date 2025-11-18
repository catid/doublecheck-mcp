#!/usr/bin/env bash
set -euo pipefail

# One-shot setup for the DoubleCheck MCP server.
# - Installs dependencies (requires uv)
# - Ensures a .env exists (will copy from .env.example if missing)
# - Adds an mcp_servers.doublecheck entry to ~/.codex/config.toml if absent

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODEX_HOME_DIR="${CODEX_HOME:-$HOME/.codex}"
CONFIG_FILE="$CODEX_HOME_DIR/config.toml"
SERVER_PATH="$SCRIPT_DIR/server.py"

ensure_env_file() {
  if [[ -f "$SCRIPT_DIR/.env" ]]; then
    return
  fi
  if [[ -f "$SCRIPT_DIR/.env.example" ]]; then
    cp "$SCRIPT_DIR/.env.example" "$SCRIPT_DIR/.env"
    echo "Created $SCRIPT_DIR/.env from .env.example. Please fill in your API keys."
  else
    cat >"$SCRIPT_DIR/.env" <<'EOF'
GOOGLE_API_KEY=replace-with-your-google-api-key
ANTHROPIC_API_KEY=replace-with-your-anthropic-api-key
EOF
    echo "Created $SCRIPT_DIR/.env. Please fill in your API keys."
  fi
}

load_env() {
  # shellcheck disable=SC1091
  set -a
  source "$SCRIPT_DIR/.env"
  set +a

  if [[ -z "${GOOGLE_API_KEY:-}" || -z "${ANTHROPIC_API_KEY:-}" ]]; then
    echo "Error: GOOGLE_API_KEY and ANTHROPIC_API_KEY must be set in $SCRIPT_DIR/.env"
    exit 1
  fi
}

install_deps() {
  if ! command -v uv >/dev/null 2>&1; then
    echo "Error: uv is required but not installed. See https://github.com/astral-sh/uv#getting-started"
    exit 1
  fi

  echo "Installing dependencies with uv…"
  uv sync
  RUN_CMD="uv"
  RUN_ARGS=(
    "run"
    "--with" "mcp"
    "--with" "google-generativeai"
    "--with" "anthropic"
    "python"
    "$SERVER_PATH"
  )
}

write_config() {
  mkdir -p "$CODEX_HOME_DIR"
  if [[ -f "$CONFIG_FILE" ]] && grep -q "\[mcp_servers\.doublecheck\]" "$CONFIG_FILE"; then
    echo "Config already contains [mcp_servers.doublecheck]; leaving it unchanged."
    return
  fi

  printf '\n[mcp_servers.doublecheck]\n' >>"$CONFIG_FILE"
  printf 'command = "%s"\n' "$RUN_CMD" >>"$CONFIG_FILE"
  printf 'args = [\n' >>"$CONFIG_FILE"
  for arg in "${RUN_ARGS[@]}"; do
    printf '  "%s",\n' "$arg" >>"$CONFIG_FILE"
  done
  printf ']\n' >>"$CONFIG_FILE"
  printf 'env = { GOOGLE_API_KEY = "%s", ANTHROPIC_API_KEY = "%s" }\n' "$GOOGLE_API_KEY" "$ANTHROPIC_API_KEY" >>"$CONFIG_FILE"
  printf 'web_search_request = true\n' >>"$CONFIG_FILE"

  echo "Added [mcp_servers.doublecheck] to $CONFIG_FILE"
}

main() {
  ensure_env_file
  load_env
  install_deps
  write_config
  echo "Setup complete. Make sure $SCRIPT_DIR/.env has valid API keys, then run: $RUN_CMD ${RUN_ARGS[*]}"
}

main "$@"

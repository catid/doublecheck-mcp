#!/usr/bin/env bash
set -euo pipefail

# One-shot setup for the DoubleCheck MCP server.
# - Installs dependencies (requires uv and python3)
# - Ensures a .env exists (will copy from .env.example if missing)
# - Writes/rewrites an mcp_servers.doublecheck entry to ~/.codex/config.toml with absolute paths

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODEX_HOME_DIR="${CODEX_HOME:-$HOME/.codex}"
CONFIG_FILE="$CODEX_HOME_DIR/config.toml"
SERVER_PATH="$SCRIPT_DIR/server.py"
RUN_CMD=""
RUN_ARGS=()

escape_toml() {
  # Escape backslashes and double quotes for TOML string literals.
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

ensure_python() {
  if ! command -v python3 >/dev/null 2>&1; then
    echo "Error: python3 is required but not installed. Install it (e.g., apt install python3 on Ubuntu) and rerun."
    exit 1
  fi
}

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
  if [[ "${GOOGLE_API_KEY}" == replace-with-* || "${ANTHROPIC_API_KEY}" == replace-with-* ]]; then
    echo "Error: Replace the placeholder API keys in $SCRIPT_DIR/.env with real values."
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
  local backup_made=false
  local backup_file=""
  if [[ -f "$CONFIG_FILE" ]]; then
    backup_file="$CONFIG_FILE.bak.$(date +%s)"
    cp "$CONFIG_FILE" "$backup_file"
    chmod 600 "$backup_file" 2>/dev/null || echo "Warning: Could not secure backup permissions for $backup_file" >&2
    backup_made=true
    echo "Backed up existing config to $backup_file"
  fi

  local tmp_config
  tmp_config="$(mktemp)" || { echo "Error: failed to create temp file for config update."; exit 1; }
  TMP_CONFIG_FILE="$tmp_config"
  trap '[[ -n "${TMP_CONFIG_FILE:-}" ]] && rm -f "$TMP_CONFIG_FILE"' EXIT

  if [[ -f "$CONFIG_FILE" ]]; then
    python3 - "$CONFIG_FILE" "$tmp_config" <<'PY'
import re
import sys

src, dst = sys.argv[1], sys.argv[2]
try:
    with open(src, "r", encoding="utf-8") as f:
        lines = f.readlines()
except FileNotFoundError:
    lines = []

out = []
skipping = False
section_header = re.compile(r"\[mcp_servers\.doublecheck\]\s*$")
for line in lines:
    if section_header.match(line):
        skipping = True
        continue
    if skipping and re.match(r"^\s*\[", line):
        skipping = False
    if not skipping:
        out.append(line)

with open(dst, "w", encoding="utf-8") as f:
    f.writelines(out)
PY
  else
    : >"$tmp_config"
  fi

  # Ensure a terminating newline before appending the new block
  if [[ -s "$tmp_config" ]] && [[ "$(tail -c 1 "$tmp_config")" != $'\n' ]]; then
    printf '\n' >>"$tmp_config"
  fi

  local escaped_cmd
  escaped_cmd="$(escape_toml "$RUN_CMD")"
  {
    printf '[mcp_servers.doublecheck]\n'
    printf 'command = "%s"\n' "$escaped_cmd"
    printf 'args = [\n'
    for arg in "${RUN_ARGS[@]}"; do
      printf '  "%s",\n' "$(escape_toml "$arg")"
    done
    printf ']\n'
    printf 'env = { GOOGLE_API_KEY = "%s", ANTHROPIC_API_KEY = "%s" }\n' "$(escape_toml "$GOOGLE_API_KEY")" "$(escape_toml "$ANTHROPIC_API_KEY")"
    printf 'web_search_request = true\n'
  } >>"$tmp_config"

  mv "$tmp_config" "$CONFIG_FILE"
  TMP_CONFIG_FILE=""
  echo "Wrote [mcp_servers.doublecheck] to $CONFIG_FILE (overwrote any existing entry)."
  if $backup_made; then
    echo "If you had custom settings, they are preserved in $backup_file"
  fi
  chmod 600 "$CONFIG_FILE" || echo "Warning: Could not secure permissions on $CONFIG_FILE" >&2
  echo "Note: API keys are stored in plain text in $CONFIG_FILE; permissions set to 600 to limit access."
}

main() {
  ensure_python
  ensure_env_file
  load_env
  install_deps
  write_config
  echo "Setup complete. Make sure $SCRIPT_DIR/.env has valid GOOGLE_API_KEY and ANTHROPIC_API_KEY values; Codex will start the DoubleCheck MCP server automatically (no need to run server.py directly)."
}

main "$@"

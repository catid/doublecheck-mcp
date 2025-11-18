# DoubleCheck MCP Server

`DoubleCheck` is a minimal Model Context Protocol (MCP) server that gives Codex access to two “second-opinion” reviewers:

- **Gemini 3 Pro** for plan critiques (`gemini_plan_check`)
- **Claude Sonnet 4.5** for code reviews (`sonnet_code_review`)

The server is stateless and uses API keys supplied via environment variables. Outbound network access is required so the tools can call the hosted models.

## Prerequisites

- Python 3.11+
- API keys exported in your shell:
  - `GOOGLE_API_KEY` for Gemini
  - `ANTHROPIC_API_KEY` for Claude
- `uv` (recommended) or `pip` to install dependencies

## Install

From this directory:

```bash
uv sync
# or: pip install -e .
```

One-shot setup (installs deps, copies .env, and writes the Codex MCP config entry):

```bash
./setup.sh
```

## Run the server

```bash
uv run server.py
# or: python server.py
```

You can also probe it with the MCP inspector:

```bash
npx @modelcontextprotocol/inspector uv run server.py
```

## Tools

- `gemini_plan_check(plan_description, expectations=None)`  
  Asks Gemini 3 Pro to flag gaps, risks, and missing edge cases. Returns a concise verdict with reasoning.

- `sonnet_code_review(code_snippet, context=None)`  
  Sends code to Claude Sonnet 4.5 for safety, correctness, and readability feedback.

## Configure Codex

Add a server entry to `~/.codex/config.toml` (update the path to `server.py`):

```toml
[mcp_servers.doublecheck]
command = "uv"
args = [
  "run",
  "--with", "mcp",
  "--with", "google-generativeai",
  "--with", "anthropic",
  "python",
  "/ABSOLUTE/PATH/TO/doublecheck-mcp/server.py",
]
env = {
  "GOOGLE_API_KEY" = "your-google-key",
  "ANTHROPIC_API_KEY" = "your-anthropic-key",
  # Optional: override model choices
  # "DOUBLECHECK_GEMINI_MODEL" = "gemini-3.0-pro-preview",
  # "DOUBLECHECK_SONNET_MODEL" = "claude-sonnet-4.5",
}
# Required so the tools can reach the hosted APIs
web_search_request = true
```

Then ask Codex to call the tools, e.g. “Run `gemini_plan_check` on this plan” or “Send this diff to `sonnet_code_review`.”

## Notes

- The server fails fast if API keys are missing and returns readable errors to the client.
- Defaults target `gemini-3.0-pro-preview` and `claude-sonnet-4.5`; override via env vars if your account uses different slugs.
- No data is stored on disk; requests are proxied directly to the model providers.

# DoubleCheck MCP Server

`DoubleCheck` is a minimal MCP server that gives the Codex CLI two “second-opinion” tools: a Gemini plan check (`gemini_plan_check`, default model `models/gemini-3-pro-preview`) and a Claude Sonnet code review (`sonnet_code_review`, default model `claude-sonnet-4-5-20250929`).

## Quick start

- Requirements: macOS/Linux shell, Python 3.11+, `uv`, outbound network access.
- From this directory, run `./setup.sh` (or `bash setup.sh` if the file isn’t executable). It installs dependencies with `uv`, ensures `.env` exists, and writes a `[mcp_servers.doublecheck]` entry to `~/.codex/config.toml` with absolute paths (creating the file if needed).
- Open `.env` and set your API keys (the file is already `.gitignore`’d):

  ```bash
  GOOGLE_API_KEY=your-google-api-key   # get from ai.google.dev
  ANTHROPIC_API_KEY=your-anthropic-key # get from console.anthropic.com
  ```
- Copy `AGENTS.md` into the repo where you’ll use Codex so it can load this MCP server (it’s the agent manifest), e.g. `cp /path/to/doublecheck-mcp/AGENTS.md /path/to/your/repo/AGENTS.md`.
- In that repo, run Codex pointing at the agents file, for example: `codex --agents ./AGENTS.md "review this diff"` (adjust the flag if your Codex CLI uses a different one). Codex will start the configured DoubleCheck server automatically—no need to run `server.py` manually.

## Tools

- `gemini_plan_check(plan_description, expectations=None, context=None)` — plan critique sent to Google’s Gemini model (default `models/gemini-3-pro-preview`). Optional `context` is wrapped in `<context>` delimiters and truncated to ~6000 characters to keep the plan and metadata distinct.
- `gemini_edit_plan_check(plan_description, file_contents, file_path=None, expectations=None, context=None)` — like `gemini_plan_check`, but includes the target file content (truncated) and optional path in the prompt so edit plans can be reviewed with the live file context.
- `sonnet_code_review(code_snippet, context=None)` — code review sent to Anthropic’s Claude Sonnet model (default `claude-sonnet-4-5-20250929`).

## Notes

- Defaults use `models/gemini-3-pro-preview` and `claude-sonnet-4-5-20250929`; override them with `DOUBLECHECK_GEMINI_MODEL` and `DOUBLECHECK_SONNET_MODEL` if your account uses different slugs.
- `setup.sh` installs via `uv` and wires Codex to this server; you don’t need to activate a virtualenv afterward.
- Setup script targets a Unix shell; on Windows use WSL or mirror the steps manually (`uv sync`, create `.env`, update `~/.codex/config.toml`).
- Keep `.env` private (already ignored by git). Lock it down with `chmod 600 .env`.
- The server keeps no state on disk; it just forwards requests to the hosted models. Ensure you’re comfortable sending the provided code/plans to Google and Anthropic. You can copy `AGENTS.md` anywhere because it relies on the absolute MCP entry written to `~/.codex/config.toml`.

Consider editing your ~/.codex/config.toml to add:

```code
[features]
web_search_request = true
```


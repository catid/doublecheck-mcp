# AGENTS.md instructions for doublecheck-mcp

- When proposing or executing implementation work in this repo, summarize the plan and call the `gemini_plan_check` MCP tool with the expectations; include its verdict in your response and incorporate any useful changes it suggests.
- When writing or modifying code/scripts, run both MCP tools on the changed snippets: use `sonnet_code_review` and also call `gemini_plan_check` (with a brief plan/expectations for the code change). Consider their feedback and incorporate beneficial improvements before finalizing your answer.
- Treat reviewer feedback as guidance, not ground truth: prefer substantive issues over minor nits (style-only suggestions are non-blocking) and avoid looping on cosmetic changes unless the user explicitly asks.
- Keep responses concise; surface tool outputs (especially verdicts, issues, and follow-up actions) clearly.

import asyncio
import html
import os
from textwrap import dedent
from typing import Optional

import anthropic
from anthropic.types import Message
import google.generativeai as genai
from mcp.server.fastmcp import FastMCP

mcp = FastMCP("DoubleCheck")

GEMINI_MODEL_ID = os.getenv("DOUBLECHECK_GEMINI_MODEL", "models/gemini-3-pro-preview")
SONNET_MODEL_ID = os.getenv("DOUBLECHECK_SONNET_MODEL", "claude-sonnet-4-5-20250929")
CONTEXT_MAX_CHARS = 6000  # ~1500 tokens (4 chars/token) to keep prompts bounded
PLAN_MAX_CHARS = 6000


def _require_env(var: str) -> str:
    value = os.getenv(var)
    if not value:
        raise RuntimeError(f"{var} is required for this tool but is not set.")
    return value


def _build_gemini_model():
    api_key = _require_env("GOOGLE_API_KEY")
    genai.configure(api_key=api_key)
    return genai.GenerativeModel(GEMINI_MODEL_ID)


def _build_anthropic_client() -> anthropic.Anthropic:
    api_key = _require_env("ANTHROPIC_API_KEY")
    return anthropic.Anthropic(api_key=api_key)


def _prepare_text(raw: str, max_chars: int) -> tuple[str, bool]:
    """
    Normalize/truncate text without splitting multibyte characters. Returns (text, was_truncated).
    """
    cleaned = raw.strip()
    if not cleaned:
        return "", False
    if len(cleaned) <= max_chars:
        return cleaned, False
    truncated = cleaned[:max_chars]
    return truncated, True


def _prepare_context(raw: str) -> tuple[str, bool]:
    """
    Normalize/truncate context without splitting multibyte characters.
    Returns (text, was_truncated).
    """
    return _prepare_text(raw, CONTEXT_MAX_CHARS)


def _format_plan_prompt(
    plan_description: str, expectations: Optional[str], context: Optional[str]
) -> str:
    trimmed_plan, plan_truncated = _prepare_text(plan_description, PLAN_MAX_CHARS)

    sections: list[str] = [
        "Act as a Principal Staff Engineer.",
        "Review the implementation plan for missing steps, incorrect assumptions, security risks, and edge cases.",
        "Respond concisely with bullet points of issues/improvements and a final line: Verdict: [APPROVED] or Verdict: [CHANGES REQUESTED].",
        "",
    ]

    if expectations and expectations.strip():
        sections.append("Specific concerns or constraints to keep in mind:")
        sections.append(html.escape(expectations.strip()))
        sections.append("")

    if context and context.strip():
        prepared_context, context_truncated = _prepare_context(context)
        sections.append("Context (delimited to avoid mixing with instructions):")
        sections.append("<context>")
        sections.append(html.escape(prepared_context))
        sections.append("</context>")
        if context_truncated:
            sections.append(f"(Context truncated to {CONTEXT_MAX_CHARS} characters.)")
        sections.append("")

    sections.append("Plan:")
    sections.append(html.escape(trimmed_plan))
    if plan_truncated:
        sections.append(f"(Plan truncated to {PLAN_MAX_CHARS} characters.)")

    return "\n".join(sections).strip()


@mcp.tool()
async def gemini_plan_check(
    plan_description: str, expectations: Optional[str] = None, context: Optional[str] = None
) -> str:
    """
    Ask Gemini 3 Pro to critique a plan for correctness, risks, and gaps.
    """
    if not plan_description.strip():
        return "Error: plan_description is empty."

    try:
        model = _build_gemini_model()
        prompt = _format_plan_prompt(plan_description, expectations, context)
        response = await model.generate_content_async(prompt)
        if response is None or not getattr(response, "text", None):
            return "Error: Gemini returned an empty or blocked response."
        return response.text
    except Exception as exc:  # pylint: disable=broad-except
        return f"Error calling Gemini ({type(exc).__name__})."


def _build_sonnet_request(code_snippet: str, context: Optional[str]) -> list[dict]:
    user_message = dedent(
        f"""
        Please review this code for correctness, safety, and maintainability.
        Point out bugs, risky assumptions, insecure patterns, and unclear naming.

        Code:
        ```
        {code_snippet}
        ```
        """
    ).strip()

    if context and context.strip():
        user_message = f"{user_message}\n\nAdditional context:\n{context.strip()}"

    return [{"role": "user", "content": user_message}]


def _extract_anthropic_text(response: Message) -> str:
    parts = []
    for block in response.content:
        text = getattr(block, "text", None)
        if text:
            parts.append(text)
    return "\n".join(parts).strip() or "Claude returned an empty response."


@mcp.tool()
async def sonnet_code_review(code_snippet: str, context: Optional[str] = None) -> str:
    """
    Ask Claude Sonnet 4.5 to review code for bugs, security issues, and readability.
    """
    if not code_snippet.strip():
        return "Error: code_snippet is empty."

    def _call_sonnet() -> Message:
        client = _build_anthropic_client()
        return client.messages.create(
            model=SONNET_MODEL_ID,
            max_tokens=1800,
            system="You are an expert code reviewer. Be concise and specific.",
            messages=_build_sonnet_request(code_snippet, context),
        )

    try:
        response = await asyncio.to_thread(_call_sonnet)
        return _extract_anthropic_text(response)
    except Exception as exc:  # pylint: disable=broad-except
        return f"Error calling Claude: {exc}"


if __name__ == "__main__":
    mcp.run()

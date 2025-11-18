import asyncio
import os
from textwrap import dedent
from typing import Optional

import anthropic
from anthropic.types import Message
import google.generativeai as genai
from mcp.server.fastmcp import FastMCP

mcp = FastMCP("DoubleCheck")

GEMINI_MODEL_ID = os.getenv("DOUBLECHECK_GEMINI_MODEL", "gemini-3.0-pro-preview")
SONNET_MODEL_ID = os.getenv("DOUBLECHECK_SONNET_MODEL", "claude-sonnet-4.5")


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


def _format_plan_prompt(plan_description: str, expectations: Optional[str]) -> str:
    if expectations:
        expectations_block = f"Specific concerns or constraints to keep in mind:\n{expectations.strip()}\n\n"
    else:
        expectations_block = ""
    return dedent(
        f"""
        Act as a Principal Staff Engineer.

        Review the implementation plan below for missing steps, incorrect assumptions, security risks, and edge cases.
        Respond concisely with:
        - Bullet points of any issues or improvements
        - A final verdict line in the form: Verdict: [APPROVED] or Verdict: [CHANGES REQUESTED]

        {expectations_block}Plan:
        {plan_description.strip()}
        """
    ).strip()


@mcp.tool()
async def gemini_plan_check(plan_description: str, expectations: Optional[str] = None) -> str:
    """
    Ask Gemini 3 Pro to critique a plan for correctness, risks, and gaps.
    """
    if not plan_description.strip():
        return "Error: plan_description is empty."

    try:
        model = _build_gemini_model()
        prompt = _format_plan_prompt(plan_description, expectations)
        response = await model.generate_content_async(prompt)
        return response.text or "Gemini returned an empty response."
    except Exception as exc:  # pylint: disable=broad-except
        return f"Error calling Gemini: {exc}"


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

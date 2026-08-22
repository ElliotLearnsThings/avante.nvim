"""Translate an :class:`AdapterRequest` into a Claude Code CLI invocation."""

from __future__ import annotations

import json
import os
from typing import TYPE_CHECKING, Any

if TYPE_CHECKING:
    from .protocol import AdapterRequest

#: Flags that pin the CLI into the machine-readable streaming mode we parse.
BASE_ARGS: tuple[str, ...] = (
    "--print",
    "--input-format",
    "stream-json",
    "--output-format",
    "stream-json",
    "--verbose",
)


def _append(args: list[str], flag: str, value: str | None) -> None:
    if value:
        args.extend((flag, value))


def build_args(request: AdapterRequest) -> list[str]:
    """Return the full argv (including the executable) for one turn."""
    args = [request.cli_path, *BASE_ARGS]

    if request.include_partial_messages:
        args.append("--include-partial-messages")

    _append(args, "--model", request.model)
    _append(args, "--fallback-model", request.fallback_model)
    _append(args, "--effort", request.effort)
    _append(args, "--system-prompt", request.system_prompt)
    _append(args, "--append-system-prompt", request.append_system_prompt)
    _append(args, "--permission-mode", request.permission_mode)
    _append(args, "--settings", request.settings)
    _append(args, "--setting-sources", request.setting_sources)
    _append(args, "--agents", request.agents)

    # `--resume` continues a previous Claude Code session; `--session-id` names a
    # brand new one. They are mutually exclusive, resume wins.
    if request.resume:
        _append(args, "--resume", request.resume)
    else:
        _append(args, "--session-id", request.session_id)

    if request.tools is not None:
        # An empty list means "no built-in tools", which the CLI spells as "".
        args.extend(("--tools", ",".join(request.tools) if request.tools else ""))
    if request.allowed_tools:
        args.extend(("--allowed-tools", ",".join(request.allowed_tools)))
    if request.disallowed_tools:
        args.extend(("--disallowed-tools", ",".join(request.disallowed_tools)))

    for directory in request.add_dirs:
        args.extend(("--add-dir", directory))
    for config in request.mcp_config:
        args.extend(("--mcp-config", config))
    if request.strict_mcp_config:
        args.append("--strict-mcp-config")

    if request.max_budget_usd is not None:
        args.extend(("--max-budget-usd", str(request.max_budget_usd)))

    args.extend(request.extra_args)
    return args


def build_env(request: AdapterRequest) -> dict[str, str]:
    """Return the environment for the CLI child process."""
    env = dict(os.environ)
    env.update(request.env)
    # Keeps the CLI's own npm/node chatter out of the NDJSON stream.
    env.setdefault("NODE_NO_WARNINGS", "1")
    return env


def _text_of(content: object) -> str:
    """Flatten an Anthropic content value down to plain text."""
    if isinstance(content, str):
        return content
    if not isinstance(content, list):
        return ""
    parts: list[str] = []
    for block in content:
        if not isinstance(block, dict):
            continue
        kind = block.get("type")
        if kind in {"text", "thinking"}:
            parts.append(str(block.get(kind) or ""))
        elif kind == "tool_result":
            parts.append(_text_of(block.get("content")))
        elif kind == "tool_use":
            parts.append(f"[called {block.get('name')} with {json.dumps(block.get('input') or {})}]")
    return "\n".join(part for part in parts if part)


def build_stdin_messages(request: AdapterRequest) -> list[dict[str, Any]]:
    """
    Render Avante's conversation as Claude Code stream-json input messages.

    The CLI only accepts *user* turns on stdin — it owns the assistant side of
    the transcript itself. When resuming an existing session the CLI already
    remembers the earlier turns, so only trailing user content is replayed.
    Otherwise prior assistant turns are folded into the prompt as quoted
    context so a fresh session still starts with the full history.
    """
    rendered: list[str] = []
    pending: list[str] = []

    for message in request.messages:
        if not isinstance(message, dict):
            continue
        text = _text_of(message.get("content"))
        if not text:
            continue
        role = message.get("role", "user")
        if role == "user":
            pending.append(text)
            continue
        # An assistant turn closes the preceding user turn(s) as history.
        rendered.extend(pending)
        pending = []
        if not request.resume:
            rendered.append(f"<previous_assistant_response>\n{text}\n</previous_assistant_response>")

    # When resuming, everything before the last assistant turn is already in
    # the session, so only the trailing user content is replayed.
    prompt = "\n\n".join(pending) if request.resume else "\n\n".join([*rendered, *pending])

    if not prompt.strip():
        return []
    return [{"type": "user", "message": {"role": "user", "content": [{"type": "text", "text": prompt}]}}]

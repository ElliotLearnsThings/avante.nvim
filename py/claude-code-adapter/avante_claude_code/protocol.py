"""
Wire types shared between the Neovim provider and the Claude Code adapter.

The adapter speaks two protocols:

* **inbound** — a single JSON object on stdin, described by :class:`AdapterRequest`.
  It is produced by ``lua/avante/providers/claude_code.lua``.
* **outbound** — Anthropic Messages API server-sent events on stdout, so that the
  Lua side can reuse the exact same streaming parser it would use for a direct
  ``https://api.anthropic.com/v1/messages`` request.
"""

from __future__ import annotations

import json
import sys
from dataclasses import dataclass, field
from typing import Any, TextIO

#: Emitted alongside the standard Anthropic events so the Lua side can learn the
#: Claude Code session id and reuse it for the next turn via ``--resume``.
SESSION_EVENT = "avante_session"

#: Emitted for Claude Code's *own* tool activity. Avante must not execute these,
#: they are informational, so they travel under a private event name.
TOOL_ACTIVITY_EVENT = "avante_tool_activity"

#: Emitted once per turn with what this Claude Code session actually has:
#: its slash commands, skills, plugins, MCP servers, tools and auth source.
CAPABILITIES_EVENT = "avante_capabilities"


@dataclass
class AdapterRequest:
    """Everything the adapter needs to drive one Claude Code turn."""

    messages: list[dict[str, Any]] = field(default_factory=list)
    system_prompt: str | None = None
    append_system_prompt: str | None = None
    model: str | None = None
    fallback_model: str | None = None
    effort: str | None = None
    cwd: str | None = None
    resume: str | None = None
    session_id: str | None = None
    permission_mode: str | None = None
    tools: list[str] | None = None
    allowed_tools: list[str] | None = None
    disallowed_tools: list[str] | None = None
    add_dirs: list[str] = field(default_factory=list)
    mcp_config: list[str] = field(default_factory=list)
    strict_mcp_config: bool = False
    plugin_dirs: list[str] = field(default_factory=list)
    plugin_urls: list[str] = field(default_factory=list)
    disable_slash_commands: bool = False
    settings: str | None = None
    setting_sources: str | None = None
    agents: str | None = None
    max_budget_usd: float | None = None
    include_partial_messages: bool = True
    emit_tool_activity: bool = True
    cli_path: str = "claude"
    extra_args: list[str] = field(default_factory=list)
    env: dict[str, str] = field(default_factory=dict)
    timeout: float | None = None

    @classmethod
    def from_json(cls, raw: str) -> AdapterRequest:
        """Build a request from the JSON blob handed to us on stdin."""
        payload = json.loads(raw)
        if not isinstance(payload, dict):
            msg = "adapter request must be a JSON object"
            raise TypeError(msg)
        known = set(cls.__dataclass_fields__)
        return cls(**{k: v for k, v in payload.items() if k in known})


class SSEWriter:
    """Writes Anthropic-shaped server-sent events, unbuffered."""

    def __init__(self, stream: TextIO | None = None) -> None:
        """Wrap ``stream`` (default stdout) as an SSE sink."""
        self._stream = stream if stream is not None else sys.stdout

    def emit(self, event: dict[str, Any], name: str | None = None) -> None:
        """Emit one ``event:``/``data:`` pair and flush immediately."""
        event_name = name or str(event.get("type", "message"))
        self._stream.write(f"event: {event_name}\n")
        self._stream.write(f"data: {json.dumps(event, separators=(',', ':'))}\n\n")
        self._stream.flush()

    def error(self, message: str, kind: str = "adapter_error") -> None:
        """Emit an Anthropic-shaped error event."""
        self.emit({"type": "error", "error": {"type": kind, "message": message}}, name="error")

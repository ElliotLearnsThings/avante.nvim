"""
Merge Claude Code's NDJSON stream into a single Anthropic message stream.

Claude Code runs a full agentic loop for one user turn: it may emit several
assistant messages, each with its own ``message_start``/``message_stop`` and an
intermediate ``stop_reason`` of ``tool_use``. Avante expects *one* streamed
assistant message. :class:`StreamTranslator` therefore:

* emits a single ``message_start`` and a single terminal ``message_delta`` /
  ``message_stop`` pair, synthesised from the CLI's final ``result`` record;
* renumbers content blocks so indices stay unique across the merged message;
* rewrites Claude Code's own ``tool_use`` blocks (and the matching
  ``tool_result`` payloads) into readable text, because those tools are executed
  by the CLI itself and must never be handed to Avante's tool runner;
* accumulates token usage across every underlying request.
"""

from __future__ import annotations

import json
from typing import Any

from .protocol import CAPABILITIES_EVENT, SESSION_EVENT, SSEWriter

#: How much of a tool result is echoed into the transcript.
TOOL_RESULT_PREVIEW_LINES = 6
TOOL_RESULT_PREVIEW_CHARS = 500

#: Longest tool-argument hint shown next to a tool name.
TOOL_HINT_CHARS = 120

#: Prefix Claude Code gives tools bridged from Avante. Neovim renders those
#: itself, with its own diff review and confirmations, so echoing them here
#: would show every call twice.
BRIDGED_TOOL_PREFIX = "mcp__avante__"

#: Fields of the CLI's `init` record that describe what this session can do.
#: They are forwarded so Neovim can offer the same slash commands, skills and
#: plugins the CLI itself would.
_CAPABILITY_KEYS = (
    "slash_commands",
    "skills",
    "agents",
    "plugins",
    "tools",
    "mcp_servers",
    "model",
    "permissionMode",
    "apiKeySource",
    "claude_code_version",
    "cwd",
)

#: Generated tokens genuinely accumulate across the CLI's internal requests —
#: every one of them was produced.
_SUMMED_USAGE_KEYS = ("output_tokens",)

#: Prompt-side counters describe how big the context *was* for one request, not
#: a running total. Summing them across an agentic loop counts the same context
#: once per tool call, which Avante then reads as the conversation approaching
#: its context window and compacts for no reason. The largest single request is
#: the honest figure.
_PEAK_USAGE_KEYS = (
    "input_tokens",
    "cache_creation_input_tokens",
    "cache_read_input_tokens",
)

_USAGE_KEYS = _SUMMED_USAGE_KEYS + _PEAK_USAGE_KEYS


def _truncate(text: str) -> str:
    lines = text.splitlines()
    if len(lines) > TOOL_RESULT_PREVIEW_LINES:
        lines = [*lines[:TOOL_RESULT_PREVIEW_LINES], "…"]
    preview = "\n".join(lines)
    if len(preview) > TOOL_RESULT_PREVIEW_CHARS:
        preview = preview[:TOOL_RESULT_PREVIEW_CHARS] + "…"
    return preview


def _render_call(name: str, tool_input: dict[str, Any]) -> str:
    """Render a tool call the way the Claude Code TUI does."""
    hint = ""
    for key in ("file_path", "path", "command", "pattern", "url", "description"):
        value = tool_input.get(key)
        if isinstance(value, str) and value:
            hint = value if len(value) <= TOOL_HINT_CHARS else value[:TOOL_HINT_CHARS] + "…"
            break
    return f"\n⏺ {name}({hint})\n" if hint else f"\n⏺ {name}\n"


class StreamTranslator:
    """Stateful translator from CLI NDJSON records to Anthropic SSE events."""

    def __init__(self, writer: SSEWriter, *, emit_tool_activity: bool = True) -> None:
        """Translate into ``writer``; set ``emit_tool_activity`` to show CLI tool calls."""
        self._writer = writer
        self._emit_tool_activity = emit_tool_activity
        self._started = False
        self._finished = False
        self._session_id: str | None = None
        self._next_index = 0
        # Message ids seen as a live stream. Anything else the CLI reports as a
        # finished assistant message was produced locally (a slash command such
        # as /context) and never streamed, so it has to be replayed by hand.
        self._streamed_message_ids: set[str] = set()
        # CLI block index -> our block index, for the message being streamed.
        self._index_map: dict[int, int] = {}
        # CLI block index -> accumulated partial JSON, for tool_use blocks.
        self._tool_blocks: dict[int, dict[str, Any]] = {}
        # tool_use ids that Avante is rendering itself.
        self._bridged_tool_ids: set[str] = set()
        self._usage: dict[str, int] = dict.fromkeys(_USAGE_KEYS, 0)
        self._stop_reason = "end_turn"

    @property
    def finished(self) -> bool:
        """Whether the merged message has already been closed off."""
        return self._finished

    @property
    def session_id(self) -> str | None:
        """The Claude Code session id, once the CLI has announced it."""
        return self._session_id

    # -- record dispatch ---------------------------------------------------

    def handle(self, record: dict[str, Any]) -> None:
        """Process one NDJSON record from the CLI."""
        kind = record.get("type")
        if kind == "system":
            self._handle_system(record)
        elif kind == "stream_event":
            event = record.get("event")
            if isinstance(event, dict):
                self._handle_stream_event(event)
        elif kind == "assistant":
            self._handle_unstreamed_assistant(record)
        elif kind == "user":
            self._handle_tool_results(record)
        elif kind == "result":
            self._handle_result(record)

    def _handle_system(self, record: dict[str, Any]) -> None:
        if record.get("subtype") != "init":
            return
        session_id = record.get("session_id")
        if isinstance(session_id, str):
            self._session_id = session_id
            self._writer.emit({"type": SESSION_EVENT, "session_id": session_id}, name=SESSION_EVENT)
        capabilities = {key: record[key] for key in _CAPABILITY_KEYS if key in record}
        if capabilities:
            capabilities["type"] = CAPABILITIES_EVENT
            self._writer.emit(capabilities, name=CAPABILITIES_EVENT)

    # -- streamed assistant content ---------------------------------------

    def _handle_stream_event(self, event: dict[str, Any]) -> None:
        handlers = {
            "message_start": self._on_message_start,
            "content_block_start": self._on_block_start,
            "content_block_delta": self._on_block_delta,
            "content_block_stop": self._on_block_stop,
            "message_delta": self._on_message_delta,
        }
        handler = handlers.get(str(event.get("type")))
        if handler is not None:
            handler(event)

    def _on_message_start(self, event: dict[str, Any]) -> None:
        # Later assistant messages in the same turn continue the merged one.
        self._index_map = {}
        self._tool_blocks = {}
        message_id = (event.get("message") or {}).get("id")
        if isinstance(message_id, str):
            self._streamed_message_ids.add(message_id)
        if self._started:
            return
        self._started = True
        message = dict(event.get("message") or {})
        message["content"] = []
        message["stop_reason"] = None
        self._writer.emit({"type": "message_start", "message": message})

    def _on_block_start(self, event: dict[str, Any]) -> None:
        source_index = int(event.get("index", 0))
        block = dict(event.get("content_block") or {})
        if block.get("type") == "tool_use":
            # Swallowed: Claude Code executes this itself. We buffer it and
            # replay it as text once the arguments have finished streaming.
            name = str(block.get("name") or "tool")
            self._tool_blocks[source_index] = {"name": name, "json": "", "id": block.get("id")}
            if name.startswith(BRIDGED_TOOL_PREFIX) and block.get("id"):
                self._bridged_tool_ids.add(str(block["id"]))
            return
        index = self._claim_index(source_index)
        self._writer.emit({"type": "content_block_start", "index": index, "content_block": block})

    def _on_block_delta(self, event: dict[str, Any]) -> None:
        source_index = int(event.get("index", 0))
        delta = event.get("delta") or {}
        pending = self._tool_blocks.get(source_index)
        if pending is not None:
            if delta.get("type") == "input_json_delta":
                pending["json"] += str(delta.get("partial_json") or "")
            return
        index = self._index_map.get(source_index)
        if index is None:
            return
        self._writer.emit({"type": "content_block_delta", "index": index, "delta": delta})

    def _on_block_stop(self, event: dict[str, Any]) -> None:
        source_index = int(event.get("index", 0))
        pending = self._tool_blocks.pop(source_index, None)
        if pending is not None:
            self._emit_tool_call(pending)
            return
        index = self._index_map.pop(source_index, None)
        if index is None:
            return
        self._writer.emit({"type": "content_block_stop", "index": index})

    def _on_message_delta(self, event: dict[str, Any]) -> None:
        # Only usage is kept; the stop reason is decided by the final result.
        self._accumulate(event.get("usage"))

    # -- tool activity -----------------------------------------------------

    def _emit_tool_call(self, pending: dict[str, Any]) -> None:
        if not self._emit_tool_activity:
            return
        if str(pending["name"]).startswith(BRIDGED_TOOL_PREFIX):
            return
        try:
            tool_input = json.loads(pending["json"]) if pending["json"] else {}
        except json.JSONDecodeError:
            tool_input = {}
        if not isinstance(tool_input, dict):
            tool_input = {}
        self._emit_text(_render_call(str(pending["name"]), tool_input))

    def _handle_unstreamed_assistant(self, record: dict[str, Any]) -> None:
        """
        Replay an assistant message that never came through as stream events.

        Claude Code answers its local slash commands itself, emitting a finished
        assistant message with no ``message_start``. Without this the reply would
        be silently dropped.
        """
        message = record.get("message") or {}
        message_id = message.get("id")
        if isinstance(message_id, str) and message_id in self._streamed_message_ids:
            return
        content = message.get("content")
        if not isinstance(content, list):
            return
        for block in content:
            if not isinstance(block, dict):
                continue
            if block.get("type") == "text":
                text = str(block.get("text") or "")
                if text:
                    self._ensure_started(message)
                    self._emit_text(text)
            elif block.get("type") == "tool_use" and self._emit_tool_activity:
                self._ensure_started(message)
                tool_input = block.get("input")
                self._emit_text(_render_call(str(block.get("name") or "tool"), tool_input if isinstance(tool_input, dict) else {}))

    def _ensure_started(self, message: dict[str, Any] | None = None) -> None:
        """Open the merged message if nothing has opened it yet."""
        if self._started:
            return
        self._started = True
        started = dict(message or {})
        started["content"] = []
        started["stop_reason"] = None
        started.setdefault("role", "assistant")
        started.setdefault("type", "message")
        self._writer.emit({"type": "message_start", "message": started})

    def _handle_tool_results(self, record: dict[str, Any]) -> None:
        if not self._emit_tool_activity or not self._started:
            return
        content = (record.get("message") or {}).get("content")
        if not isinstance(content, list):
            return
        for block in content:
            if not isinstance(block, dict) or block.get("type") != "tool_result":
                continue
            if str(block.get("tool_use_id")) in self._bridged_tool_ids:
                continue
            body = block.get("content")
            if isinstance(body, list):
                body = "\n".join(str(part.get("text", "")) for part in body if isinstance(part, dict))
            text = _truncate(str(body or "")).strip()
            marker = "⎿ error" if block.get("is_error") else "⎿"
            self._emit_text(f"  {marker} {text}\n" if text else f"  {marker}\n")

    def _emit_text(self, text: str) -> None:
        """Emit a standalone text content block carrying ``text``."""
        index = self._next_index
        self._next_index += 1
        self._writer.emit({"type": "content_block_start", "index": index, "content_block": {"type": "text", "text": ""}})
        self._writer.emit(
            {"type": "content_block_delta", "index": index, "delta": {"type": "text_delta", "text": text}},
        )
        self._writer.emit({"type": "content_block_stop", "index": index})

    # -- termination -------------------------------------------------------

    def _handle_result(self, record: dict[str, Any]) -> None:
        self._accumulate(record.get("usage"))
        if record.get("is_error"):
            subtype = str(record.get("subtype") or "error")
            message = str(record.get("result") or record.get("api_error_status") or subtype)
            self._writer.error(message, kind=subtype)
            self._finished = True
            return
        stop_reason = record.get("stop_reason")
        if isinstance(stop_reason, str) and stop_reason:
            self._stop_reason = stop_reason
        self.finish()

    def finish(self) -> None:
        """Close the merged message, emitting a start first if nothing streamed."""
        if self._finished:
            return
        self._finished = True
        self._ensure_started()
        for index in sorted(self._index_map.values()):
            self._writer.emit({"type": "content_block_stop", "index": index})
        self._index_map = {}
        self._writer.emit(
            {
                "type": "message_delta",
                "delta": {"stop_reason": self._stop_reason, "stop_sequence": None},
                "usage": dict(self._usage),
            },
        )
        self._writer.emit({"type": "message_stop"})

    def _claim_index(self, source_index: int) -> int:
        index = self._next_index
        self._next_index += 1
        self._index_map[source_index] = index
        return index

    def _accumulate(self, usage: object) -> None:
        if not isinstance(usage, dict):
            return
        for key in _SUMMED_USAGE_KEYS:
            value = usage.get(key)
            if isinstance(value, int):
                self._usage[key] += value
        for key in _PEAK_USAGE_KEYS:
            value = usage.get(key)
            if isinstance(value, int):
                self._usage[key] = max(self._usage[key], value)

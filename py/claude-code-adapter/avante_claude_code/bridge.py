"""
The adapter half of the Avante tool bridge.

Claude Code spawns :mod:`avante_claude_code.mcp_server`, which connects here
over a Unix socket. This module answers ``tools/list`` from the schemas Neovim
sent with the request, and turns ``tools/call`` into a round trip:

    MCP server --socket--> bridge --stdout--> Neovim --stdin--> bridge

Each call blocks its own socket thread until Neovim answers, so several tools
can be in flight at once without the CLI's own concurrency being serialised.
"""

from __future__ import annotations

import contextlib
import json
import socket
import tempfile
import threading
import uuid
from pathlib import Path
from typing import TYPE_CHECKING, Any

if TYPE_CHECKING:
    from collections.abc import Callable

#: How long a single tool call may take before we give up on Neovim.
TOOL_CALL_TIMEOUT = 600.0


class PendingCall:
    """One in-flight tool call, waiting on Neovim."""

    def __init__(self) -> None:
        """Create an unresolved call."""
        self.event = threading.Event()
        self.response: dict[str, Any] = {}

    def resolve(self, response: dict[str, Any]) -> None:
        """Hand the call its result and wake whoever is waiting."""
        self.response = response
        self.event.set()

    def wait(self, timeout: float = TOOL_CALL_TIMEOUT) -> dict[str, Any]:
        """Block until resolved, or report a timeout as a tool error."""
        if not self.event.wait(timeout):
            return {"error": f"Neovim did not answer within {timeout:.0f}s"}
        return self.response


class ToolBridge:
    """A Unix-socket server that relays Avante's tools to Claude Code."""

    def __init__(self, tools: list[dict[str, Any]], emit: Callable[[dict[str, Any]], None]) -> None:
        """
        Serve ``tools`` and report calls through ``emit``.

        ``emit`` is handed a request describing the call; the answer arrives
        later via :meth:`resolve`.
        """
        self._tools = tools
        self._emit = emit
        self._pending: dict[str, PendingCall] = {}
        self._lock = threading.Lock()
        self._next_id = 0
        # A bridge lives for one Avante turn, but `session_ctx` — and the diff
        # bookkeeping keyed on tool_use_id — lives for the whole conversation.
        # A per-bridge counter alone would restart at 1 every turn and collide,
        # which silently drops the second edit to a file while still reporting
        # success. The prefix makes ids unique across turns and processes.
        self._id_prefix = uuid.uuid4().hex[:8]
        self._closed = threading.Event()
        # A socket in the abstract filesystem would be simpler, but is Linux
        # only; a temp directory keeps macOS working too.
        self._dir = Path(tempfile.mkdtemp(prefix="avante-bridge-"))
        self.path = str(self._dir / "bridge.sock")
        self._server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self._server.bind(self.path)
        self._server.listen(8)
        self._threads: list[threading.Thread] = []

    def start(self) -> None:
        """Begin accepting connections from the MCP server."""
        thread = threading.Thread(target=self._accept_loop, daemon=True)
        thread.start()
        self._threads.append(thread)

    def resolve(self, call_id: str, response: dict[str, Any]) -> bool:
        """Deliver Neovim's answer for ``call_id``. False if it is unknown."""
        with self._lock:
            pending = self._pending.pop(call_id, None)
        if pending is None:
            return False
        pending.resolve(response)
        return True

    def close(self) -> None:
        """Stop serving and fail any call still waiting."""
        self._closed.set()
        with contextlib.suppress(OSError):
            self._server.close()
        with self._lock:
            waiting = list(self._pending.values())
            self._pending.clear()
        for pending in waiting:
            pending.resolve({"error": "the turn ended before this tool finished"})
        with contextlib.suppress(OSError):
            Path(self.path).unlink()
        with contextlib.suppress(OSError):
            self._dir.rmdir()

    # -- internals ---------------------------------------------------------

    def _accept_loop(self) -> None:
        while not self._closed.is_set():
            try:
                connection, _ = self._server.accept()
            except OSError:
                return
            thread = threading.Thread(target=self._serve_connection, args=(connection,), daemon=True)
            thread.start()
            self._threads.append(thread)

    def _serve_connection(self, connection: socket.socket) -> None:
        with connection:
            reader = connection.makefile("r", encoding="utf-8")
            writer = connection.makefile("w", encoding="utf-8")
            for raw in reader:
                line = raw.strip()
                if not line:
                    continue
                try:
                    request = json.loads(line)
                except json.JSONDecodeError:
                    continue
                response = self._dispatch(request)
                try:
                    writer.write(json.dumps(response) + "\n")
                    writer.flush()
                except (BrokenPipeError, ValueError):
                    return

    def _dispatch(self, request: dict[str, Any]) -> dict[str, Any]:
        kind = request.get("type")
        if kind == "tools/list":
            return {"tools": self._tools}
        if kind == "tools/call":
            return self._call(str(request.get("name") or ""), request.get("arguments") or {})
        return {"error": f"unknown bridge request: {kind}"}

    def _call(self, name: str, arguments: dict[str, Any]) -> dict[str, Any]:
        pending = PendingCall()
        with self._lock:
            self._next_id += 1
            call_id = f"avante-{self._id_prefix}-{self._next_id}"
            self._pending[call_id] = pending
        self._emit({"id": call_id, "name": name, "input": arguments})
        return pending.wait()

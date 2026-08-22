"""
MCP stdio server that hands Avante's own tools to Claude Code.

Claude Code spawns this process itself (via ``--mcp-config``) and speaks
JSON-RPC to it over stdio. This process owns no tool logic: it forwards every
request across a Unix socket to the adapter, which relays it to Neovim, where
the real Lua tool runs.

    claude CLI  --stdio-->  mcp_server  --socket-->  adapter  --stdout-->  Neovim
"""

from __future__ import annotations

import argparse
import contextlib
import json
import socket
import sys
from typing import Any

#: JSON-RPC error code for "the server broke", per the MCP spec's use of the
#: standard JSON-RPC range.
INTERNAL_ERROR = -32603

#: Protocol revision assumed when the client does not name one.
DEFAULT_PROTOCOL_VERSION = "2024-11-05"

#: A JSON-RPC id is a string, a number, or absent on a notification.
RequestId = "str | int | None"


class BridgeClient:
    """A line-delimited JSON channel to the adapter."""

    def __init__(self, path: str) -> None:
        """Connect to the adapter's socket at ``path``."""
        self._sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self._sock.connect(path)
        self._reader = self._sock.makefile("r", encoding="utf-8")
        self._writer = self._sock.makefile("w", encoding="utf-8")

    def request(self, payload: dict[str, Any]) -> dict[str, Any]:
        """Send one request and block until its reply arrives."""
        self._writer.write(json.dumps(payload) + "\n")
        self._writer.flush()
        line = self._reader.readline()
        if not line:
            msg = "adapter closed the tool bridge"
            raise ConnectionError(msg)
        return json.loads(line)

    def close(self) -> None:
        """Close the channel, ignoring an already-broken socket."""
        with contextlib.suppress(OSError):
            self._sock.close()


def _send(message: dict[str, Any]) -> None:
    sys.stdout.write(json.dumps(message) + "\n")
    sys.stdout.flush()


def _reply(request_id: RequestId, result: dict[str, Any]) -> None:
    _send({"jsonrpc": "2.0", "id": request_id, "result": result})


def _fail(request_id: RequestId, message: str) -> None:
    _send({"jsonrpc": "2.0", "id": request_id, "error": {"code": INTERNAL_ERROR, "message": message}})


def _tool_error(request_id: RequestId, message: str) -> None:
    """
    Report a failed tool call as MCP tool content, not a protocol error.

    The model can read and react to this; a JSON-RPC error it cannot.
    """
    _reply(request_id, {"content": [{"type": "text", "text": message}], "isError": True})


def _handle_initialize(request_id: RequestId, params: dict[str, Any]) -> None:
    _reply(
        request_id,
        {
            "protocolVersion": params.get("protocolVersion", DEFAULT_PROTOCOL_VERSION),
            "capabilities": {"tools": {"listChanged": False}},
            "serverInfo": {"name": "avante", "version": "0.1.0"},
        },
    )


def serve(bridge: BridgeClient) -> int:
    """Run the JSON-RPC loop until the client closes stdin."""
    for raw in sys.stdin:
        line = raw.strip()
        if not line:
            continue
        try:
            message = json.loads(line)
        except json.JSONDecodeError:
            continue
        if not isinstance(message, dict):
            continue

        request_id = message.get("id")
        method = message.get("method")
        params = message.get("params") or {}

        if method == "initialize":
            _handle_initialize(request_id, params)
        elif method == "tools/list":
            _handle_list(bridge, request_id)
        elif method == "tools/call":
            _handle_call(bridge, request_id, params)
        elif request_id is not None:
            # Anything else with an id still needs an answer, or the client hangs.
            _reply(request_id, {})
        # Messages without an id are notifications; they take no reply.
    return 0


def _handle_list(bridge: BridgeClient, request_id: RequestId) -> None:
    try:
        response = bridge.request({"type": "tools/list"})
    except (ConnectionError, OSError, json.JSONDecodeError) as exc:
        _fail(request_id, f"could not reach Neovim: {exc}")
        return
    _reply(request_id, {"tools": response.get("tools", [])})


def _handle_call(bridge: BridgeClient, request_id: RequestId, params: dict[str, Any]) -> None:
    name = params.get("name")
    try:
        response = bridge.request(
            {"type": "tools/call", "name": name, "arguments": params.get("arguments") or {}},
        )
    except (ConnectionError, OSError, json.JSONDecodeError) as exc:
        _tool_error(request_id, f"could not reach Neovim: {exc}")
        return

    if response.get("error"):
        _tool_error(request_id, str(response["error"]))
        return
    content = response.get("content")
    _reply(request_id, {"content": [{"type": "text", "text": "" if content is None else str(content)}]})


def main(argv: list[str] | None = None) -> int:
    """Entry point: connect to the adapter, then serve MCP over stdio."""
    parser = argparse.ArgumentParser(description="Avante tool bridge for Claude Code")
    parser.add_argument("--socket", required=True, help="Path to the adapter's tool-bridge socket")
    args = parser.parse_args(argv)

    try:
        bridge = BridgeClient(args.socket)
    except OSError as exc:
        sys.stderr.write(f"avante tool bridge unavailable: {exc}\n")
        return 1
    try:
        return serve(bridge)
    finally:
        bridge.close()


if __name__ == "__main__":
    sys.exit(main())

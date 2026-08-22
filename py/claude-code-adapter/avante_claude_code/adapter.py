"""Process orchestration: run the Claude Code CLI and stream its turn back."""

from __future__ import annotations

import contextlib
import json
import os
import signal
import subprocess
import sys
import threading
from typing import IO, Any

from .cli import build_args, build_env, build_stdin_messages
from .probe import probe
from .protocol import AdapterRequest, SSEWriter
from .translator import StreamTranslator

#: Tail of the CLI's stderr kept around to explain a non-zero exit.
STDERR_TAIL_LINES = 20


def _pump_stderr(stream: IO[str], sink: list[str]) -> None:
    for line in stream:
        sink.append(line.rstrip("\n"))
        del sink[:-STDERR_TAIL_LINES]


def _write_prompt(process: subprocess.Popen[str], request: AdapterRequest) -> None:
    """Feed the turn to the CLI, then close stdin so it runs to completion."""
    stdin = process.stdin
    if stdin is None:
        return
    try:
        for message in build_stdin_messages(request):
            stdin.write(json.dumps(message, separators=(",", ":")) + "\n")
        stdin.flush()
    except (BrokenPipeError, ValueError):
        pass
    finally:
        with contextlib.suppress(BrokenPipeError, ValueError):
            stdin.close()


def run(request: AdapterRequest, writer: SSEWriter | None = None) -> int:
    """
    Run one Claude Code turn, translating its output to Anthropic SSE.

    Returns the exit code to hand back to the shell.
    """
    writer = writer if writer is not None else SSEWriter()
    translator = StreamTranslator(writer, emit_tool_activity=request.emit_tool_activity)

    try:
        process = subprocess.Popen(
            build_args(request),
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=build_env(request),
            cwd=request.cwd or None,
            text=True,
            bufsize=1,
            start_new_session=True,
        )
    except FileNotFoundError:
        writer.error(
            f"Claude Code CLI not found: {request.cli_path!r}. Install it from https://claude.com/claude-code or set providers.claude_code.cli_path.",
            kind="cli_not_found",
        )
        return 127
    except OSError as exc:
        writer.error(f"failed to start Claude Code CLI: {exc}", kind="spawn_failed")
        return 1

    stderr_tail: list[str] = []
    stderr_pump: threading.Thread | None = None
    if process.stderr is not None:
        stderr_pump = threading.Thread(target=_pump_stderr, args=(process.stderr, stderr_tail), daemon=True)
        stderr_pump.start()

    timer: threading.Timer | None = None
    if request.timeout and request.timeout > 0:
        timer = threading.Timer(request.timeout, lambda: _terminate(process))
        timer.daemon = True
        timer.start()

    threading.Thread(target=_write_prompt, args=(process, request), daemon=True).start()

    try:
        _consume(process, translator, writer)
    finally:
        if timer is not None:
            timer.cancel()
        code = process.wait()
        if stderr_pump is not None:
            stderr_pump.join(timeout=1)

    if code != 0 and not translator.finished:
        detail = "\n".join(stderr_tail).strip() or f"Claude Code CLI exited with status {code}"
        writer.error(detail, kind="cli_failed")
        return code

    # A clean exit that never produced a `result` record still needs closing.
    translator.finish()
    return 0


def _consume(process: subprocess.Popen[str], translator: StreamTranslator, writer: SSEWriter) -> None:
    """Read the CLI's NDJSON stdout and drive the translator."""
    stdout = process.stdout
    if stdout is None:
        return
    for line in stdout:
        text = line.strip()
        if not text:
            continue
        try:
            record: Any = json.loads(text)
        except json.JSONDecodeError:
            # Anything non-JSON on stdout is CLI noise, not part of the turn.
            continue
        if isinstance(record, dict):
            try:
                translator.handle(record)
            except Exception as exc:
                writer.error(f"failed to translate CLI record: {exc}", kind="translate_failed")
                return


def _terminate(process: subprocess.Popen[str]) -> None:
    """Kill the CLI and everything it spawned."""
    try:
        os.killpg(os.getpgid(process.pid), signal.SIGTERM)
    except (ProcessLookupError, PermissionError, OSError):
        process.terminate()


def main(argv: list[str] | None = None) -> int:
    """
    Entry point.

    With ``--probe`` it answers a few local CLI questions as one JSON object and
    exits; otherwise it reads one request from stdin and streams one turn.
    """
    argv = list(sys.argv[1:] if argv is None else argv)
    if "--probe" in argv:
        return _probe(argv)
    raw = sys.stdin.read()
    writer = SSEWriter()
    if not raw.strip():
        writer.error("no request received on stdin", kind="empty_request")
        return 2
    try:
        request = AdapterRequest.from_json(raw)
    except (TypeError, ValueError) as exc:
        writer.error(f"malformed adapter request: {exc}", kind="bad_request")
        return 2
    return run(request, writer)


def _probe(argv: list[str]) -> int:
    """Print the local installation report as JSON. Never starts a turn."""
    cli_path = "claude"
    if "--cli-path" in argv:
        index = argv.index("--cli-path")
        if index + 1 < len(argv):
            cli_path = argv[index + 1]
    json.dump(probe(cli_path), sys.stdout)
    sys.stdout.write("\n")
    sys.stdout.flush()
    return 0

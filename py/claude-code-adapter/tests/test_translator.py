"""Unit tests for the CLI -> Anthropic SSE translation."""

from __future__ import annotations

import io
import json

from avante_claude_code.protocol import SESSION_EVENT, AdapterRequest, SSEWriter
from avante_claude_code.cli import build_args, build_stdin_messages
from avante_claude_code.translator import StreamTranslator


def drive(records: list[dict]) -> list[dict]:
    """Feed ``records`` through a translator and return the emitted events."""
    buffer = io.StringIO()
    translator = StreamTranslator(SSEWriter(buffer))
    for record in records:
        translator.handle(record)
    translator.finish()
    return [
        json.loads(line[len("data: ") :])
        for line in buffer.getvalue().splitlines()
        if line.startswith("data: ")
    ]


def stream(event: dict) -> dict:
    return {"type": "stream_event", "event": event}


def test_session_id_is_announced() -> None:
    events = drive([{"type": "system", "subtype": "init", "session_id": "sid-1"}])
    assert events[0] == {"type": SESSION_EVENT, "session_id": "sid-1"}


def test_text_turn_is_passed_through() -> None:
    events = drive(
        [
            stream({"type": "message_start", "message": {"role": "assistant", "content": []}}),
            stream({"type": "content_block_start", "index": 0, "content_block": {"type": "text", "text": ""}}),
            stream({"type": "content_block_delta", "index": 0, "delta": {"type": "text_delta", "text": "hi"}}),
            stream({"type": "content_block_stop", "index": 0}),
            {"type": "result", "is_error": False, "stop_reason": "end_turn", "usage": {"input_tokens": 3, "output_tokens": 4}},
        ]
    )
    types = [event["type"] for event in events]
    assert types == [
        "message_start",
        "content_block_start",
        "content_block_delta",
        "content_block_stop",
        "message_delta",
        "message_stop",
    ]
    assert events[-2]["delta"]["stop_reason"] == "end_turn"
    assert events[-2]["usage"]["output_tokens"] == 4


def test_several_assistant_messages_merge_into_one() -> None:
    """The CLI's internal tool loop must not leak extra message boundaries."""
    events = drive(
        [
            stream({"type": "message_start", "message": {"role": "assistant", "content": []}}),
            stream({"type": "content_block_start", "index": 0, "content_block": {"type": "text", "text": ""}}),
            stream({"type": "content_block_delta", "index": 0, "delta": {"type": "text_delta", "text": "a"}}),
            stream({"type": "content_block_stop", "index": 0}),
            stream({"type": "message_delta", "delta": {"stop_reason": "tool_use"}, "usage": {"output_tokens": 1}}),
            stream({"type": "message_stop"}),
            stream({"type": "message_start", "message": {"role": "assistant", "content": []}}),
            stream({"type": "content_block_start", "index": 0, "content_block": {"type": "text", "text": ""}}),
            stream({"type": "content_block_delta", "index": 0, "delta": {"type": "text_delta", "text": "b"}}),
            stream({"type": "content_block_stop", "index": 0}),
            {"type": "result", "is_error": False, "stop_reason": "end_turn", "usage": {"output_tokens": 2}},
        ]
    )
    assert [event["type"] for event in events].count("message_start") == 1
    assert [event["type"] for event in events].count("message_stop") == 1
    # The second message's block was renumbered so indices stay unique.
    starts = [event for event in events if event["type"] == "content_block_start"]
    assert [start["index"] for start in starts] == [0, 1]
    assert events[-2]["usage"]["output_tokens"] == 3


def test_cli_tool_calls_become_text_not_tool_use() -> None:
    """Claude Code runs its own tools, so Avante must never see a tool_use block."""
    events = drive(
        [
            stream({"type": "message_start", "message": {"role": "assistant", "content": []}}),
            stream(
                {
                    "type": "content_block_start",
                    "index": 0,
                    "content_block": {"type": "tool_use", "id": "t1", "name": "Read", "input": {}},
                }
            ),
            stream(
                {
                    "type": "content_block_delta",
                    "index": 0,
                    "delta": {"type": "input_json_delta", "partial_json": '{"file_path": "a.txt"}'},
                }
            ),
            stream({"type": "content_block_stop", "index": 0}),
            {
                "type": "user",
                "message": {"role": "user", "content": [{"type": "tool_result", "tool_use_id": "t1", "content": "ok"}]},
            },
            {"type": "result", "is_error": False, "stop_reason": "end_turn"},
        ]
    )
    assert all(event.get("content_block", {}).get("type") != "tool_use" for event in events)
    text = "".join(
        event["delta"].get("text", "") for event in events if event["type"] == "content_block_delta"
    )
    assert "Read(a.txt)" in text
    assert "⎿ ok" in text


def test_cli_error_becomes_an_error_event() -> None:
    events = drive([{"type": "result", "is_error": True, "subtype": "error_max_turns", "result": "too many turns"}])
    assert events[-1]["type"] == "error"
    assert events[-1]["error"]["message"] == "too many turns"


def test_args_disable_builtin_tools_with_an_empty_list() -> None:
    args = build_args(AdapterRequest(cli_path="claude", tools=[]))
    assert args[args.index("--tools") + 1] == ""
    assert "--include-partial-messages" in args


def test_resume_only_replays_the_trailing_user_turn() -> None:
    request = AdapterRequest(
        resume="sid",
        messages=[
            {"role": "user", "content": "first"},
            {"role": "assistant", "content": [{"type": "text", "text": "answered"}]},
            {"role": "user", "content": "second"},
        ],
    )
    (message,) = build_stdin_messages(request)
    assert message["message"]["content"][0]["text"] == "second"

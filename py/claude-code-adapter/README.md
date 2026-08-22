# avante-claude-code

The Python adapter that lets [avante.nvim](https://github.com/yetone/avante.nvim)
talk to the **native Claude Code CLI** instead of an HTTP LLM endpoint.

It is a plain stdin/stdout filter with **no third-party dependencies** — any
Python 3.9+ interpreter on `PATH` can run it.

```
                 JSON request                 stream-json
avante.nvim  ───────────────────▶  adapter  ◀────────────▶  claude --print
             ◀───────────────────           
                Anthropic SSE
```

## Protocol

**In** — one JSON object on stdin (see `avante_claude_code/protocol.py`,
`AdapterRequest`), then EOF. Notable fields:

| field | meaning |
| --- | --- |
| `messages` | Avante's conversation, in Anthropic content-block form |
| `system_prompt` / `append_system_prompt` | passed to `--system-prompt` / `--append-system-prompt` |
| `model`, `fallback_model`, `effort` | model selection |
| `cwd` | directory Claude Code runs in — its tools are scoped to this |
| `resume` | a previous Claude Code session id to continue |
| `permission_mode` | `acceptEdits`, `bypassPermissions`, `plan`, … |
| `tools`, `allowed_tools`, `disallowed_tools` | which built-in tools may run (`[]` disables all) |
| `plugin_dirs`, `plugin_urls` | Claude Code plugins loaded for this session only |
| `disable_slash_commands` | suppress the CLI's own slash commands |
| `cli_path`, `extra_args`, `env` | escape hatches for anything not modelled above |

**Out** — Anthropic Messages API server-sent events on stdout, exactly as
`https://api.anthropic.com/v1/messages` would emit them. That is the whole point
of the adapter: the Neovim side reuses a stock Anthropic stream parser.

Two extra event names are emitted outside the Anthropic set:

- `avante_session` — carries the Claude Code `session_id` so the next turn can
  `--resume` it instead of resending the transcript.
- `avante_capabilities` — what this session actually has: its slash commands,
  skills, agents, plugins, MCP servers, tools, model and auth source. Neovim
  caches this so it can offer the same commands the CLI would.
- `error` — an Anthropic-shaped error envelope for CLI failures.

## Why a translation layer is needed

Claude Code runs a *complete agentic loop* for a single user turn: it may emit
several assistant messages, each with its own `message_start`/`message_stop` and
an intermediate `stop_reason` of `tool_use`. Avante expects one streamed
assistant message. `translator.StreamTranslator` therefore merges them: one
`message_start`, content-block indices renumbered so they stay unique, usage
summed across every underlying request, and a single terminal
`message_delta`/`message_stop` synthesised from the CLI's final `result` record.

Claude Code's own `tool_use` blocks are **rewritten into text** rather than
forwarded. The CLI already executed those tools; handing them to Avante's tool
runner would run them a second time. They render in the sidebar as

```
⏺ Read(src/main.rs)
  ⎿ 1  fn main() {
```

## Running it

```sh
echo '{"model":"sonnet","messages":[{"role":"user","content":"hi"}]}' \
  | python3 -m avante_claude_code
```

## Probing

`--probe` answers a few questions about the local installation and exits. It
only calls CLI subcommands that resolve locally, so no turn is started and no
tokens are spent:

```sh
python3 -m avante_claude_code --probe [--cli-path /path/to/claude]
```

```json
{
  "cli_path": "claude",
  "version": { "ok": true, "value": "2.1.240 (Claude Code)" },
  "auth": { "ok": true, "value": { "loggedIn": true, "authMethod": "oauth_token" } },
  "plugins": { "ok": true, "value": [] }
}
```

This backs `:AvanteClaudeCodeStatus` and `:checkhealth avante`.

## Tests

```sh
uv run --with pytest python -m pytest tests -q
```

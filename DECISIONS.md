# Switching avante.nvim to the native Claude Code CLI

This document records the decisions taken while replacing avante.nvim's
multi-provider LLM layer with a single provider that drives the **native Claude
Code CLI** through a **Python adapter**.

It is a decision log, not a tutorial. User-facing setup lives in `README.md` and
`py/claude-code-adapter/README.md`.

---

## 1. What "the Claude Code CLI as a provider" means

**Decision.** `claude_code` is the only LLM provider. It shells out to the
`claude` binary in `--print --input-format stream-json --output-format
stream-json` mode and streams the result back into the sidebar.

**Rejected: the ACP route.** avante already ships an Agent Client Protocol
integration whose `claude-code` entry spawns `claude-agent-acp`, a third-party
npm shim around the CLI. That is not the *native* CLI, it adds a Node dependency
that has to be installed and kept in step with Claude Code, and it bypasses
avante's provider interface entirely. The ACP machinery is left in the tree but
`acp_providers` now defaults to `{}` — see §7.

**Rejected: the Anthropic HTTP API.** That is the old `claude` provider. It needs
an API key, it does not use the user's existing Claude Code subscription, and it
gives up everything the CLI brings for free: file tools, permission modes,
`CLAUDE.md` discovery, skills, MCP servers, session resumption.

---

## 2. Why a Python adapter and not raw Lua

**Decision.** A standalone Python process sits between Neovim and the CLI:
`py/claude-code-adapter`.

The CLI's NDJSON stream is not a drop-in for what avante's stream parser expects
(§3), and the reshaping is stateful: buffering partial JSON, renumbering content
blocks, summing usage across requests. Doing that in Lua would mean writing it
inside `parse_response`, which is called once per line and has no natural place
to keep cross-line buffers beyond the `ctx` table.

Python also gets process supervision — process groups, a stderr tail, timeouts —
that is fiddly from Neovim.

**Constraint accepted: no third-party dependencies.** The adapter is stdlib-only
and runs on any Python ≥ 3.9. Requiring users to `uv sync` a virtualenv before
their editor works would be a bad trade. This is why the RAG service's
`pyproject.toml` (which pulls in llama-index and friends) was not reused.

---

## 3. Wire format: Anthropic SSE, not a bespoke protocol

**Decision.** The adapter emits **Anthropic Messages API server-sent events** on
stdout — byte-for-byte what `api.anthropic.com/v1/messages` would emit.

This fell out of a discovery: with `--include-partial-messages`, the CLI's
`{"type":"stream_event","event":{…}}` records wrap *verbatim* Anthropic SSE
events. Unwrapping them is nearly free, and it means the Lua provider's
`parse_response` is a plain Anthropic parser — the same shape avante already
knows, with thinking blocks, usage and stop reasons all working unchanged.

Two events fall outside the Anthropic set:

- `avante_session` — the Claude Code session id, so the next turn can `--resume`.
- `error` — an Anthropic-shaped error envelope for CLI failures.

### The merge problem

Claude Code runs a *complete agentic loop* per user turn. One turn can produce
several assistant messages, each with its own `message_start`/`message_stop` and
an intermediate `stop_reason: "tool_use"`. Avante expects one streamed message.

`translator.StreamTranslator` therefore emits one `message_start`, renumbers
content-block indices so they stay unique across the merged message, sums usage
across every underlying request, swallows the intermediate stop events, and
synthesises a single terminal `message_delta`/`message_stop` from the CLI's
final `result` record.

---

## 4. Tools: Claude Code keeps its own

**Decision.** Claude Code executes its own tools (Read, Edit, Write, Bash, Grep,
…). Avante's tool runner is **disabled** for this provider, and avante's tool
schemas are not sent.

This is the decision with the widest blast radius, so the reasoning matters.
Avante's tool loop is request-scoped: the model returns `stop_reason: tool_use`,
avante runs the tool, then issues a *new* request with the result appended. The
CLI does not work that way — it owns the loop and returns only when the whole
turn is done. Reconciling the two would mean either

1. exposing avante's tools to the CLI as an MCP server and holding the CLI
   process alive across avante requests, blocked on Neovim — essentially
   reimplementing ACP, or
2. disabling the CLI's tools and using it as a dumb completion endpoint — which
   throws away the reason to use Claude Code at all.

Neither is worth it. Claude Code's tools are better than avante's for the same
jobs, and they come with permission modes and `CLAUDE.md` discovery.

**Consequence.** The CLI's `tool_use` blocks must never reach avante's tool
runner, or every tool would run twice. The translator rewrites them into text:

```
⏺ Read(src/main.rs)
  ⎿ 1  fn main() {
```

**Consequence.** Claude Code edits files on disk directly, so avante's diff-review
flow does not sit in front of those edits. `permission_mode` (default
`acceptEdits`) is the control users have. This is the same bargain the ACP
integration already made.

---

## 5. Transport: a subprocess fork in `llm.lua`

**Decision.** `M.curl` gained a fork on `provider.transport == "subprocess"`,
mirroring the existing `Config.acp_providers` fork in `M._stream`. The provider
implements `parse_subprocess_args` instead of `parse_curl_args`.

avante's transport was curl-only (`plenary.curl`, `llm.lua`). The two escape
hatches — `rawArgs` (extra curl argv) and `parse_stream_data` (custom chunk
framing) — cannot make curl spawn a local process. Abusing `file://` URLs or a
local proxy was considered and rejected as a hack that would break cancellation
and error reporting.

The fork is deliberately narrow: it spawns the process, feeds stdout lines into
the *same* `parse_stream_data` → `parse_response` pipeline curl uses, and wires
the same cancellation autocmd. Everything downstream — the agent loop, history,
sidebar rendering, token accounting — is untouched.

---

## 6. Session continuity

**Decision.** The provider remembers the Claude Code session id per conversation
and passes `resume` on later turns, sending only the new user content.

Without this, every turn would replay the entire transcript into a fresh CLI
session, losing prompt caching and making the CLI re-read files it already read.
The session id arrives on the `avante_session` event; conversations are keyed by
a hash of their first user message, which is stable for the life of a chat.

When there is no session to resume, prior assistant turns are folded into the
prompt as `<previous_assistant_response>` blocks so a cold start still has the
full history.

---

## 7. Scope of the removal

**Removed.** `azure`, `bedrock` (and `providers/bedrock/`), `claude`, `cohere`,
`copilot`, `gemini`, `ollama`, `openai`, `vertex`, `vertex_claude`,
`watsonx_code_assistant`, and every config-only alias of those
(`claude-haiku`, `claude-opus`, `openai-gpt-4o-mini`, `aihubmix`,
`aihubmix-claude`, `morph`, `moonshot`, `xai`, `glm`, `qwen`, `mistral`).

**Kept: the RAG service.** `py/rag-service` has its own provider namespace
(`openai`, `ollama`, `dashscope`, `openrouter`) for embeddings and retrieval. It
shares no code with `lua/avante/providers/` and is an opt-in Docker service.
Removing it would be an unrelated decision.

**Kept but emptied: ACP.** `Config.acp_providers` now defaults to `{}`. The ACP
implementation stays in the tree. `Config.acp_providers` is dereferenced
unconditionally from about fifteen call sites across `llm.lua`, `sidebar.lua`,
`providers/init.lua`, `slashcommands.lua` and others; ripping those out is a
large, risky, orthogonal change. An empty table means no ACP agent is offered by
default while users who want one can still configure it.

**Kept: Fast Apply, defanged.** `llm_tools/edit_file.lua` looked up
`Providers["morph"]`, which *raises* rather than returning nil for an unknown
provider — so deleting `morph` would have broken the guard that was meant to
catch exactly that. The lookup is now `pcall`-wrapped and Fast Apply reports
itself unavailable instead of erroring.

---

## 8. Native commands, plugins and auth

Using the real CLI means its own extension surface comes along, and leaving it
inaccessible would waste the main advantage of this design.

### Slash commands

Claude Code resolves `/compact`, `/context`, skills and plugin commands itself,
and a message beginning with `/` sent over stream-json is handled natively — no
special casing needed on our side. So the provider contributes them to Avante's
slash-command list **without a callback**: Avante offers the name, then passes
the text through untouched.

Avante's own commands win a name clash. `/compact` exists on both sides, and
Avante's acts on the Avante-side conversation, which is what a user typing it in
the sidebar means.

Discovery is the awkward part: the CLI only announces its commands in the `init`
record of a turn, and a turn costs tokens. Feeding it empty stdin exits before
`init` is emitted, so there is no free probe. The provider therefore harvests
the announcement from **every** turn and caches it to
`stdpath("cache")/avante/claude_code_capabilities.json`, reloading it at
startup. Commands are available immediately in every session after the first
message ever sent.

`Utils.get_commands` gained a generic third source rather than a Claude Code
special case: any provider exposing `list_slash_commands` contributes.

The capability table is mutated in place, never rebound. `Providers.__index`
builds the provider table with `vim.tbl_deep_extend`, which shares references
for tables present in only one source — so rebinding the field would silently
strand that copy on the original empty table.

### Plugins

`plugin_dirs` and `plugin_urls` map to `--plugin-dir` / `--plugin-url`, which
are per-session: they layer on top of whatever `claude plugin install` has
already set up globally. Installed plugins are reported by
`:AvanteClaudeCodeStatus` rather than managed from Neovim — `claude plugin` is a
complete CLI already, and wrapping it would only add a second thing to keep in
sync.

### Auth

There is no API key, so avante's key-prompt path is inert and health checks had
nothing to verify. `claude auth status --json` answers locally and cheaply, and
`claude plugin list --json` and `claude --version` do too. The adapter exposes
all three behind a `--probe` flag that starts no turn and spends no tokens; it
backs `:AvanteClaudeCodeStatus` and the `:checkhealth` entry.

`:AvanteClaudeCodeAuth` runs `claude auth login` in a terminal split rather than
a job, because the sign-in flow is interactive and needs a real TTY.

## 9. Smaller calls

- **`tokenizer_id` stays `"gpt-4o"`.** It selects tiktoken in
  `crates/avante-tokenizers`; anything else triggers a HuggingFace Hub download
  at startup. Token counts are approximate either way — the CLI reports real
  usage on `message_delta`.
- **No API key.** `api_key_name = ""`, so avante never prompts for one. The CLI
  owns authentication (`claude auth`). Health checks verify the binary and a
  Python interpreter instead.
- **`copilot`-specific branches** in `llm_tools/bash.lua` and
  `llm_tools/dispatch_agent.lua` were removed rather than left permanently false.
- **`dual_boost`** now names `claude_code` for both providers.
- **Provider-specific curl branches** for watsonx (multipart) and openrouter
  (HTML error detection) were removed with their providers.

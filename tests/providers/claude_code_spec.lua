local Config = require("avante.config")
local ClaudeCode = require("avante.providers.claude_code")

describe("claude_code provider", function()
  --- An executable path for `cli_path`, so the provider believes the CLI is
  --- installed without the test depending on a real Claude Code install.
  local function stub_cli_path()
    local resolved = vim.fn.exepath("sh")
    if resolved == "" then resolved = vim.v.progpath end
    return resolved
  end

  --- Build the provider the way `avante.providers` does: the module's functions
  --- with the resolved provider config layered on top.
  ---@param overrides table | nil
  local function make_provider(overrides)
    local conf = vim.tbl_deep_extend("force", vim.deepcopy(Config._defaults.providers.claude_code), {
      cli_path = stub_cli_path(),
      python_path = "/usr/bin/python3",
      cwd = "/tmp/avante-claude-code-spec",
    }, overrides or {})
    return setmetatable(conf, { __index = ClaudeCode })
  end

  --- Collect everything `parse_response` hands back to the caller.
  local function make_handlers()
    local recorded = { chunks = {}, messages = {}, stops = {} }
    local opts = {
      on_chunk = function(chunk) table.insert(recorded.chunks, chunk) end,
      on_messages_add = function(messages)
        for _, message in ipairs(messages) do
          table.insert(recorded.messages, message)
        end
      end,
      on_stop = function(stop_opts) table.insert(recorded.stops, stop_opts) end,
    }
    return recorded, opts
  end

  local function sse(payload) return vim.json.encode(payload) end

  before_each(function() ClaudeCode._sessions = {} end)

  after_each(function() ClaudeCode._sessions = {} end)

  describe("session_key", function()
    it("hashes the first user message", function()
      local key = ClaudeCode.session_key({ { role = "user", content = "refactor the parser" } })

      assert.is_string(key)
      assert.are.same(ClaudeCode.session_key({ { role = "user", content = "refactor the parser" } }), key)
    end)

    it("stays stable as the conversation grows", function()
      local first_turn = {
        { role = "user", content = "refactor the parser" },
      }
      local later_turn = {
        { role = "user", content = "refactor the parser" },
        { role = "assistant", content = "done" },
        { role = "user", content = "now add tests" },
      }

      assert.are.same(ClaudeCode.session_key(first_turn), ClaudeCode.session_key(later_turn))
    end)

    it("differs for a different first user message", function()
      local a = ClaudeCode.session_key({ { role = "user", content = "refactor the parser" } })
      local b = ClaudeCode.session_key({ { role = "user", content = "refactor the lexer" } })

      assert.is_string(a)
      assert.is_string(b)
      assert.are_not.same(a, b)
    end)

    it("reads through content-item arrays", function()
      local key = ClaudeCode.session_key({
        { role = "user", content = { { type = "text", text = "refactor the parser" } } },
      })

      assert.are.same(ClaudeCode.session_key({ { role = "user", content = "refactor the parser" } }), key)
    end)

    it("returns nil when there is no usable user text", function()
      assert.is_nil(ClaudeCode.session_key({}))
      assert.is_nil(ClaudeCode.session_key({ { role = "assistant", content = "hello" } }))
      assert.is_nil(ClaudeCode.session_key({ { role = "user", content = "" } }))
      assert.is_nil(ClaudeCode.session_key({ { role = "user", content = {} } }))
    end)
  end)

  describe("parse_messages", function()
    it("keeps string content and maps roles", function()
      local messages = ClaudeCode:parse_messages({
        messages = {
          { role = "user", content = "hello" },
          { role = "assistant", content = "hi" },
        },
      })

      assert.are.same({
        { role = "user", content = "hello" },
        { role = "assistant", content = "hi" },
      }, messages)
    end)

    it("passes through roles the role_map does not cover", function()
      local messages = ClaudeCode:parse_messages({
        messages = { { role = "system", content = "be brief" } },
      })

      assert.are.same({ { role = "system", content = "be brief" } }, messages)
    end)

    it("flattens content-item arrays", function()
      local messages = ClaudeCode:parse_messages({
        messages = {
          {
            role = "assistant",
            content = {
              { type = "text", text = "first" },
              { type = "thinking", thinking = "pondering" },
              { type = "tool_result", content = "tool said so" },
            },
          },
        },
      })

      assert.are.same(1, #messages)
      assert.are.same("first\npondering\ntool said so", messages[1].content)
    end)

    it("inspects structured tool_result content", function()
      local messages = ClaudeCode:parse_messages({
        messages = {
          {
            role = "user",
            content = { { type = "tool_result", content = { { type = "text", text = "nested-result" } } } },
          },
        },
      })

      assert.are.same(1, #messages)
      assert.is_truthy(messages[1].content:find("nested-result", 1, true))
    end)

    it("drops messages that flatten to nothing", function()
      local messages = ClaudeCode:parse_messages({
        messages = {
          { role = "user", content = "keep me" },
          { role = "assistant", content = "" },
          { role = "assistant", content = {} },
          { role = "user", content = { { type = "image", source = {} } } },
        },
      })

      assert.are.same({ { role = "user", content = "keep me" } }, messages)
    end)

    it("appends image paths to the last message", function()
      local messages = ClaudeCode:parse_messages({
        messages = {
          { role = "user", content = "look at these" },
          { role = "assistant", content = "sure" },
        },
        image_paths = { "/tmp/a.png", "/tmp/b.png" },
      })

      assert.are.same(2, #messages)
      assert.are.same("look at these", messages[1].content)
      assert.are.same("sure\n\nAttached images:\n- /tmp/a.png\n- /tmp/b.png", messages[2].content)
    end)

    it("ignores image paths when every message was dropped", function()
      local messages = ClaudeCode:parse_messages({
        messages = { { role = "user", content = "" } },
        image_paths = { "/tmp/a.png" },
      })

      assert.are.same({}, messages)
    end)
  end)

  describe("parse_subprocess_args", function()
    it("runs the adapter package with a python interpreter", function()
      local provider = make_provider()

      local spec = provider:parse_subprocess_args({
        system_prompt = "you are avante",
        messages = { { role = "user", content = "hello there" } },
      })

      assert.is_not_nil(spec)
      assert.are.same("/usr/bin/python3", spec.cmd)
      assert.is_truthy(spec.cmd:find("python", 1, true))
      assert.are.same({ "-m", "avante_claude_code" }, spec.args)
      assert.is_truthy(spec.cwd:find("py/claude%-code%-adapter$"))
      assert.are.same(spec.cwd, spec.env.PYTHONPATH)
    end)

    it("encodes the provider config into the adapter request", function()
      local provider = make_provider({
        model = "opus",
        permission_mode = "plan",
        allowed_tools = { "Read", "Grep" },
        add_dirs = { "/tmp/extra" },
        emit_tool_activity = false,
        timeout = 45,
      })

      local spec = provider:parse_subprocess_args({
        system_prompt = "you are avante",
        messages = {
          { role = "user", content = "hello there" },
          { role = "assistant", content = "hi" },
        },
      })

      local request = vim.json.decode(assert(spec).stdin)

      assert.are.same("opus", request.model)
      assert.are.same("you are avante", request.system_prompt)
      assert.are.same("/tmp/avante-claude-code-spec", request.cwd)
      assert.are.same("plan", request.permission_mode)
      assert.are.same({ "Read", "Grep" }, request.allowed_tools)
      assert.are.same({ "/tmp/extra" }, request.add_dirs)
      assert.is_false(request.emit_tool_activity)
      assert.are.same(45, request.timeout)
      assert.are.same(stub_cli_path(), request.cli_path)
      assert.are.same({
        { role = "user", content = "hello there" },
        { role = "assistant", content = "hi" },
      }, request.messages)
      -- `disable_tools` is Avante-side only; the adapter never sees it.
      assert.is_nil(request.disable_tools)
    end)

    it("seeds the turn context with the session key", function()
      local provider = make_provider()
      local messages = { { role = "user", content = "hello there" } }

      local spec = provider:parse_subprocess_args({ system_prompt = "sys", messages = messages })

      assert.are.same(ClaudeCode.session_key(messages), assert(spec).ctx.session_key)
    end)

    it("merges extra_request_body over the request", function()
      local provider = make_provider({
        effort = "low",
        extra_request_body = { effort = "high", custom_flag = true },
      })

      local spec = provider:parse_subprocess_args({
        system_prompt = "sys",
        messages = { { role = "user", content = "hello there" } },
      })

      local request = vim.json.decode(assert(spec).stdin)

      assert.are.same("high", request.effort)
      assert.is_true(request.custom_flag)
      -- extra_request_body is unpacked, never forwarded as a nested key.
      assert.is_nil(request.extra_request_body)
    end)

    it("returns nil when the CLI cannot be found", function()
      local provider = make_provider({ cli_path = "/definitely/not/here/claude" })

      local spec = provider:parse_subprocess_args({
        system_prompt = "sys",
        messages = { { role = "user", content = "hello there" } },
      })

      assert.is_nil(spec)
    end)
  end)

  describe("parse_response", function()
    it("streams a text block through to completion", function()
      local recorded, opts = make_handlers()
      local ctx = { turn_id = "turn-1" }

      ClaudeCode:parse_response(
        ctx,
        sse({ type = "message_start", message = { usage = { input_tokens = 11, output_tokens = 0 } } }),
        "message_start",
        opts
      )
      ClaudeCode:parse_response(
        ctx,
        sse({ type = "content_block_start", index = 0, content_block = { type = "text", text = "" } }),
        "content_block_start",
        opts
      )
      ClaudeCode:parse_response(
        ctx,
        sse({ type = "content_block_delta", index = 0, delta = { type = "text_delta", text = "Hello" } }),
        "content_block_delta",
        opts
      )
      ClaudeCode:parse_response(
        ctx,
        sse({ type = "content_block_delta", index = 0, delta = { type = "text_delta", text = " world" } }),
        "content_block_delta",
        opts
      )
      ClaudeCode:parse_response(ctx, sse({ type = "content_block_stop", index = 0 }), "content_block_stop", opts)
      ClaudeCode:parse_response(
        ctx,
        sse({
          type = "message_delta",
          delta = { stop_reason = "end_turn" },
          usage = { input_tokens = 11, output_tokens = 7 },
        }),
        "message_delta",
        opts
      )

      assert.are.same("Hello world", table.concat(recorded.chunks))
      assert.are.same(1, #recorded.stops)
      assert.are.same("complete", recorded.stops[1].reason)
      assert.are.same({ prompt_tokens = 11, completion_tokens = 7 }, recorded.stops[1].usage)

      local last_message = recorded.messages[#recorded.messages]
      assert.are.same("assistant", last_message.message.role)
      assert.are.same("Hello world", last_message.message.content)
      assert.are.same("generated", last_message.state)
      assert.are.same("turn-1", last_message.turn_id)
    end)

    it("counts cache tokens as prompt tokens", function()
      local recorded, opts = make_handlers()
      local ctx = {}

      ClaudeCode:parse_response(
        ctx,
        sse({
          type = "message_start",
          message = {
            usage = { input_tokens = 3, cache_creation_input_tokens = 5, cache_read_input_tokens = 2 },
          },
        }),
        "message_start",
        opts
      )
      ClaudeCode:parse_response(ctx, sse({ type = "message_delta", delta = {} }), "message_delta", opts)

      assert.are.same({ prompt_tokens = 10, completion_tokens = 0 }, recorded.stops[1].usage)
    end)

    it("reports a truncated turn as max_tokens", function()
      local recorded, opts = make_handlers()

      ClaudeCode:parse_response(
        {},
        sse({ type = "message_delta", delta = { stop_reason = "max_tokens" } }),
        "message_delta",
        opts
      )

      assert.are.same(1, #recorded.stops)
      assert.are.same("max_tokens", recorded.stops[1].reason)
    end)

    it("reports an error event, inferring the event state from the payload", function()
      local recorded, opts = make_handlers()

      ClaudeCode:parse_response({}, '{"type":"error","error":{"type":"api_error","message":"boom"}}', nil, opts)

      assert.are.same(1, #recorded.stops)
      assert.are.same("error", recorded.stops[1].reason)
      assert.are.same({ type = "api_error", message = "boom" }, recorded.stops[1].error)
    end)

    it("wraps a thinking block in think tags", function()
      local recorded, opts = make_handlers()
      local ctx = {}

      ClaudeCode:parse_response(
        ctx,
        sse({ type = "content_block_start", index = 0, content_block = { type = "thinking", thinking = "" } }),
        "content_block_start",
        opts
      )
      ClaudeCode:parse_response(
        ctx,
        sse({ type = "content_block_delta", index = 0, delta = { type = "thinking_delta", thinking = "hmm" } }),
        "content_block_delta",
        opts
      )
      ClaudeCode:parse_response(ctx, sse({ type = "content_block_stop", index = 0 }), "content_block_stop", opts)

      assert.are.same("<think>\nhmm\n</think>\n\n", table.concat(recorded.chunks))
    end)

    it("ignores payloads that are not valid json", function()
      local recorded, opts = make_handlers()

      ClaudeCode:parse_response({}, "not json at all", "message_delta", opts)

      assert.are.same(0, #recorded.stops)
    end)
  end)

  describe("session resumption", function()
    it("records the session id and resumes the next turn", function()
      local provider = make_provider()
      local messages = { { role = "user", content = "hello there" } }
      local session_key = assert(ClaudeCode.session_key(messages))

      local first = provider:parse_subprocess_args({ system_prompt = "sys", messages = messages })
      assert.is_nil(vim.json.decode(assert(first).stdin).resume)

      local _, opts = make_handlers()
      ClaudeCode:parse_response(
        { session_key = session_key },
        sse({ type = "avante_session", session_id = "sess-42" }),
        "avante_session",
        opts
      )

      assert.are.same("sess-42", ClaudeCode._sessions[session_key])

      local second = provider:parse_subprocess_args({
        system_prompt = "sys",
        messages = {
          { role = "user", content = "hello there" },
          { role = "assistant", content = "hi" },
          { role = "user", content = "and now the tests" },
        },
      })

      assert.are.same("sess-42", vim.json.decode(assert(second).stdin).resume)
    end)

    it("does not resume a different conversation", function()
      local provider = make_provider()

      local _, opts = make_handlers()
      ClaudeCode:parse_response(
        { session_key = assert(ClaudeCode.session_key({ { role = "user", content = "hello there" } })) },
        sse({ type = "avante_session", session_id = "sess-42" }),
        "avante_session",
        opts
      )

      local spec = provider:parse_subprocess_args({
        system_prompt = "sys",
        messages = { { role = "user", content = "a brand new question" } },
      })

      assert.is_nil(vim.json.decode(assert(spec).stdin).resume)
    end)

    it("never resumes when stateful is off", function()
      local provider = make_provider({ stateful = false })
      local messages = { { role = "user", content = "hello there" } }

      local _, opts = make_handlers()
      ClaudeCode:parse_response(
        { session_key = assert(ClaudeCode.session_key(messages)) },
        sse({ type = "avante_session", session_id = "sess-42" }),
        "avante_session",
        opts
      )

      local spec = provider:parse_subprocess_args({ system_prompt = "sys", messages = messages })

      assert.is_nil(vim.json.decode(assert(spec).stdin).resume)
    end)
  end)
end)

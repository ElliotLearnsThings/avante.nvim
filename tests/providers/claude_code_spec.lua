local Config = require("avante.config")
local Utils = require("avante.utils")
local ClaudeCode = require("avante.providers.claude_code")
--- The same `avante.providers` instance the provider module itself captured.
local Providers = require("avante.providers")

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

  --- The `avante_capabilities` event the adapter emits at the start of a turn,
  --- built from the CLI's `init` record. Overrides replace whole keys.
  ---@param overrides table | nil
  local function capabilities_event(overrides)
    local payload = {
      type = "avante_capabilities",
      slash_commands = { "review", "cost", "pr-comments" },
      skills = { "pdf", "xlsx" },
      plugins = { "acme-tools" },
      mcp_servers = { "github" },
      tools = { "Read", "Edit" },
      model = "claude-sonnet-4-5",
      apiKeySource = "none",
      claude_code_version = "2.1.0",
    }
    for key, value in pairs(overrides or {}) do
      payload[key] = value
    end
    return payload
  end

  --- Drive one capabilities event through `parse_response`, as the stream does.
  ---@param payload table
  local function emit_capabilities(payload)
    local recorded, opts = make_handlers()
    ClaudeCode:parse_response({}, sse(payload), "avante_capabilities", opts)
    return recorded
  end

  --- Empty `M._capabilities` without rebinding it: the table is shared, and
  --- these tests are precisely about that sharing.
  local function reset_capabilities()
    for key in pairs(ClaudeCode._capabilities) do
      ClaudeCode._capabilities[key] = nil
    end
  end

  --- A throwaway `stdpath("cache")`, so nothing here reads or clobbers the
  --- developer's real capability cache.
  local cache_root
  local real_stdpath

  local function cache_file() return vim.fs.joinpath(cache_root, "avante", "claude_code_capabilities.json") end

  --- Load a fresh `avante.config` and `avante.providers`, so a test can pick the
  --- active provider without leaking that choice into the rest of the suite.
  ---@param opts table
  ---@return table config
  local function setup_config(opts)
    package.loaded["avante.config"] = nil
    package.loaded["avante.providers"] = nil
    local fresh = require("avante.config")
    fresh.get_last_used_model = function() end
    fresh.setup(opts)
    return fresh
  end

  local function forget_config()
    package.loaded["avante.config"] = nil
    package.loaded["avante.providers"] = nil
  end

  before_each(function()
    ClaudeCode._sessions = {}
    reset_capabilities()
    cache_root = vim.fn.tempname()
    vim.fn.mkdir(cache_root, "p")
    real_stdpath = vim.fn.stdpath
    vim.fn.stdpath = function(what)
      if what == "cache" then return cache_root end
      return real_stdpath(what)
    end
  end)

  after_each(function()
    vim.fn.stdpath = real_stdpath
    vim.fs.rm(cache_root, { recursive = true, force = true })
    ClaudeCode._sessions = {}
    reset_capabilities()
  end)

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
        timeout = 45000,
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
      -- Avante configures the timeout in milliseconds; the adapter wants seconds.
      assert.are.same(45, request.timeout)
      assert.are.same(stub_cli_path(), request.cli_path)
      assert.are.same({
        { role = "user", content = "hello there" },
        { role = "assistant", content = "hi" },
      }, request.messages)
      -- `disable_tools` is Avante-side only; the adapter never sees it.
      assert.is_nil(request.disable_tools)
    end)

    it("forwards the plugin and slash-command config", function()
      local provider = make_provider({
        plugin_dirs = { "/tmp/avante-plugins/acme" },
        plugin_urls = { "https://example.invalid/acme-plugin.git" },
        disable_slash_commands = true,
      })

      local spec = provider:parse_subprocess_args({
        system_prompt = "sys",
        messages = { { role = "user", content = "hello there" } },
      })

      local request = vim.json.decode(assert(spec).stdin)

      assert.are.same({ "/tmp/avante-plugins/acme" }, request.plugin_dirs)
      assert.are.same({ "https://example.invalid/acme-plugin.git" }, request.plugin_urls)
      assert.is_true(request.disable_slash_commands)
    end)

    it("defaults the plugin and slash-command config when it is unset", function()
      local provider = make_provider()
      -- The adapter always receives these keys, whether or not they are configured.
      provider.plugin_dirs = nil
      provider.plugin_urls = nil
      provider.disable_slash_commands = nil

      local spec = provider:parse_subprocess_args({
        system_prompt = "sys",
        messages = { { role = "user", content = "hello there" } },
      })

      local request = vim.json.decode(assert(spec).stdin)

      assert.are.same({}, request.plugin_dirs)
      assert.are.same({}, request.plugin_urls)
      assert.is_false(request.disable_slash_commands)
    end)

    it("keeps the defaults from the provider config", function()
      local provider = make_provider()

      local spec = provider:parse_subprocess_args({
        system_prompt = "sys",
        messages = { { role = "user", content = "hello there" } },
      })

      local request = vim.json.decode(assert(spec).stdin)

      assert.are.same({}, request.plugin_dirs)
      assert.are.same({}, request.plugin_urls)
      assert.is_false(request.disable_slash_commands)
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

  describe("capabilities", function()
    it("stores what the capabilities event announced", function()
      local recorded = emit_capabilities(capabilities_event())

      assert.are.same({ "review", "cost", "pr-comments" }, ClaudeCode._capabilities.slash_commands)
      assert.are.same({ "pdf", "xlsx" }, ClaudeCode._capabilities.skills)
      assert.are.same({ "acme-tools" }, ClaudeCode._capabilities.plugins)
      assert.are.same({ "github" }, ClaudeCode._capabilities.mcp_servers)
      assert.are.same("claude-sonnet-4-5", ClaudeCode._capabilities.model)
      assert.are.same("none", ClaudeCode._capabilities.apiKeySource)
      -- Capabilities are metadata: nothing reaches the sidebar.
      assert.are.same(0, #recorded.chunks)
      assert.are.same(0, #recorded.messages)
      assert.are.same(0, #recorded.stops)
    end)

    it("strips the event's own type key", function()
      emit_capabilities(capabilities_event())

      assert.is_nil(ClaudeCode._capabilities.type)
    end)

    it("infers the event state from the payload", function()
      local _, opts = make_handlers()

      ClaudeCode:parse_response({}, sse(capabilities_event()), nil, opts)

      assert.are.same({ "review", "cost", "pr-comments" }, ClaudeCode._capabilities.slash_commands)
    end)

    it("updates the capabilities table in place", function()
      -- The provider table `Providers.__index` builds shares this very table.
      -- Rebinding the field instead of refilling it would leave the shared copy
      -- permanently empty, and no native command would ever be offered.
      local shared = ClaudeCode._capabilities
      local provider = Utils.deep_extend_with_metatable("force", ClaudeCode, { model = "sonnet" })
      assert.is_true(rawequal(shared, provider._capabilities))

      emit_capabilities(capabilities_event({ slash_commands = { "review" } }))

      assert.is_true(rawequal(shared, ClaudeCode._capabilities))
      assert.are.same({ "review" }, shared.slash_commands)
      assert.is_true(rawequal(shared, provider._capabilities))
      assert.are.same({ "review" }, provider._capabilities.slash_commands)
    end)

    it("drops keys the newest capabilities event does not carry", function()
      emit_capabilities(capabilities_event())
      local shared = ClaudeCode._capabilities

      emit_capabilities({ type = "avante_capabilities", slash_commands = { "cost" } })

      assert.is_true(rawequal(shared, ClaudeCode._capabilities))
      assert.are.same({ "cost" }, shared.slash_commands)
      assert.is_nil(shared.skills)
      assert.is_nil(shared.plugins)
      assert.is_nil(shared.model)
    end)
  end)

  describe("list_slash_commands", function()
    it("offers every native command for the CLI to resolve", function()
      emit_capabilities(capabilities_event({ slash_commands = { "review", "cost" } }))

      local commands = ClaudeCode.list_slash_commands()

      assert.are.same(2, #commands)
      assert.are.same("review", commands[1].name)
      assert.are.same("Claude Code: /review", commands[1].description)
      assert.are.same("Native Claude Code command, resolved by the CLI", commands[1].details)
      assert.are.same("cost", commands[2].name)
      assert.are.same("Claude Code: /cost", commands[2].description)
    end)

    it("gives them no callback, so Avante passes the text through", function()
      emit_capabilities(capabilities_event())

      for _, command in ipairs(ClaudeCode.list_slash_commands()) do
        assert.is_nil(command.callback)
      end
    end)

    it("skips entries that are not usable names", function()
      emit_capabilities(capabilities_event({ slash_commands = { "review", "", 42, {}, "cost" } }))

      local names = vim.tbl_map(function(command) return command.name end, ClaudeCode.list_slash_commands())

      assert.are.same({ "review", "cost" }, names)
    end)

    it("returns an empty list when the CLI announced nothing", function()
      assert.are.same({}, ClaudeCode.list_slash_commands())

      emit_capabilities({ type = "avante_capabilities", slash_commands = {} })

      assert.are.same({}, ClaudeCode.list_slash_commands())
    end)
  end)

  describe("capability persistence", function()
    ---@param capabilities table
    local function write_cache(capabilities)
      vim.fn.mkdir(vim.fs.dirname(cache_file()), "p")
      vim.fn.writefile(vim.split(vim.json.encode(capabilities), "\n"), cache_file())
    end

    it("caches the capabilities it was told about", function()
      emit_capabilities(capabilities_event({ slash_commands = { "review" } }))

      assert.are.same(1, vim.fn.filereadable(cache_file()))

      local cached = vim.json.decode(table.concat(vim.fn.readfile(cache_file()), "\n"))
      assert.are.same({ "review" }, cached.slash_commands)
      assert.are.same("claude-sonnet-4-5", cached.model)
      assert.is_nil(cached.type)
    end)

    it("restores them, in place, on the next session", function()
      write_cache({ slash_commands = { "review", "cost" }, model = "opus" })
      local shared = ClaudeCode._capabilities

      ClaudeCode.load_capabilities()

      assert.is_true(rawequal(shared, ClaudeCode._capabilities))
      assert.are.same({ "review", "cost" }, ClaudeCode._capabilities.slash_commands)
      assert.are.same("opus", ClaudeCode._capabilities.model)
      assert.are.same(
        { "review", "cost" },
        vim.tbl_map(function(command) return command.name end, ClaudeCode.list_slash_commands())
      )
    end)

    it("survives a missing cache file", function()
      assert.are.same(0, vim.fn.filereadable(cache_file()))

      assert.has_no.errors(function() ClaudeCode.load_capabilities() end)

      assert.are.same({}, ClaudeCode.list_slash_commands())
    end)

    it("survives a corrupt cache file", function()
      vim.fn.mkdir(vim.fs.dirname(cache_file()), "p")
      vim.fn.writefile({ "{ this is not json" }, cache_file())

      assert.has_no.errors(function() ClaudeCode.load_capabilities() end)

      assert.are.same({}, ClaudeCode.list_slash_commands())
    end)

    it("keeps the capabilities it already has when the cache is unusable", function()
      emit_capabilities(capabilities_event({ slash_commands = { "review" } }))
      vim.fn.writefile({ "]not json[" }, cache_file())

      ClaudeCode.load_capabilities()

      assert.are.same({ "review" }, ClaudeCode._capabilities.slash_commands)
    end)

    it("ignores a cache file that does not hold a table", function()
      vim.fn.mkdir(vim.fs.dirname(cache_file()), "p")
      vim.fn.writefile({ '"just a string"' }, cache_file())

      assert.has_no.errors(function() ClaudeCode.load_capabilities() end)

      assert.are.same({}, ClaudeCode.list_slash_commands())
    end)
  end)

  describe("probe and auth", function()
    local real_get_config
    local real_system
    local real_cmd
    local spawned

    --- The provider config `probe` and `auth_login` read, without touching the
    --- global config: they go through `Providers.get_config`, not through `self`.
    ---@param overrides table | nil
    local function stub_provider_config(overrides)
      local conf = vim.tbl_extend("force", {
        cli_path = stub_cli_path(),
        python_path = "/usr/bin/python3",
      }, overrides or {})
      Providers.get_config = function() return conf end
    end

    --- Answer the adapter's probe without ever running it.
    ---@param result table
    local function stub_system(result)
      vim.system = function(cmd)
        table.insert(spawned, cmd)
        return { wait = function() return result end }
      end
    end

    ---@param report table
    local function stub_probe_report(report) stub_system({ code = 0, stdout = vim.json.encode(report), stderr = "" }) end

    before_each(function()
      spawned = {}
      real_get_config = Providers.get_config
      real_system = vim.system
      real_cmd = vim.cmd
      stub_provider_config()
    end)

    after_each(function()
      Providers.get_config = real_get_config
      vim.system = real_system
      vim.cmd = real_cmd
    end)

    it("asks the adapter for a probe, and decodes what it answers", function()
      stub_probe_report({ cli = { version = "2.1.0" }, auth = { ok = true, value = { loggedIn = true } } })

      local report, err = ClaudeCode.probe()

      assert.is_nil(err)
      assert.are.same("2.1.0", assert(report).cli.version)
      assert.are.same(1, #spawned)
      assert.are.same({ "-m", "avante_claude_code" }, { spawned[1][2], spawned[1][3] })
      assert.is_true(vim.tbl_contains(spawned[1], "--probe"))
      assert.is_true(vim.tbl_contains(spawned[1], stub_cli_path()))
    end)

    it("spawns nothing when the CLI is not installed", function()
      stub_provider_config({ cli_path = "/definitely/not/here/claude" })
      stub_system({ code = 0, stdout = "{}", stderr = "" })

      local report, err = ClaudeCode.probe()

      assert.is_nil(report)
      assert.are.same("Claude Code CLI not found", err)
      assert.are.same(0, #spawned)
    end)

    it("reports the adapter's stderr when the probe fails", function()
      stub_system({ code = 1, stdout = "", stderr = "  boom  \n" })

      local report, err = ClaudeCode.probe()

      assert.is_nil(report)
      assert.are.same("boom", err)
    end)

    it("reports output it cannot parse", function()
      stub_system({ code = 0, stdout = "not json at all", stderr = "" })

      local report, err = ClaudeCode.probe()

      assert.is_nil(report)
      assert.are.same("could not parse the probe output", err)
    end)

    it("describes how Claude Code is signed in", function()
      stub_probe_report({
        auth = { ok = true, value = { loggedIn = true, authMethod = "claude.ai", apiProvider = "anthropic" } },
      })

      local logged_in, detail = ClaudeCode.auth_status()

      assert.is_true(logged_in)
      assert.are.same("claude.ai (anthropic)", detail)
    end)

    it("reports a signed-out install", function()
      stub_probe_report({ auth = { ok = true, value = { loggedIn = false } } })

      local logged_in, detail = ClaudeCode.auth_status()

      assert.is_false(logged_in)
      assert.are.same("not signed in", detail)
    end)

    it("passes on an auth error from the CLI", function()
      stub_probe_report({ auth = { ok = false, error = "keychain locked" } })

      local logged_in, detail = ClaudeCode.auth_status()

      assert.is_false(logged_in)
      assert.are.same("keychain locked", detail)
    end)

    it("passes on a failed probe", function()
      stub_provider_config({ cli_path = "/definitely/not/here/claude" })

      local logged_in, detail = ClaudeCode.auth_status()

      assert.is_false(logged_in)
      assert.are.same("Claude Code CLI not found", detail)
    end)

    it("opens the CLI's own sign-in flow in a terminal", function()
      local commands = {}
      vim.cmd = function(command) table.insert(commands, command) end

      ClaudeCode.auth_login()

      assert.are.same("botright split", commands[1])
      assert.are.same("terminal " .. vim.fn.fnameescape(stub_cli_path()) .. " auth login", commands[2])
      assert.are.same("startinsert", commands[3])
    end)

    it("opens no terminal when the CLI is not installed", function()
      stub_provider_config({ cli_path = "/definitely/not/here/claude" })
      local commands = {}
      vim.cmd = function(command) table.insert(commands, command) end

      ClaudeCode.auth_login()

      assert.are.same({}, commands)
    end)
  end)

  describe("Utils.get_commands", function()
    local function builtin_names()
      return vim.tbl_map(
        function(command) return command.name end,
        require("avante.slashcommands").get_builtin_commands()
      )
    end

    local function command_names(commands)
      return vim.tbl_map(function(command) return command.name end, commands)
    end

    after_each(function() forget_config() end)

    it("appends the provider's commands after Avante's own", function()
      setup_config({})
      emit_capabilities(capabilities_event({ slash_commands = { "review", "cost" } }))

      local commands = Utils.get_commands()
      local names = command_names(commands)
      local builtins = builtin_names()

      -- Avante's builtins keep their order and their place at the front.
      for index, name in ipairs(builtins) do
        assert.are.same(name, names[index])
      end
      assert.are.same(#builtins + 2, #commands)
      assert.are.same({ "review", "cost" }, { names[#names - 1], names[#names] })
      -- The CLI resolves them, so Avante must pass the text through untouched.
      assert.is_nil(commands[#commands].callback)
      assert.are.same("Claude Code: /cost", commands[#commands].description)
    end)

    it("keeps Avante's builtin when a native command has the same name", function()
      setup_config({})
      emit_capabilities(capabilities_event({ slash_commands = { "clear", "review" } }))

      local commands = Utils.get_commands()
      local clear = vim.tbl_filter(function(command) return command.name == "clear" end, commands)

      assert.are.same(1, #clear)
      -- Avante's own acts on the Avante-side chat, so it wins the clash.
      assert.are.same("Clear chat history", clear[1].description)
      assert.is_function(clear[1].callback)
      assert.are.same(#builtin_names() + 1, #commands)
    end)

    it("lists only Avante's commands when the CLI announced none", function()
      setup_config({})

      assert.are.same({}, Utils.get_provider_slash_commands())
      assert.are.same(builtin_names(), command_names(Utils.get_commands()))
    end)

    it("offers nothing when the active provider has no native commands", function()
      setup_config({
        provider = "plain_http",
        providers = {
          plain_http = {
            api_key_name = "",
            model = "plain-model",
            parse_curl_args = function() end,
            setup = function() end,
          },
        },
      })
      emit_capabilities(capabilities_event({ slash_commands = { "review" } }))

      assert.are.same({}, Utils.get_provider_slash_commands())
      assert.are.same(builtin_names(), command_names(Utils.get_commands()))
    end)

    it("offers nothing when the provider cannot be resolved", function()
      local config = setup_config({})
      emit_capabilities(capabilities_event({ slash_commands = { "review" } }))
      config.provider = "no_such_provider"

      assert.are.same({}, Utils.get_provider_slash_commands())
      assert.are.same(builtin_names(), command_names(Utils.get_commands()))
    end)

    it("offers nothing when the active provider is an ACP one", function()
      local config = setup_config({})
      emit_capabilities(capabilities_event({ slash_commands = { "review" } }))
      config.acp_providers = { my_agent = { command = "my-agent", args = {} } }
      config.provider = "my_agent"

      assert.are.same({}, Utils.get_provider_slash_commands())
      assert.are.same(builtin_names(), command_names(Utils.get_commands()))
    end)
  end)

  describe("native slash commands", function()
    it("sends a known command unwrapped and without context ahead of it", function()
      -- Agentic mode wraps submissions in <task>, which buried the leading "/"
      -- and stopped Claude Code from ever resolving the command.
      ClaudeCode._capabilities.slash_commands = { "context", "compact" }
      local provider = make_provider()
      local spec = provider:parse_subprocess_args({
        system_prompt = "sys",
        messages = {
          { role = "user", content = "<context>some project context</context>" },
          { role = "user", content = "<task>/context</task>" },
        },
      })
      local request = vim.json.decode(spec.stdin)
      assert.are.same(1, #request.messages)
      assert.are.same("/context", request.messages[1].content)
    end)

    it("leaves an unknown command as an ordinary message", function()
      ClaudeCode._capabilities.slash_commands = { "context" }
      local provider = make_provider()
      local spec = provider:parse_subprocess_args({
        system_prompt = "sys",
        messages = {
          { role = "user", content = "<context>ctx</context>" },
          { role = "user", content = "<task>/notacommand please</task>" },
        },
      })
      local request = vim.json.decode(spec.stdin)
      assert.is_true(#request.messages > 1)
    end)

    it("leaves ordinary prose alone", function()
      ClaudeCode._capabilities.slash_commands = { "context" }
      local provider = make_provider()
      local spec = provider:parse_subprocess_args({
        system_prompt = "sys",
        messages = { { role = "user", content = "<task>what does 20/20 mean</task>" } },
      })
      local request = vim.json.decode(spec.stdin)
      assert.are.same("<task>what does 20/20 mean</task>", request.messages[1].content)
    end)
  end)
end)

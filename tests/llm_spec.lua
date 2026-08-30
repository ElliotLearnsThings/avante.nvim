local utils = require("avante.utils")

local llm = require("avante.llm")

describe("generate_prompts", function()
  local project_root = "/tmp/project_root"

  before_each(function()
    local mock_dir = vim.fs.joinpath("tests", project_root)
    vim.fn.mkdir(mock_dir, "p")

    local mock_file = vim.fs.joinpath("tests", project_root, "avante.md")
    local file = assert(io.open(mock_file, "w"))
    file:write("# Mock Instructions\nThis is a mock instruction file.")
    file:close()

    -- Mock the project root
    utils.root = {}
    utils.root.get = function() return mock_dir end

    -- Mock Config.providers
    local Config = require("avante.config")
    Config.instructions_file = "avante.md"
    Config.provider = "openai"
    Config.acp_providers = {}
    Config.providers = {
      openai = {
        endpoint = "https://api.mock.com/v1",
        model = "gpt-mock",
        timeout = 10000,
        context_window = 1000,
        extra_request_body = {
          temperature = 0.5,
          max_tokens = 1000,
        },
      },
    }
    -- Mock Config.history to prevent nil access error in Path.setup()
    Config.history = {
      max_tokens = 4096,
      carried_entry_count = nil,
      storage_path = "/tmp/test_avante_history",
      paste = {
        extension = "png",
        filename = "pasted-%Y-%m-%d-%H-%M-%S",
      },
    }

    -- Mock Config.behaviour
    Config.behaviour = {
      auto_focus_sidebar = true,
      auto_suggestions = false, -- Experimental stage
      auto_suggestions_respect_ignore = false,
      auto_set_highlight_group = true,
      auto_set_keymaps = true,
      auto_apply_diff_after_generation = false,
      jump_result_buffer_on_finish = false,
      support_paste_from_clipboard = false,
      minimize_diff = true,
      enable_token_counting = true,
      use_cwd_as_project_root = false,
      auto_focus_on_diff_view = false,
      auto_approve_tool_permissions = false, -- Default: show permission prompts for all tools
      auto_check_diagnostics = true,
      enable_fastapply = false,
    }

    -- Mock Config.rules to prevent nil access error in get_templates_dir()
    Config.rules = {
      project_dir = nil,
      global_dir = nil,
    }

    -- Mock P.available to always return true
    local Path = require("avante.path")
    ---@diagnostic disable-next-line: duplicate-set-field
    Path.available = function() return true end

    -- Mock the Prompt functions directly since _templates_lib is a local variable
    -- that we can't easily access from outside the module
    Path.prompts.initialize = function(_cache_directory, _project_directory)
      -- Mock initialization - no-op for tests
    end

    Path.prompts.render_file = function(_path, _opts)
      -- Mock render - return empty string for tests
      return ""
    end

    Path.prompts.render_mode = function(_mode, _opts)
      -- Mock render_mode - return empty string for tests
      return ""
    end

    Path.setup() -- Initialize necessary paths like cache_path
  end)

  after_each(function()
    -- Clean up created test files and directories
    local mock_dir = vim.fs.joinpath("tests", project_root)
    if vim.uv.fs_stat(mock_dir) then vim.fs.rm(mock_dir, { recursive = true }) end
  end)

  it("should include instruction file content when the file exists", function()
    local opts = {}
    llm.generate_prompts(opts)
    assert.are.same("\n# Mock Instructions\nThis is a mock instruction file.", opts.instructions)
  end)

  it("should not modify instructions if the file does not exist", function()
    local mock_file = vim.fs.joinpath("tests", project_root, "avante.md")
    if vim.uv.fs_stat(mock_file) then vim.fs.rm(mock_file) end

    local opts = {}
    llm.generate_prompts(opts)
    assert.are.same(opts.instructions, nil)
  end)

  it("should set tools to nil when no tools are provided", function()
    local opts = {}
    local result = llm.generate_prompts(opts)
    assert.are.same(result.tools, nil)
  end)

  it("should set tools to nil when empty tools array is provided", function()
    local opts = {
      tools = {},
    }
    local result = llm.generate_prompts(opts)
    assert.are.same(result.tools, nil)
  end)

  it("should set tools to nil when empty prompt_opts.tools array is provided", function()
    local opts = {
      prompt_opts = {
        tools = {},
      },
    }
    local result = llm.generate_prompts(opts)
    assert.are.same(result.tools, nil)
  end)

  it("should include tools when non-empty tools are provided", function()
    local mock_tool = {
      name = "test_tool",
      description = "A test tool",
      func = function() end,
    }
    local opts = {
      tools = { mock_tool },
    }
    local result = llm.generate_prompts(opts)
    assert.are.same(#result.tools, 1)
    assert.are.same(result.tools[1].name, "test_tool")
  end)

  it("should not duplicate instruction file content when called multiple times with same opts", function()
    local opts = {}
    llm.generate_prompts(opts)
    local first_instructions = opts.instructions

    -- Call again with the same opts object
    llm.generate_prompts(opts)
    local second_instructions = opts.instructions

    -- Instructions should be the same, not duplicated
    assert.are.same(first_instructions, second_instructions)
    -- Verify that mock content is present (more flexible than hardcoded exact match)
    assert.truthy(string.find(opts.instructions, "Mock Instructions"))
  end)

  it("should not duplicate instructions in messages when called multiple times with same opts", function()
    local opts = {
      instructions = "Test instructions",
    }

    -- First call
    local result1 = llm.generate_prompts(opts)
    local instruction_message_count1 = 0
    for _, msg in ipairs(result1.messages) do
      if
        msg.role == "user"
        and type(msg.content) == "string"
        and string.find(msg.content, "Test instructions", 1, true)
      then
        instruction_message_count1 = instruction_message_count1 + 1
      end
    end

    -- Second call with same opts
    local result2 = llm.generate_prompts(opts)
    local instruction_message_count2 = 0
    for _, msg in ipairs(result2.messages) do
      if
        msg.role == "user"
        and type(msg.content) == "string"
        and string.find(msg.content, "Test instructions", 1, true)
      then
        instruction_message_count2 = instruction_message_count2 + 1
      end
    end

    -- Should have instructions message only once in both calls
    assert.are.same(1, instruction_message_count1)
    assert.are.same(1, instruction_message_count2)
  end)
end)

describe("ACP prompt parts", function()
  local ACPClient = require("avante.libs.acp_client")
  local stub = require("luassert.stub")
  local Config = require("avante.config")
  local tmp_dir = vim.fs.joinpath("tests", "/tmp/acp_prompt_parts")
  local setup_transport_stub
  local warn_stub
  local warnings

  ---@param caps table
  local function make_client(caps)
    local client = ACPClient:new({ transport_type = "stdio", handlers = {} })
    client.agent_capabilities = { loadSession = true, promptCapabilities = caps }
    client.prompt_capabilities = caps
    return client
  end

  local function write_file(name, content)
    local path = vim.fs.joinpath(tmp_dir, name)
    local file = assert(io.open(path, "wb"))
    file:write(content)
    file:close()
    return vim.fn.fnamemodify(path, ":p")
  end

  before_each(function()
    vim.fn.mkdir(tmp_dir, "p")
    setup_transport_stub = stub(ACPClient, "_setup_transport")
    warnings = {}
    warn_stub = stub(utils, "warn")
    warn_stub.invokes(function(msg) table.insert(warnings, msg) end)
    Config.provider = "claude-code"
    llm._acp_image_unsupported_warned = {}
  end)

  after_each(function()
    setup_transport_stub:revert()
    warn_stub:revert()
    vim.fn.delete(tmp_dir, "rf")
  end)

  describe("extract_image_paths_from_text", function()
    it("extracts image: lines produced by the paste template", function()
      local text = "look at this\nimage: /tmp/a.png\nand this\nimage: /tmp/b.jpg\n"
      assert.same({ "/tmp/a.png", "/tmp/b.jpg" }, llm.extract_image_paths_from_text(text))
    end)

    it("returns nothing when there is no image line", function()
      assert.same({}, llm.extract_image_paths_from_text("just text"))
    end)
  end)

  describe("build_acp_image_parts", function()
    it("emits base64 image parts when the agent supports images", function()
      local png = write_file("a.png", "\137PNG\r\n\26\n")
      local client = make_client({ image = true, embeddedContext = true })
      local opts = {
        history_messages = { { message = { role = "user", content = "describe\nimage: " .. png } } },
      }

      local parts = llm.build_acp_image_parts(opts, client)

      assert.equals(1, #parts)
      assert.equals("image", parts[1].type)
      assert.equals("image/png", parts[1].mimeType)
      assert.equals(vim.base64.encode("\137PNG\r\n\26\n"), parts[1].data)
      assert.equals("file://" .. png, parts[1].uri)
      assert.same({}, warnings)
    end)

    it("uses prompt_opts.image_paths and detects jpeg mime type", function()
      local jpg = write_file("b.jpg", "\255\216\255")
      local client = make_client({ image = true })
      local parts = llm.build_acp_image_parts({ prompt_opts = { image_paths = { jpg } } }, client)

      assert.equals(1, #parts)
      assert.equals("image/jpeg", parts[1].mimeType)
      assert.equals(vim.base64.encode("\255\216\255"), parts[1].data)
    end)

    it("only reads images from the latest user message", function()
      local png = write_file("c.png", "x")
      local client = make_client({ image = true })
      local opts = {
        history_messages = {
          { message = { role = "user", content = "image: /tmp/old.png" } },
          { message = { role = "assistant", content = "ok" } },
          { message = { role = "user", content = { { type = "text", text = "image: " .. png } } } },
        },
      }
      local parts = llm.build_acp_image_parts(opts, client)
      assert.equals(1, #parts)
      assert.equals("file://" .. png, parts[1].uri)
    end)

    it("falls back to resource_link and warns once when the agent lacks image support", function()
      local png = write_file("d.png", "x")
      local client = make_client({ embeddedContext = true })
      local opts = { prompt_opts = { image_paths = { png } } }

      local parts = llm.build_acp_image_parts(opts, client)
      llm.build_acp_image_parts(opts, client)

      assert.equals(1, #parts)
      assert.same(
        { type = "resource_link", uri = "file://" .. png, name = "d.png", mimeType = "image/png" },
        parts[1]
      )
      assert.equals(1, #warnings)
      assert.truthy(warnings[1]:find("does not advertise image support", 1, true))
    end)

    it("returns no parts when no images are attached", function()
      local client = make_client({ image = true })
      assert.same({}, llm.build_acp_image_parts({ history_messages = {} }, client))
    end)
  end)

  describe("build_acp_file_part", function()
    it("embeds file content as a text resource when embeddedContext is supported", function()
      local lua_file = write_file("mod.lua", "return 1\n")
      local client = make_client({ image = true, embeddedContext = true })

      local part = llm.build_acp_file_part(lua_file, client)

      assert.same({
        type = "resource",
        resource = { uri = "file://" .. lua_file, text = "return 1\n", mimeType = "text/x-lua" },
      }, part)
    end)

    it("uses resource_link when embeddedContext is not supported", function()
      local lua_file = write_file("mod.lua", "return 1\n")
      local client = make_client({ image = true })

      local part = llm.build_acp_file_part(lua_file, client)

      assert.same(
        { type = "resource_link", uri = "file://" .. lua_file, name = "mod.lua", mimeType = "text/x-lua" },
        part
      )
    end)

    it("uses resource_link for files above the embedded size limit", function()
      local big = write_file("big.txt", string.rep("a", llm.ACP_EMBEDDED_RESOURCE_MAX_BYTES + 1))
      local client = make_client({ embeddedContext = true })

      local part = llm.build_acp_file_part(big, client)

      assert.equals("resource_link", part.type)
      assert.equals("big.txt", part.name)
    end)
  end)

  describe("_continue_stream_acp", function()
    it("sends embedded files and images in the prompt request", function()
      local png = write_file("shot.png", "img")
      local lua_file = write_file("mod.lua", "return 1\n")
      local client = make_client({ image = true, embeddedContext = true })
      local sent_prompt
      client.transport = {
        send = function(_, data)
          local decoded = vim.json.decode(data)
          if decoded.method == "session/prompt" then sent_prompt = decoded.params.prompt end
        end,
        start = function() end,
        stop = function() end,
      }
      client.state = "ready"

      llm._continue_stream_acp({
        selected_filepaths = { lua_file },
        history_messages = { { message = { role = "user", content = "hi\nimage: " .. png } } },
        on_start = function() end,
        on_stop = function() end,
      }, client, "session-1")

      assert.is_not_nil(sent_prompt)
      local types = vim.tbl_map(function(p) return p.type end, sent_prompt)
      assert.same({ "resource", "text", "image" }, types)
      assert.equals("return 1\n", sent_prompt[1].resource.text)
      assert.equals(vim.base64.encode("img"), sent_prompt[3].data)
    end)
  end)
end)

describe("ACP stop reasons", function()
  it("treats end_turn and a missing stopReason as normal completion", function()
    local notice, reason = llm.describe_acp_stop_reason("end_turn")
    assert.is_nil(notice)
    assert.equals("complete", reason)
    notice, reason = llm.describe_acp_stop_reason(nil)
    assert.is_nil(notice)
    assert.equals("complete", reason)
  end)

  it("surfaces a distinct notice for abnormal stop reasons", function()
    local cases = {
      max_tokens = "max_tokens",
      max_turn_requests = "complete",
      refusal = "complete",
      cancelled = "cancelled",
    }
    for stop_reason, expected_reason in pairs(cases) do
      local notice, reason = llm.describe_acp_stop_reason(stop_reason)
      assert.is_string(notice, stop_reason)
      assert.truthy(notice:find(stop_reason, 1, true), stop_reason)
      assert.equals(expected_reason, reason, stop_reason)
    end
  end)

  it("still produces a notice for unknown stop reasons", function()
    local notice, reason = llm.describe_acp_stop_reason("something_new")
    assert.truthy(notice:find("something_new", 1, true))
    assert.equals("complete", reason)
  end)
end)

describe("ACP user_message_chunk", function()
  local History = require("avante.history")

  it("skips text already present in a user message", function()
    local messages = { History.Message:new("user", "hello world", { is_user_submission = true }) }
    assert.is_nil(llm._apply_user_message_chunk(messages, "hello"))
    assert.is_nil(llm._apply_user_message_chunk(messages, "hello world"))
  end)

  it("creates a new user message when there is no user message to extend", function()
    local messages = { History.Message:new("assistant", "hi") }
    local message = llm._apply_user_message_chunk(messages, "new text")
    assert.is_not_nil(message)
    assert.equals("user", message.message.role)
    assert.equals("new text", message.message.content)
  end)

  it("appends to a trailing agent-originated user message", function()
    local messages = { History.Message:new("user", "part one ") }
    local message = llm._apply_user_message_chunk(messages, "part two")
    assert.equals(messages[1], message)
    assert.equals("part one part two", message.message.content)
  end)

  it("does not append to the user's own submission", function()
    local messages = { History.Message:new("user", "typed by user", { is_user_submission = true }) }
    local message = llm._apply_user_message_chunk(messages, "other")
    assert.is_not_nil(message)
    assert.not_equals(messages[1], message)
    assert.equals("typed by user", messages[1].message.content)
  end)
end)

describe("ACP subagent terminal output", function()
  local ACPClient = require("avante.libs.acp_client")
  local stub = require("luassert.stub")
  local Config = require("avante.config")
  local setup_transport_stub
  local connect_stub

  local saved_provider, saved_acp_providers, saved_behaviour

  before_each(function()
    saved_provider, saved_acp_providers, saved_behaviour = Config.provider, Config.acp_providers, Config.behaviour
    Config.behaviour = Config.behaviour or {}
    Config.provider = "claude-code"
    Config.acp_providers = { ["claude-code"] = { command = "fake-acp", args = {}, env = {} } }
    setup_transport_stub = stub(ACPClient, "_setup_transport")
    connect_stub = stub(ACPClient, "connect")
  end)

  after_each(function()
    setup_transport_stub:revert()
    connect_stub:revert()
    Config.provider, Config.acp_providers, Config.behaviour = saved_provider, saved_acp_providers, saved_behaviour
  end)

  it("copies terminal snapshots from a child tool_call_update onto the parent message", function()
    local added = {}
    llm._stream_acp({
      just_connect_acp_client = true,
      on_messages_add = function(messages)
        for _, m in ipairs(messages) do
          added[m.uuid] = m
        end
      end,
      on_start = function() end,
      on_stop = function() end,
    })
    local client = connect_stub.calls[1].refs[1]
    assert.is_not_nil(client)
    local on_session_update = client.config.handlers.on_session_update

    on_session_update({
      sessionUpdate = "tool_call",
      toolCallId = "task-1",
      title = "Task",
      kind = "think",
      status = "in_progress",
      _meta = { claudeCode = { toolName = "Task" } },
    })
    on_session_update({
      sessionUpdate = "tool_call",
      toolCallId = "bash-1",
      title = "ls",
      kind = "execute",
      status = "in_progress",
      content = { { type = "terminal", terminalId = "term-1" } },
      _meta = { claudeCode = { toolName = "Bash", parentToolUseId = "task-1" }, terminal_info = { terminal_id = "term-1" } },
    })
    on_session_update({
      sessionUpdate = "tool_call_update",
      toolCallId = "bash-1",
      status = "completed",
      _meta = {
        terminal_output = { terminal_id = "term-1", data = "hello from subagent\n" },
        terminal_exit = { terminal_id = "term-1", exit_code = 0 },
      },
    })

    local parent = added["task-1"]
    assert.is_not_nil(parent)
    assert.is_nil(added["bash-1"], "child tool call must not become a top-level message")
    assert.equals(1, #parent.acp_children)
    assert.equals("bash-1", parent.acp_children[1].tool_call.toolCallId)
    assert.equals("completed", parent.acp_children[1].tool_call.status)
    assert.is_not_nil(parent.acp_terminals)
    assert.equals("hello from subagent\n", parent.acp_terminals["term-1"].output)
    assert.equals(0, parent.acp_terminals["term-1"].exitStatus.exitCode)

    -- the scheduled on_terminal_update also reaches the parent via acp_children
    client:push_terminal_output("term-1", "more\n")
    vim.wait(100, function() return parent.acp_terminals["term-1"].output:find("more", 1, true) ~= nil end)
    assert.equals("hello from subagent\nmore\n", parent.acp_terminals["term-1"].output)

    local Render = require("avante.history.render")
    local lines = Render.get_content_lines(parent.acp_children[1].tool_call.content, "", false, parent.acp_terminals)
    local text = table.concat(vim.tbl_map(tostring, lines), "\n")
    assert.is_truthy(text:find("hello from subagent", 1, true))
    client.transport = { stop = function() end }
    client:stop()
  end)
end)

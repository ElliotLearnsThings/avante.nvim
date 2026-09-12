local ACPClient = require("avante.libs.acp_client")
local stub = require("luassert.stub")

describe("ACPClient", function()
  local schedule_stub
  local setup_transport_stub

  before_each(function()
    schedule_stub = stub(vim, "schedule")
    schedule_stub.invokes(function(fn) fn() end)
    setup_transport_stub = stub(ACPClient, "_setup_transport")
  end)

  after_each(function()
    schedule_stub:revert()
    setup_transport_stub:revert()
  end)

  describe("_handle_read_text_file", function()
    it("should call error_callback when file read fails", function()
      local sent_error = nil
      local handler_called = false
      local mock_config = {
        transport_type = "stdio",
        handlers = {
          on_read_file = function(path, line, limit, success_callback, err_callback)
            handler_called = true
            err_callback("File not found", ACPClient.ERROR_CODES.RESOURCE_NOT_FOUND)
          end,
        },
      }

      local client = ACPClient:new(mock_config)
      client._send_error = stub().invokes(
        function(self, id, message, code) sent_error = { id = id, message = message, code = code } end
      )

      client:_handle_read_text_file(123, { sessionId = "test-session", path = "/nonexistent/file.txt" })

      assert.is_true(handler_called)
      assert.is_not_nil(sent_error)
      assert.equals(123, sent_error.id)
      assert.equals("File not found", sent_error.message)
      assert.equals(ACPClient.ERROR_CODES.RESOURCE_NOT_FOUND, sent_error.code)
    end)

    it("should use default error message when error_callback called with nil", function()
      local sent_error = nil
      local mock_config = {
        transport_type = "stdio",
        handlers = {
          on_read_file = function(path, line, limit, success_callback, err_callback) err_callback(nil, nil) end,
        },
      }

      local client = ACPClient:new(mock_config)
      client._send_error = stub().invokes(
        function(self, id, message, code) sent_error = { id = id, message = message, code = code } end
      )

      client:_handle_read_text_file(456, { sessionId = "test-session", path = "/bad/file.txt" })

      assert.is_not_nil(sent_error)
      assert.equals(456, sent_error.id)
      assert.equals("Failed to read file", sent_error.message)
      assert.is_nil(sent_error.code)
    end)

    it("should call success_callback when file read succeeds", function()
      local sent_result = nil
      local mock_config = {
        transport_type = "stdio",
        handlers = {
          on_read_file = function(path, line, limit, success_callback, err_callback) success_callback("file contents") end,
        },
      }

      local client = ACPClient:new(mock_config)
      client._send_result = stub().invokes(function(self, id, result) sent_result = { id = id, result = result } end)

      client:_handle_read_text_file(789, { sessionId = "test-session", path = "/existing/file.txt" })

      assert.is_not_nil(sent_result)
      assert.equals(789, sent_result.id)
      assert.equals("file contents", sent_result.result.content)
    end)

    it("should send error when params are invalid (missing sessionId)", function()
      local sent_error = nil
      local mock_config = {
        transport_type = "stdio",
        handlers = {
          on_read_file = function() end,
        },
      }

      local client = ACPClient:new(mock_config)
      client._send_error = stub().invokes(
        function(self, id, message, code) sent_error = { id = id, message = message, code = code } end
      )

      client:_handle_read_text_file(100, { path = "/file.txt" })

      assert.is_not_nil(sent_error)
      assert.equals(100, sent_error.id)
      assert.equals("Invalid fs/read_text_file params", sent_error.message)
      assert.equals(ACPClient.ERROR_CODES.INVALID_PARAMS, sent_error.code)
    end)

    it("should send error when params are invalid (missing path)", function()
      local sent_error = nil
      local mock_config = {
        transport_type = "stdio",
        handlers = {
          on_read_file = function() end,
        },
      }

      local client = ACPClient:new(mock_config)
      client._send_error = stub().invokes(
        function(self, id, message, code) sent_error = { id = id, message = message, code = code } end
      )

      client:_handle_read_text_file(200, { sessionId = "test-session" })

      assert.is_not_nil(sent_error)
      assert.equals(200, sent_error.id)
      assert.equals("Invalid fs/read_text_file params", sent_error.message)
      assert.equals(ACPClient.ERROR_CODES.INVALID_PARAMS, sent_error.code)
    end)

    it("should send error when handler is not configured", function()
      local sent_error = nil
      local mock_config = {
        transport_type = "stdio",
        handlers = {},
      }

      local client = ACPClient:new(mock_config)
      client._send_error = stub().invokes(
        function(self, id, message, code) sent_error = { id = id, message = message, code = code } end
      )

      client:_handle_read_text_file(300, { sessionId = "test-session", path = "/file.txt" })

      assert.is_not_nil(sent_error)
      assert.equals(300, sent_error.id)
      assert.equals("fs/read_text_file handler not configured", sent_error.message)
      assert.equals(ACPClient.ERROR_CODES.METHOD_NOT_FOUND, sent_error.code)
    end)
  end)

  describe("_handle_write_text_file", function()
    it("should send error when params are invalid (missing sessionId)", function()
      local sent_error = nil
      local mock_config = {
        transport_type = "stdio",
        handlers = {
          on_write_file = function() end,
        },
      }

      local client = ACPClient:new(mock_config)
      client._send_error = stub().invokes(
        function(self, id, message, code) sent_error = { id = id, message = message, code = code } end
      )

      client:_handle_write_text_file(400, { path = "/file.txt", content = "data" })

      assert.is_not_nil(sent_error)
      assert.equals(400, sent_error.id)
      assert.equals("Invalid fs/write_text_file params", sent_error.message)
      assert.equals(ACPClient.ERROR_CODES.INVALID_PARAMS, sent_error.code)
    end)

    it("should send error when params are invalid (missing path)", function()
      local sent_error = nil
      local mock_config = {
        transport_type = "stdio",
        handlers = {
          on_write_file = function() end,
        },
      }

      local client = ACPClient:new(mock_config)
      client._send_error = stub().invokes(
        function(self, id, message, code) sent_error = { id = id, message = message, code = code } end
      )

      client:_handle_write_text_file(500, { sessionId = "test-session", content = "data" })

      assert.is_not_nil(sent_error)
      assert.equals(500, sent_error.id)
      assert.equals("Invalid fs/write_text_file params", sent_error.message)
      assert.equals(ACPClient.ERROR_CODES.INVALID_PARAMS, sent_error.code)
    end)

    it("should send error when params are invalid (missing content)", function()
      local sent_error = nil
      local mock_config = {
        transport_type = "stdio",
        handlers = {
          on_write_file = function() end,
        },
      }

      local client = ACPClient:new(mock_config)
      client._send_error = stub().invokes(
        function(self, id, message, code) sent_error = { id = id, message = message, code = code } end
      )

      client:_handle_write_text_file(600, { sessionId = "test-session", path = "/file.txt" })

      assert.is_not_nil(sent_error)
      assert.equals(600, sent_error.id)
      assert.equals("Invalid fs/write_text_file params", sent_error.message)
      assert.equals(ACPClient.ERROR_CODES.INVALID_PARAMS, sent_error.code)
    end)

    it("should send error when handler is not configured", function()
      local sent_error = nil
      local mock_config = {
        transport_type = "stdio",
        handlers = {},
      }

      local client = ACPClient:new(mock_config)
      client._send_error = stub().invokes(
        function(self, id, message, code) sent_error = { id = id, message = message, code = code } end
      )

      client:_handle_write_text_file(700, { sessionId = "test-session", path = "/file.txt", content = "data" })

      assert.is_not_nil(sent_error)
      assert.equals(700, sent_error.id)
      assert.equals("fs/write_text_file handler not configured", sent_error.message)
      assert.equals(ACPClient.ERROR_CODES.METHOD_NOT_FOUND, sent_error.code)
    end)
  end)

  describe("prompt capabilities", function()
    local function make_client(init_result)
      local client
      local mock_transport = {
        send = function(self, data)
          local decoded = vim.json.decode(data)
          if decoded.method == "initialize" then
            vim.schedule(function() client:_handle_message({ jsonrpc = "2.0", id = decoded.id, result = init_result }) end)
          end
        end,
        start = function(self, on_message) end,
        stop = function(self) end,
      }
      client = ACPClient:new({ transport_type = "stdio", handlers = {} })
      client.transport = mock_transport
      client.state = "connected"
      return client
    end

    it("returns an empty table before initialization", function()
      local client = ACPClient:new({ transport_type = "stdio", handlers = {} })
      assert.same({}, client:get_prompt_capabilities())
      assert.is_false(client:supports_prompt_capability("image"))
    end)

    it("stores promptCapabilities from the initialize response", function()
      local client = make_client({
        protocolVersion = 1,
        agentCapabilities = {
          loadSession = true,
          promptCapabilities = { image = true, embeddedContext = true },
        },
      })

      local init_err = "not called"
      client:initialize(function(err) init_err = err end)

      assert.is_nil(init_err)
      assert.same({ image = true, embeddedContext = true }, client:get_prompt_capabilities())
      assert.is_true(client:supports_prompt_capability("image"))
      assert.is_true(client:supports_prompt_capability("embeddedContext"))
      assert.is_false(client:supports_prompt_capability("audio"))
    end)

    it("treats missing promptCapabilities as unsupported", function()
      local client = make_client({ protocolVersion = 1, agentCapabilities = { loadSession = false } })
      client:initialize(function() end)

      assert.same({}, client:get_prompt_capabilities())
      assert.is_false(client:supports_prompt_capability("image"))
      assert.is_false(client:supports_prompt_capability("embeddedContext"))
    end)
  end)

  describe("content constructors", function()
    it("builds image content blocks", function()
      local client = ACPClient:new({ transport_type = "stdio", handlers = {} })
      assert.same(
        { type = "image", data = "AAAA", mimeType = "image/png", uri = "file:///tmp/a.png" },
        client:create_image_content("AAAA", "image/png", "file:///tmp/a.png")
      )
    end)

    it("builds embedded text resource blocks", function()
      local client = ACPClient:new({ transport_type = "stdio", handlers = {} })
      assert.same(
        { type = "resource", resource = { uri = "file:///tmp/a.lua", text = "print(1)", mimeType = "text/x-lua" } },
        client:create_resource_content(client:create_text_resource("file:///tmp/a.lua", "print(1)", "text/x-lua"))
      )
    end)
  end)

  describe("ERROR_CODES", function()
    it("defines the client-side codes referenced by the implementation", function()
      assert.equals(-32010, ACPClient.ERROR_CODES.PROTOCOL_ERROR)
      assert.equals(-32011, ACPClient.ERROR_CODES.TIMEOUT_ERROR)
      local seen = {}
      for name, code in pairs(ACPClient.ERROR_CODES) do
        assert.is_nil(seen[code], "duplicate error code for " .. name)
        seen[code] = name
      end
    end)

    it("wait_ready reports PROTOCOL_ERROR with a numeric code when in error state", function()
      local client = ACPClient:new({ transport_type = "stdio", handlers = {} })
      client.state = "error"
      local got
      client:wait_ready(function(err) got = err end, 0)
      assert.is_not_nil(got)
      assert.equals(ACPClient.ERROR_CODES.PROTOCOL_ERROR, got.code)
    end)
  end)

  describe("permission requests", function()
    local function new_client_with_transport(on_permission)
      local sent = {}
      local client = ACPClient:new({
        transport_type = "stdio",
        handlers = { on_request_permission = on_permission },
      })
      client.transport = {
        send = function(_, data) table.insert(sent, vim.json.decode(data)) end,
        start = function() end,
        stop = function() end,
      }
      client.state = "ready"
      return client, sent
    end

    local permission_params = {
      sessionId = "s1",
      toolCall = { toolCallId = "tc1", title = "bash", kind = "execute" },
      options = {
        { optionId = "allow", name = "Allow", kind = "allow_once" },
        { optionId = "reject", name = "Reject", kind = "reject_once" },
      },
    }

    it("answers with selected when the handler picks an option", function()
      local client, sent = new_client_with_transport(function(_tool_call, _options, cb) cb("allow") end)
      client:_handle_message({ jsonrpc = "2.0", id = 42, method = "session/request_permission", params = permission_params })
      assert.equals(1, #sent)
      assert.equals(42, sent[1].id)
      assert.same({ outcome = "selected", optionId = "allow" }, sent[1].result.outcome)
      assert.is_nil(next(client.pending_permissions))
    end)

    it("answers with cancelled when the handler passes nil", function()
      local client, sent = new_client_with_transport(function(_tool_call, _options, cb) cb(nil) end)
      client:_handle_message({ jsonrpc = "2.0", id = 7, method = "session/request_permission", params = permission_params })
      assert.equals(1, #sent)
      assert.same({ outcome = "cancelled" }, sent[1].result.outcome)
    end)

    it("cancel_session resolves in-flight permission requests with cancelled before session/cancel", function()
      local pending_cb
      local client, sent = new_client_with_transport(function(_tool_call, _options, cb) pending_cb = cb end)
      client:_handle_message({ jsonrpc = "2.0", id = 9, method = "session/request_permission", params = permission_params })
      client:_handle_message({ jsonrpc = "2.0", id = 10, method = "session/request_permission", params = permission_params })
      assert.is_true(client.pending_permissions[9])
      assert.is_true(client.pending_permissions[10])
      assert.equals(0, #sent)

      client:cancel_session("s1")

      assert.equals(3, #sent)
      assert.equals(9, sent[1].id)
      assert.same({ outcome = "cancelled" }, sent[1].result.outcome)
      assert.equals(10, sent[2].id)
      assert.same({ outcome = "cancelled" }, sent[2].result.outcome)
      assert.equals("session/cancel", sent[3].method)
      assert.equals("s1", sent[3].params.sessionId)
      assert.is_nil(next(client.pending_permissions))

      -- A late answer from the UI must not produce a second response
      pending_cb("allow")
      assert.equals(3, #sent)
    end)

    it("cancel_session with no pending permissions only sends session/cancel", function()
      local client, sent = new_client_with_transport(function() end)
      client:cancel_session("s1")
      assert.equals(1, #sent)
      assert.equals("session/cancel", sent[1].method)
    end)
  end)

  describe("stderr diagnostics", function()
    it("keeps a bounded tail of stderr lines", function()
      local client = ACPClient:new({ transport_type = "stdio", handlers = {} })
      for i = 1, ACPClient.STDERR_TAIL_LINES + 5 do
        client:_record_stderr("line " .. i .. "\n")
      end
      assert.equals(ACPClient.STDERR_TAIL_LINES, #client.stderr_lines)
      assert.equals("line 6", client.stderr_lines[1])
      assert.equals("line " .. (ACPClient.STDERR_TAIL_LINES + 5), client.stderr_lines[#client.stderr_lines])
    end)

    it("includes stderr and command in the spawn failure message and fails pending callbacks", function()
      local client = ACPClient:new({ transport_type = "stdio", command = "claude-agent-acp", args = {}, handlers = {} })
      client:_record_stderr("Error: Cannot find module 'foo'\n")
      local msg = client:_format_spawn_failure(1, 0)
      assert.truthy(msg:find("claude-agent-acp", 1, true))
      assert.truthy(msg:find("exited with code 1", 1, true))
      assert.truthy(msg:find("Cannot find module 'foo'", 1, true))

      local got
      client.callbacks[1] = function(_, err) got = err end
      client:_fail_pending_callbacks(client:_create_error(ACPClient.ERROR_CODES.PROTOCOL_ERROR, msg))
      assert.is_not_nil(got)
      assert.equals(ACPClient.ERROR_CODES.PROTOCOL_ERROR, got.code)
      assert.is_nil(next(client.callbacks))
    end)
  end)

  describe("MCP tool flow", function()
    local MCP_TOOL_UUID = "mcp-test-uuid-12345-67890"

    it("receives MCP tool result via session/update when mcp_servers configured", function()
      local sent_request = nil
      local session_updates = {}
      local client

      local mock_transport = {
        send = function(self, data)
          local decoded = vim.json.decode(data)

          if decoded.method == "session/new" then
            sent_request = decoded.params

            vim.schedule(
              function()
                client:_handle_message({
                  jsonrpc = "2.0",
                  id = decoded.id,
                  result = { sessionId = "test-session-mcp" },
                })
              end
            )
          elseif decoded.method == "session/prompt" then
            vim.schedule(
              function()
                client:_handle_message({
                  jsonrpc = "2.0",
                  method = "session/update",
                  params = {
                    sessionId = "test-session-mcp",
                    update = {
                      sessionUpdate = "tool_call",
                      toolCallId = "mcp-tool-1",
                      title = "lookup__get_code",
                      kind = "other",
                      status = "completed",
                      content = {
                        {
                          type = "content",
                          content = { type = "text", text = MCP_TOOL_UUID },
                        },
                      },
                    },
                  },
                })
              end
            )

            vim.schedule(
              function()
                client:_handle_message({
                  jsonrpc = "2.0",
                  id = decoded.id,
                  result = { stopReason = "end_turn" },
                })
              end
            )
          end
        end,
        start = function(self, on_message) end,
        stop = function(self) end,
      }

      local mock_config = {
        transport_type = "stdio",
        handlers = {
          on_session_update = function(update) table.insert(session_updates, update) end,
        },
      }

      client = ACPClient:new(mock_config)
      client.transport = mock_transport
      client.state = "ready"

      local mcp_servers = {
        { type = "http", name = "lookup", url = "http://localhost:8080/mcp" },
      }
      local session_id = nil
      client:create_session("/tmp/test", mcp_servers, function(sid, _err) session_id = sid end)

      assert.is_not_nil(sent_request)
      assert.equals("/tmp/test", sent_request.cwd)
      assert.same(mcp_servers, sent_request.mcpServers)
      assert.equals("test-session-mcp", session_id)

      client:send_prompt("test-session-mcp", { { type = "text", text = "Use the get_code tool" } }, function() end)

      assert.equals(1, #session_updates)
      assert.equals("tool_call", session_updates[1].sessionUpdate)
      assert.equals("lookup__get_code", session_updates[1].title)
      assert.equals("completed", session_updates[1].status)

      local tool_content = session_updates[1].content[1].content.text
      assert.equals(MCP_TOOL_UUID, tool_content)
    end)

    it("should default mcp_servers to empty array", function()
      local sent_params = nil
      local client

      local mock_transport = {
        send = function(self, data)
          local decoded = vim.json.decode(data)
          if decoded.method == "session/new" then
            sent_params = decoded.params
            vim.schedule(
              function()
                client:_handle_message({
                  jsonrpc = "2.0",
                  id = decoded.id,
                  result = { sessionId = "test-session" },
                })
              end
            )
          end
        end,
        start = function(_self, _on_message) end,
        stop = function(_self) end,
      }

      client = ACPClient:new({ transport_type = "stdio", handlers = {} })
      client.transport = mock_transport
      client.state = "ready"

      client:create_session("/tmp/test", nil, function() end)

      assert.is_not_nil(sent_params)
      assert.same({}, sent_params.mcpServers)
    end)
  end)

  describe("build_spawn_env", function()
    it("inherits the base environment and layers the provider env on top", function()
      local env = ACPClient.build_spawn_env(
        { CLAUDE_CODE_EXECUTABLE = "/usr/local/bin/claude", PATH = "/override", MISSING = nil, NUM = 1 },
        { HOME = "/Users/me", PATH = "/usr/bin", SSH_AUTH_SOCK = "/tmp/agent" }
      )
      assert.same({
        "CLAUDE_CODE_EXECUTABLE=/usr/local/bin/claude",
        "HOME=/Users/me",
        "NUM=1",
        "PATH=/override",
        "SSH_AUTH_SOCK=/tmp/agent",
      }, env)
    end)

    it("skips vim.NIL values and tolerates a nil provider env", function()
      assert.same({ "HOME=/h" }, ACPClient.build_spawn_env({ KEY = vim.NIL }, { HOME = "/h" }))
      assert.same({ "HOME=/h" }, ACPClient.build_spawn_env(nil, { HOME = "/h" }))
    end)

    it("defaults to the running Neovim environment", function()
      local env = ACPClient.build_spawn_env({ AVANTE_SPEC_MARKER = "1" })
      local has_home, has_marker = false, false
      for _, entry in ipairs(env) do
        if entry:match("^HOME=") then has_home = true end
        if entry == "AVANTE_SPEC_MARKER=1" then has_marker = true end
      end
      assert.is_true(has_home)
      assert.is_true(has_marker)
    end)
  end)

  describe("describe_error", function()
    it("explains authRequired with the /login hint", function()
      local err = ACPClient.describe_error({ code = -32000, message = "Authentication required" })
      assert.equals(-32000, err.code)
      assert.truthy(err.message:find("not logged in", 1, true))
      assert.truthy(err.message:find("/login", 1, true))
      assert.truthy(err.message:find("claude auth login", 1, true))
      assert.equals("Authentication required", err.data.original_message)
    end)

    it("points subscription refusals at a Console login", function()
      local err = ACPClient.describe_error({
        code = -32000,
        message = "Authentication required",
        data = { reason = "claude_subscription_not_supported" },
      })
      assert.truthy(err.message:find("/login --console", 1, true))
    end)
  end)

  describe("_auth/status_update", function()
    it("stores the agent's auth status and forwards it to the handler", function()
      local seen
      local client = ACPClient:new({
        transport_type = "stdio",
        handlers = { on_auth_status_update = function(status) seen = status end },
      })
      client.state = "ready"
      local status = { kind = "account", label = "Claude Max", account = { email = "me@example.com" } }
      client:_handle_message({ jsonrpc = "2.0", method = "_auth/status_update", params = { authStatus = status } })
      assert.same(status, client.auth_status)
      assert.same(status, seen)
    end)
  end)

  describe("describe_session_error", function()
    it("explains an unsupported permissions.defaultMode", function()
      local err = ACPClient.describe_session_error({
        code = -32603,
        message = "Internal error",
        data = { details = "Invalid permissions.defaultMode: auto." },
      })
      assert.equals(-32603, err.code)
      assert.truthy(err.message:find('permissions.defaultMode = "auto"', 1, true))
      assert.truthy(err.message:find("@agentclientprotocol/claude-agent-acp", 1, true))
      assert.truthy(err.message:find(".claude/settings.local.json", 1, true))
      assert.equals("Internal error", err.data.original_message)
      assert.equals("Invalid permissions.defaultMode: auto.", err.data.details)
    end)

    it("appends other details to the message", function()
      local err = ACPClient.describe_session_error({
        code = -32603,
        message = "Internal error",
        data = { details = "spawn claude ENOENT" },
      })
      assert.equals("Internal error: spawn claude ENOENT", err.message)
    end)

    it("returns errors without details untouched", function()
      local err = { code = -32601, message = "Method not found" }
      assert.equals(err, ACPClient.describe_session_error(err))
      assert.equals("nope", ACPClient.describe_session_error("nope"))
    end)

    it("is applied to session/new failures", function()
      local client
      local got_err
      local mock_transport = {
        send = function(_self, data)
          local decoded = vim.json.decode(data)
          if decoded.method == "session/new" then
            vim.schedule(
              function()
                client:_handle_message({
                  jsonrpc = "2.0",
                  id = decoded.id,
                  error = {
                    code = -32603,
                    message = "Internal error",
                    data = { details = "Invalid permissions.defaultMode: auto." },
                  },
                })
              end
            )
          end
        end,
        start = function(_self, _on_message) end,
        stop = function(_self) end,
      }
      client = ACPClient:new({ transport_type = "stdio", handlers = {} })
      client.transport = mock_transport
      client.state = "ready"

      client:create_session("/tmp/test", nil, function(_sid, err) got_err = err end)
      vim.wait(200, function() return got_err ~= nil end)

      assert.is_not_nil(got_err)
      assert.truthy(got_err.message:find("claude-agent-acp rejected", 1, true))
    end)
  end)

  describe("normalize_mcp_servers", function()
    it("returns an empty list for nil or empty input", function()
      assert.same({}, ACPClient.normalize_mcp_servers(nil))
      assert.same({}, ACPClient.normalize_mcp_servers({}))
      assert.same({}, ACPClient.normalize_mcp_servers("nope"))
    end)

    it("converts keyed table form into the ACP list form", function()
      local result = ACPClient.normalize_mcp_servers({
        filesystem = {
          command = "npx",
          args = { "-y", "@modelcontextprotocol/server-filesystem", "/tmp" },
          env = { FOO = "bar" },
        },
        remote = { type = "http", url = "http://localhost:8080/mcp", headers = { Authorization = "Bearer x" } },
      })
      assert.same({
        {
          name = "filesystem",
          command = "npx",
          args = { "-y", "@modelcontextprotocol/server-filesystem", "/tmp" },
          env = { { name = "FOO", value = "bar" } },
        },
        {
          type = "http",
          name = "remote",
          url = "http://localhost:8080/mcp",
          headers = { { name = "Authorization", value = "Bearer x" } },
        },
      }, result)
    end)

    it("sorts keyed env vars by name for deterministic output", function()
      local result = ACPClient.normalize_mcp_servers({
        srv = { command = "x", env = { ZED = "1", ALPHA = "2", MID = "3" } },
      })
      assert.same({
        { name = "ALPHA", value = "2" },
        { name = "MID", value = "3" },
        { name = "ZED", value = "1" },
      }, result[1].env)
    end)

    it("passes raw ACP list form through and normalizes env tables inside it", function()
      local raw = {
        { name = "lookup", type = "http", url = "http://localhost:8080/mcp" },
        { name = "local", command = "srv", args = { "--flag" }, env = { { name = "A", value = "1" } } },
        { name = "keyed_env", command = "srv2", env = { B = "2" } },
      }
      local result = ACPClient.normalize_mcp_servers(raw)
      assert.same({
        { type = "http", name = "lookup", url = "http://localhost:8080/mcp", headers = {} },
        { name = "local", command = "srv", args = { "--flag" }, env = { { name = "A", value = "1" } } },
        { name = "keyed_env", command = "srv2", args = {}, env = { { name = "B", value = "2" } } },
      }, result)
    end)

    it("drops disabled servers and entries without command/url", function()
      local result = ACPClient.normalize_mcp_servers({
        off = { command = "x", disabled = true },
        off2 = { command = "x", enabled = false },
        nocmd = { args = { "a" } },
        nourl = { type = "sse" },
        ok = { command = "x" },
      })
      assert.same({ { name = "ok", command = "x", args = {}, env = {} } }, result)
    end)

    it("infers http type when only a url is given", function()
      local result = ACPClient.normalize_mcp_servers({ remote = { url = "http://h/mcp" } })
      assert.same({ { type = "http", name = "remote", url = "http://h/mcp", headers = {} } }, result)
    end)
  end)

  describe("terminals", function()
    local function make_client(handlers)
      local client = ACPClient:new({ transport_type = "stdio", handlers = handlers or {} })
      client.sent = {}
      client.transport = {
        send = function(_self, data) table.insert(client.sent, vim.json.decode(data)) end,
        start = function() end,
        stop = function() end,
      }
      client.state = "ready"
      return client
    end

    local function last_sent(client) return client.sent[#client.sent] end

    local function fake_spawn(on_spawn)
      return function(_self, terminal, env)
        terminal.handle = {
          kill = function() end,
          is_closing = function() return false end,
          close = function() end,
        }
        if on_spawn then on_spawn(terminal, env) end
        return nil
      end
    end

    it("advertises the terminal capability in initialize", function()
      local client = make_client()
      client.state = "connected"
      client:initialize(function() end)
      local init = client.sent[1]
      assert.equals("initialize", init.method)
      assert.is_true(init.params.clientCapabilities.terminal)
      assert.is_true(init.params.clientCapabilities._meta.terminal_output)
      assert.is_true(init.params.clientCapabilities.fs.readTextFile)
    end)

    it("rejects terminal/create with invalid params", function()
      local client = make_client()
      client:_handle_message({ jsonrpc = "2.0", id = 1, method = "terminal/create", params = { sessionId = "s" } })
      local msg = last_sent(client)
      assert.equals(1, msg.id)
      assert.equals(ACPClient.ERROR_CODES.INVALID_PARAMS, msg.error.code)
    end)

    it("returns RESOURCE_NOT_FOUND for unknown terminal ids", function()
      local client = make_client()
      for idx, method in ipairs({ "terminal/output", "terminal/wait_for_exit", "terminal/kill", "terminal/release" }) do
        client:_handle_message({
          jsonrpc = "2.0",
          id = idx,
          method = method,
          params = { sessionId = "s", terminalId = "nope" },
        })
        local msg = last_sent(client)
        assert.equals(idx, msg.id)
        assert.equals(ACPClient.ERROR_CODES.RESOURCE_NOT_FOUND, msg.error.code)
      end
    end)

    it("creates a terminal, streams output, waits for exit, kills and releases", function()
      local updates = {}
      local client = make_client({
        on_terminal_update = function(terminal) table.insert(updates, ACPClient.terminal_snapshot(terminal)) end,
      })

      local spawned, spawned_env
      local killed = false
      client._spawn_terminal = fake_spawn(function(terminal, env)
        spawned = terminal
        spawned_env = env
        terminal.handle.kill = function() killed = true end
      end)

      client:_handle_message({
        jsonrpc = "2.0",
        id = 10,
        method = "terminal/create",
        params = {
          sessionId = "sess",
          command = "echo",
          args = { "hello", "world" },
          env = { { name = "FOO", value = "bar" } },
          cwd = "/tmp",
          outputByteLimit = 8,
        },
      })
      local created = last_sent(client)
      assert.equals(10, created.id)
      local terminal_id = created.result.terminalId
      assert.is_string(terminal_id)
      assert.is_not_nil(client:get_terminal(terminal_id))
      assert.equals("echo", spawned.command)
      assert.same({ "hello", "world" }, spawned.args)
      assert.equals("/tmp", spawned.cwd)
      assert.equals("sess", spawned.session_id)
      assert.same({ FOO = "bar" }, spawned_env)

      -- No output yet
      client:_handle_message({
        jsonrpc = "2.0",
        id = 11,
        method = "terminal/output",
        params = { sessionId = "sess", terminalId = terminal_id },
      })
      local out = last_sent(client)
      assert.equals("", out.result.output)
      assert.is_false(out.result.truncated)
      assert.is_nil(out.result.exitStatus)

      -- wait_for_exit before exit stays pending
      client:_handle_message({
        jsonrpc = "2.0",
        id = 12,
        method = "terminal/wait_for_exit",
        params = { sessionId = "sess", terminalId = terminal_id },
      })
      assert.equals(11, last_sent(client).id)
      assert.equals(1, #spawned.waiters)

      -- Output arrives (exceeds the 8 byte limit -> truncated from the beginning)
      client:_append_terminal_output(spawned, "hello ")
      client:_append_terminal_output(spawned, "world\n")
      client:_handle_message({
        jsonrpc = "2.0",
        id = 13,
        method = "terminal/output",
        params = { sessionId = "sess", terminalId = terminal_id },
      })
      out = last_sent(client)
      assert.equals("o world\n", out.result.output)
      assert.is_true(out.result.truncated)
      assert.is_true(#updates >= 2)

      -- Process exits -> pending wait_for_exit resolves
      client:_set_terminal_exit(spawned, { exitCode = 3, signal = nil })
      local exited = last_sent(client)
      assert.equals(12, exited.id)
      assert.equals(3, exited.result.exitCode)
      assert.equals(vim.NIL, exited.result.signal)
      assert.equals(0, #spawned.waiters)

      -- wait_for_exit after exit resolves immediately; output carries exitStatus
      client:_handle_message({
        jsonrpc = "2.0",
        id = 14,
        method = "terminal/wait_for_exit",
        params = { sessionId = "sess", terminalId = terminal_id },
      })
      assert.equals(14, last_sent(client).id)
      assert.equals(3, last_sent(client).result.exitCode)
      client:_handle_message({
        jsonrpc = "2.0",
        id = 15,
        method = "terminal/output",
        params = { sessionId = "sess", terminalId = terminal_id },
      })
      assert.equals(3, last_sent(client).result.exitStatus.exitCode)

      -- kill on an exited terminal is a harmless no-op
      client:_handle_message({
        jsonrpc = "2.0",
        id = 16,
        method = "terminal/kill",
        params = { sessionId = "sess", terminalId = terminal_id },
      })
      assert.equals(16, last_sent(client).id)
      assert.is_nil(last_sent(client).error)
      assert.is_false(killed)

      -- release drops the terminal
      client:_handle_message({
        jsonrpc = "2.0",
        id = 17,
        method = "terminal/release",
        params = { sessionId = "sess", terminalId = terminal_id },
      })
      assert.equals(17, last_sent(client).id)
      assert.is_nil(last_sent(client).error)
      assert.is_nil(client:get_terminal(terminal_id))
      assert.is_true(spawned.released)
    end)

    it("kills running terminals on terminal/kill, session cancel and stop", function()
      local client = make_client()
      local kills = {}
      client._spawn_terminal = fake_spawn(function(terminal)
        terminal.handle.kill = function(_h, sig) table.insert(kills, { terminal.id, sig }) end
      end)
      local defer_stub = stub(vim, "defer_fn")
      defer_stub.invokes(function() end)

      for i = 1, 3 do
        client:_handle_message({
          jsonrpc = "2.0",
          id = i,
          method = "terminal/create",
          params = { sessionId = i == 3 and "other" or "sess", command = "sleep", args = { "100" } },
        })
      end
      local ids = {}
      for i = 1, 3 do
        ids[i] = client.sent[i].result.terminalId
      end

      client:_handle_message({
        jsonrpc = "2.0",
        id = 20,
        method = "terminal/kill",
        params = { sessionId = "sess", terminalId = ids[1] },
      })
      assert.same({ { ids[1], 15 } }, kills)
      assert.is_not_nil(client:get_terminal(ids[1]))

      -- Session cancel kills every terminal of that session (but keeps the records)
      kills = {}
      client:cancel_session("sess")
      table.sort(kills, function(a, b) return a[1] < b[1] end)
      assert.same({ { ids[1], 15 }, { ids[2], 15 } }, kills)
      assert.equals("session/cancel", last_sent(client).method)
      assert.is_not_nil(client:get_terminal(ids[2]))
      -- Simulate the killed processes exiting
      client:_set_terminal_exit(client:get_terminal(ids[1]), { signal = "SIGTERM" })
      client:_set_terminal_exit(client:get_terminal(ids[2]), { signal = "SIGTERM" })

      -- Stop kills whatever is still running and drops every terminal
      kills = {}
      client:stop()
      assert.same({ { ids[3], 15 } }, kills)
      assert.same({}, client.terminals)

      defer_stub:revert()
    end)

    it("handles terminal/create spawn failures", function()
      local client = make_client()
      client._spawn_terminal = function() return "boom" end
      client:_handle_message({
        jsonrpc = "2.0",
        id = 30,
        method = "terminal/create",
        params = { sessionId = "sess", command = "definitely-not-a-command" },
      })
      local msg = last_sent(client)
      assert.equals(30, msg.id)
      assert.equals("boom", msg.error.message)
      assert.same({}, client.terminals)
    end)

    it("truncates output on a UTF-8 character boundary", function()
      local output, truncated = ACPClient.truncate_terminal_output("aé😀b", 5)
      assert.is_true(truncated)
      assert.equals("😀b", output)
      output, truncated = ACPClient.truncate_terminal_output("abc", 10)
      assert.is_false(truncated)
      assert.equals("abc", output)
    end)

    it("tracks virtual terminals fed through _meta (claude-agent-acp)", function()
      local updates = {}
      local client = make_client({
        on_terminal_update = function(terminal) table.insert(updates, ACPClient.terminal_snapshot(terminal)) end,
      })
      client:ensure_virtual_terminal("toolu_1", "sess")
      client:push_terminal_output("toolu_1", "line 1\n", "sess")
      client:push_terminal_output("toolu_1", "line 2\n", "sess")
      client:push_terminal_exit("toolu_1", { exitCode = 0 }, "sess")
      local terminal = client:get_terminal("toolu_1")
      assert.is_true(terminal.virtual)
      assert.equals("line 1\nline 2\n", terminal.output)
      assert.equals(0, terminal.exit_status.exitCode)
      assert.equals(3, #updates)
      assert.equals(0, updates[3].exitStatus.exitCode)
    end)

    it("spawns a real process and collects its output", function()
      local client = make_client()
      client:_handle_message({
        jsonrpc = "2.0",
        id = 40,
        method = "terminal/create",
        params = { sessionId = "sess", command = "sh", args = { "-c", "printf hi; exit 7" } },
      })
      local terminal_id = last_sent(client).result.terminalId
      client:_handle_message({
        jsonrpc = "2.0",
        id = 41,
        method = "terminal/wait_for_exit",
        params = { sessionId = "sess", terminalId = terminal_id },
      })
      vim.wait(5000, function() return last_sent(client).id == 41 end, 10)
      local exited = last_sent(client)
      assert.equals(41, exited.id)
      assert.equals(7, exited.result.exitCode)
      assert.equals("hi", client:get_terminal(terminal_id).output)
    end)
  end)
end)

describe("ACPClient mode updates", function()
  local schedule_stub

  before_each(function()
    schedule_stub = stub(vim, "schedule")
    schedule_stub.invokes(function(fn) fn() end)
  end)

  after_each(function() schedule_stub:revert() end)

  local function new_client_with_mode(handler)
    local client = ACPClient:new({ transport_type = "stdio", handlers = { on_session_update = handler } })
    client.config_options = {
      {
        id = "mode",
        category = "mode",
        currentValue = "default",
        options = { { value = "default", name = "Default" }, { value = "plan", name = "Plan Mode" } },
      },
      { id = "model", category = "model", currentValue = "sonnet", options = {} },
    }
    return client
  end

  it("applies current_mode_update using the spec field currentModeId", function()
    local received = nil
    local client = new_client_with_mode(function(update) received = update end)

    client:_handle_session_update({
      sessionId = "s",
      update = { sessionUpdate = "current_mode_update", currentModeId = "plan" },
    })

    assert.equals("plan", client:get_current_mode())
    assert.is_not_nil(received)
    assert.equals("plan", received.currentModeId)
    -- legacy alias is populated for downstream consumers
    assert.equals("plan", received.modeId)
  end)

  it("still accepts the legacy modeId field", function()
    local client = new_client_with_mode(function() end)
    client:_handle_session_update({
      sessionId = "s",
      update = { sessionUpdate = "current_mode_update", modeId = "plan" },
    })
    assert.equals("plan", client:get_current_mode())
  end)

  it("replaces config options on config_option_update", function()
    local client = new_client_with_mode(function() end)
    client:_handle_session_update({
      sessionId = "s",
      update = {
        sessionUpdate = "config_option_update",
        configOptions = { { id = "mode", category = "mode", currentValue = "acceptEdits", options = {} } },
      },
    })
    assert.equals("acceptEdits", client:get_current_mode())
    assert.equals("mode", client:get_mode_option().id)
  end)

  it("get_current_mode returns nil without config options", function()
    local client = ACPClient:new({ transport_type = "stdio", handlers = {} })
    assert.is_nil(client:get_current_mode())
    assert.is_nil(client:get_mode_option())
  end)

  it("set_mode sends session/set_mode and updates the local mode option", function()
    local client = new_client_with_mode(function() end)
    local sent = nil
    client._send_request = function(_, method, params, cb)
      sent = { method = method, params = params }
      cb({}, nil)
    end
    local result_options
    client:set_mode("s", "plan", function(options, err)
      result_options = options
      assert.is_nil(err)
    end)
    assert.equals("session/set_mode", sent.method)
    assert.equals("plan", sent.params.modeId)
    assert.equals("s", sent.params.sessionId)
    assert.equals("plan", client:get_current_mode())
    assert.is_not_nil(result_options)
  end)
end)

describe("ACPClient request/response robustness", function()
  local stub = require("luassert.stub")
  local schedule_stub
  local setup_transport_stub

  before_each(function()
    schedule_stub = stub(vim, "schedule")
    schedule_stub.invokes(function(fn) fn() end)
    setup_transport_stub = stub(ACPClient, "_setup_transport")
  end)

  after_each(function()
    schedule_stub:revert()
    setup_transport_stub:revert()
  end)

  ---@param handlers table
  local function new_client(handlers)
    local sent = {}
    local client = ACPClient:new({ transport_type = "stdio", handlers = handlers })
    client.transport = {
      send = function(_, data)
        table.insert(sent, vim.json.decode(data))
        return true
      end,
      start = function() end,
      stop = function() end,
    }
    client.state = "ready"
    return client, sent
  end

  local permission_params = {
    sessionId = "s1",
    toolCall = { toolCallId = "tc1", title = "Edit", kind = "edit" },
    options = {
      { optionId = "allow", name = "Allow", kind = "allow_once" },
      { optionId = "reject", name = "Reject", kind = "reject_once" },
    },
  }

  describe("permission request queue", function()
    it("shows parallel permission requests one after another and answers each", function()
      local prompts = {}
      local client, sent = new_client({
        on_request_permission = function(tool_call, _, answer) table.insert(prompts, { tool_call, answer }) end,
      })

      -- Claude Code issues one request per parallel Edit; both arrive before either is answered
      client:_handle_request_permission(10, permission_params)
      client:_handle_request_permission(11, vim.tbl_deep_extend("force", permission_params, {
        toolCall = { toolCallId = "tc2" },
      }))

      assert.equals(1, #prompts, "only one prompt may be visible at a time")
      assert.equals("tc1", prompts[1][1].toolCallId)
      assert.equals(0, #sent)

      prompts[1][2]("allow")
      assert.equals(1, #sent)
      assert.equals(10, sent[1].id)
      assert.equals("allow", sent[1].result.outcome.optionId)

      -- the second request is only shown once the first one is answered
      assert.equals(2, #prompts)
      assert.equals("tc2", prompts[2][1].toolCallId)
      prompts[2][2]("reject")
      assert.equals(2, #sent)
      assert.equals(11, sent[2].id)
      assert.equals("reject", sent[2].result.outcome.optionId)
      assert.is_nil(client.active_permission_id)
      assert.is_nil(next(client.pending_permissions))
    end)

    it("ignores a second answer to the same request", function()
      local answers = {}
      local client, sent = new_client({
        on_request_permission = function(_, _, answer) table.insert(answers, answer) end,
      })
      client:_handle_request_permission(20, permission_params)
      answers[1]("allow")
      answers[1]("reject")
      assert.equals(1, #sent)
      assert.equals("allow", sent[1].result.outcome.optionId)
    end)

    it("drops queued requests when the session is cancelled", function()
      local prompts = {}
      local client, sent = new_client({
        on_request_permission = function(_, _, answer) table.insert(prompts, answer) end,
      })
      client:_handle_request_permission(30, permission_params)
      client:_handle_request_permission(31, permission_params)
      assert.equals(1, #prompts)

      client:cancel_session("s1")
      -- both requests answered with cancelled, then session/cancel
      assert.equals(3, #sent)
      assert.equals(30, sent[1].id)
      assert.equals("cancelled", sent[1].result.outcome.outcome)
      assert.equals(31, sent[2].id)
      assert.equals("cancelled", sent[2].result.outcome.outcome)
      assert.equals("session/cancel", sent[3].method)
      assert.equals(0, #client.permission_queue)
      assert.is_nil(client.active_permission_id)

      -- the prompt still on screen answers late: nothing more is sent, no second prompt appears
      prompts[1]("allow")
      assert.equals(3, #sent)
      assert.equals(1, #prompts)
    end)

    it("answers cancelled when the permission handler throws", function()
      local client, sent = new_client({
        on_request_permission = function() error("boom") end,
      })
      local error_stub = stub(require("avante.utils"), "error")
      client:_handle_request_permission(40, permission_params)
      error_stub:revert()
      assert.equals(1, #sent)
      assert.equals(40, sent[1].id)
      assert.equals("cancelled", sent[1].result.outcome.outcome)
    end)

    it("rejects malformed permission requests instead of leaving them unanswered", function()
      local client, sent = new_client({ on_request_permission = function() end })
      client:_handle_request_permission(50, { sessionId = "s1" })
      assert.equals(1, #sent)
      assert.equals(50, sent[1].id)
      assert.equals(ACPClient.ERROR_CODES.INVALID_PARAMS, sent[1].error.code)
    end)
  end)

  describe("fs handlers", function()
    it("reports a failed write as a JSON-RPC error", function()
      local client, sent = new_client({
        on_write_file = function(_, _, callback) callback("disk full") end,
      })
      client:_handle_write_text_file(60, { sessionId = "s1", path = "/x", content = "y" })
      assert.equals(1, #sent)
      assert.is_nil(sent[1].result)
      assert.equals("disk full", sent[1].error.message)
      assert.equals(ACPClient.ERROR_CODES.INTERNAL_ERROR, sent[1].error.code)
    end)

    it("answers with null on a successful write", function()
      local client, sent = new_client({
        on_write_file = function(_, _, callback) callback(nil) end,
      })
      client:_handle_write_text_file(61, { sessionId = "s1", path = "/x", content = "y" })
      assert.equals(1, #sent)
      assert.equals(vim.NIL, sent[1].result)
      assert.is_nil(sent[1].error)
    end)

    it("turns an exception in the write handler into an error response", function()
      local client, sent = new_client({
        on_write_file = function() error("E37: No write since last change") end,
      })
      client:_handle_write_text_file(62, { sessionId = "s1", path = "/x", content = "y" })
      assert.equals(1, #sent)
      assert.equals(62, sent[1].id)
      assert.truthy(sent[1].error.message:find("E37", 1, true))
    end)

    it("turns an exception in the read handler into an error response", function()
      local client, sent = new_client({
        on_read_file = function() error("kaboom") end,
      })
      client:_handle_read_text_file(63, { sessionId = "s1", path = "/x" })
      assert.equals(1, #sent)
      assert.equals(63, sent[1].id)
      assert.truthy(sent[1].error.message:find("kaboom", 1, true))
    end)
  end)

  describe("disconnected transport", function()
    it("fails a request immediately when the agent's stdin is closed", function()
      local client = ACPClient:new({ transport_type = "stdio", handlers = {} })
      client.transport = { send = function() return false end, start = function() end, stop = function() end }
      local got
      client:_send_request("session/prompt", { sessionId = "s1" }, function(_, err) got = err end)
      assert.is_not_nil(got)
      assert.equals(ACPClient.ERROR_CODES.PROTOCOL_ERROR, got.code)
      assert.is_nil(next(client.callbacks))
    end)

    it("describes an agent that died mid-session including its stderr", function()
      local client = ACPClient:new({ transport_type = "stdio", command = "claude-agent-acp", args = {}, handlers = {} })
      client:_record_stderr("TypeError: cannot read properties of undefined\n")
      local msg = client:_format_unexpected_exit(1, 0)
      assert.truthy(msg:find("exited unexpectedly", 1, true))
      assert.truthy(msg:find("TypeError", 1, true))
    end)
  end)
end)

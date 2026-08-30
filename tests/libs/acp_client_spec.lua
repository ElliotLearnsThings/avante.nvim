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
end)

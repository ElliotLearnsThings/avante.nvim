---@mod avante-acp Agent Client Protocol support
---
---@brief [[
---
---Avante.nvim now supports the Agent Client Protocol (ACP) (https://agentclientprotocol.com/overview/introduction), enabling seamless integration with AI agents that follow this standardized communication protocol.
---
---What is ACP?
---
---(ACP) is a standardized protocol that enables AI agents to communicate with development tools and environments. It provides:
---
---- **Standardized Communication**: A unified JSON-RPC based protocol for agent-client interactions
---- **Tool Integration**: Support for various development tools like file operations, code execution, and search
---- **Session Management**: Persistent sessions that maintain context across interactions
---- **Permission System**: Granular control over what agents can access and modify
---
--- Supported ACP agents include:
---
--- - Gemini CLI
--- - Claude Code
--- - Goose
--- - Codex
--- - Kimi CLI
---Before using ACP agents, ensure you have the required tools installed:
---
---- **For Gemini CLI**: Install the `gemini` CLI tool and set your `GEMINI_API_KEY`
---- **For Claude Code**: Install the `claude` CLI and the `claude-agent-acp` shim (`npm i -g @agentclientprotocol/claude-agent-acp`; the old `@zed-industries` package is deprecated); either log in with `claude auth login` or set `ANTHROPIC_API_KEY`
---
---Permission mode (Claude Code)
---
---`@agentclientprotocol/claude-agent-acp` takes its initial permission mode from Claude Code's own settings
---(`permissions.defaultMode` in `~/.claude/settings.json` or the project's `.claude/settings*.json`), not from
---the environment. Accepted values are `default`, `acceptEdits`, `dontAsk`, `plan`, `auto` and `bypassPermissions`
---(alias `bypass`); `auto` falls back to `acceptEdits` for models without auto-mode support. The deprecated
---`@zed-industries/claude-agent-acp` (frozen at 0.23.1) does not know `auto` and fails `session/new` with
---"Invalid permissions.defaultMode: auto": upgrade the shim, or override the mode for the project in
---`.claude/settings.local.json` (`{ "permissions": { "defaultMode": "default" } }`).
---With `bypassPermissions` the agent never sends `session/request_permission`, so avante's
---inline permission buttons never appear; use `default` (and `behaviour.auto_approve_tool_permissions = false`)
---to be asked, or switch the mode at runtime with `:AvanteACPModes` / `<leader>am`.
---The binary is located via `CLAUDE_CODE_EXECUTABLE`; `CLAUDE_CONFIG_DIR` and `MAX_THINKING_TOKENS` are also honoured.
---
---ACP vs Traditional Providers
---
---ACP providers offer several advantages over traditional API-based providers:
---
---- **Enhanced Tool Access**: Agents can directly interact with your file system, run commands, and access development tools
---- **Persistent Context**: Sessions maintain state across multiple interactions
---- **Fine-grained Permissions**: Control exactly what agents can access and modify
---- **Standardized Protocol**: Compatible with any ACP-compliant agent
---@brief ]]
---@see avante-config
local Config = require("avante.config")
local Utils = require("avante.utils")

---@class avante.acp.ClientCapabilities
---@field fs avante.acp.FileSystemCapability
---@field terminal boolean
---@field _meta table<string, any>|nil

---@class avante.acp.FileSystemCapability
---@field readTextFile boolean
---@field writeTextFile boolean

---@class avante.acp.AgentCapabilities
---@field loadSession boolean
---@field promptCapabilities avante.acp.PromptCapabilities

---@class avante.acp.PromptCapabilities
---@field image boolean
---@field audio boolean
---@field embeddedContext boolean

---@class avante.acp.AuthMethod
---@field id string
---@field name string
---@field description string|nil

---@class avante.acp.McpServer
---@field name string
---@field command string
---@field args string[]
---@field env avante.acp.EnvVariable[]

---@class avante.acp.EnvVariable
---@field name string
---@field value string

---@alias ACPStopReason "end_turn" | "max_tokens" | "max_turn_requests" | "refusal" | "cancelled"

---@alias ACPToolKind "read" | "edit" | "delete" | "move" | "search" | "execute" | "think" | "fetch" | "other"

---@alias ACPToolCallStatus "pending" | "in_progress" | "completed" | "failed"

---@alias ACPPlanEntryStatus "pending" | "in_progress" | "completed"

---@alias ACPPlanEntryPriority "high" | "medium" | "low"

---@class avante.acp.BaseContent
---@field type "text" | "image" | "audio" | "resource_link" | "resource"
---@field annotations avante.acp.Annotations|nil

---@class avante.acp.TextContent : avante.acp.BaseContent
---@field type "text"
---@field text string

---@class avante.acp.ImageContent : avante.acp.BaseContent
---@field type "image"
---@field data string
---@field mimeType string
---@field uri string|nil

---@class avante.acp.AudioContent : avante.acp.BaseContent
---@field type "audio"
---@field data string
---@field mimeType string

---@class avante.acp.ResourceLinkContent : avante.acp.BaseContent
---@field type "resource_link"
---@field uri string
---@field name string
---@field description string|nil
---@field mimeType string|nil
---@field size number|nil
---@field title string|nil

---@class avante.acp.ResourceContent : avante.acp.BaseContent
---@field type "resource"
---@field resource avante.acp.EmbeddedResource

---@class avante.acp.EmbeddedResource
---@field uri string
---@field text string|nil
---@field blob string|nil
---@field mimeType string|nil

---@class avante.acp.Annotations
---@field audience any[]|nil
---@field lastModified string|nil
---@field priority number|nil

---@alias ACPContent avante.acp.TextContent | avante.acp.ImageContent | avante.acp.AudioContent | avante.acp.ResourceLinkContent | avante.acp.ResourceContent

---@class avante.acp.ToolCall
---@field toolCallId string
---@field title string
---@field kind ACPToolKind
---@field status ACPToolCallStatus
---@field content ACPToolCallContent[]
---@field locations avante.acp.ToolCallLocation[]
---@field rawInput table
---@field rawOutput table

---@class avante.acp.BaseToolCallContent
---@field type "content" | "diff" | "terminal"

---@class avante.acp.ToolCallRegularContent : avante.acp.BaseToolCallContent
---@field type "content"
---@field content ACPContent

---@class avante.acp.ToolCallDiffContent : avante.acp.BaseToolCallContent
---@field type "diff"
---@field path string
---@field oldText string|nil
---@field newText string

---@class avante.acp.ToolCallTerminalContent : avante.acp.BaseToolCallContent
---@field type "terminal"
---@field terminalId string

---@alias ACPToolCallContent avante.acp.ToolCallRegularContent | avante.acp.ToolCallDiffContent | avante.acp.ToolCallTerminalContent

---@class avante.acp.TerminalExitStatus
---@field exitCode integer|nil
---@field signal string|nil

---@class avante.acp.Terminal
---@field id string
---@field session_id string|nil
---@field command string
---@field args string[]
---@field cwd string|nil
---@field output string Collected output (stdout + stderr), truncated from the beginning to byte_limit
---@field byte_limit integer|nil
---@field truncated boolean
---@field exit_status avante.acp.TerminalExitStatus|nil
---@field released boolean
---@field virtual boolean True when output is fed by the agent (via `_meta`) instead of a spawned process
---@field waiters fun(exit_status: avante.acp.TerminalExitStatus)[]
---@field handle uv.uv_process_t|nil
---@field pid integer|nil
---@field stdout uv.uv_pipe_t|nil
---@field stderr uv.uv_pipe_t|nil

---@class avante.acp.ToolCallLocation
---@field path string
---@field line number|nil

---@class avante.acp.PlanEntry
---@field content string
---@field priority ACPPlanEntryPriority
---@field status ACPPlanEntryStatus

---@class avante.acp.Plan
---@field entries avante.acp.PlanEntry[]

---@class avante.acp.ConfigOptionValue
---@field value string
---@field name string
---@field description string|nil

---@class avante.acp.ConfigOption
---@field id string
---@field name string
---@field description string|nil
---@field category string|nil
---@field type string
---@field currentValue string
---@field options avante.acp.ConfigOptionValue[]

---@class avante.acp.ConfigOptionUpdate : avante.acp.BaseSessionUpdate
---@field sessionUpdate "config_option_update"
---@field configOptions avante.acp.ConfigOption[]

---@class avante.acp.AvailableCommand
---@field name string
---@field description string
---@field input? table<string, any>

---@class avante.acp.BaseSessionUpdate
---@field sessionUpdate "user_message_chunk" | "agent_message_chunk" | "agent_thought_chunk" | "tool_call" | "tool_call_update" | "plan" | "available_commands_update" | "config_option_update" | "current_mode_update"

---@class avante.acp.UserMessageChunk : avante.acp.BaseSessionUpdate
---@field sessionUpdate "user_message_chunk"
---@field content ACPContent

---@class avante.acp.AgentMessageChunk : avante.acp.BaseSessionUpdate
---@field sessionUpdate "agent_message_chunk"
---@field content ACPContent

---@class avante.acp.AgentThoughtChunk : avante.acp.BaseSessionUpdate
---@field sessionUpdate "agent_thought_chunk"
---@field content ACPContent

---@class avante.acp.ToolCallUpdate : avante.acp.BaseSessionUpdate
---@field sessionUpdate "tool_call" | "tool_call_update"
---@field toolCallId string
---@field title string|nil
---@field kind ACPToolKind|nil
---@field status ACPToolCallStatus|nil
---@field content ACPToolCallContent[]|nil
---@field locations avante.acp.ToolCallLocation[]|nil
---@field rawInput table|nil
---@field rawOutput table|nil

---@class avante.acp.PlanUpdate : avante.acp.BaseSessionUpdate
---@field sessionUpdate "plan"
---@field entries avante.acp.PlanEntry[]

---@class avante.acp.AvailableCommandsUpdate : avante.acp.BaseSessionUpdate
---@field sessionUpdate "available_commands_update"
---@field availableCommands avante.acp.AvailableCommand[]

---@class avante.acp.CurrentModeUpdate : avante.acp.BaseSessionUpdate
---@field sessionUpdate "current_mode_update"
---@field currentModeId string
---@field modeId string legacy alias, normalized by the client

---@class avante.acp.PermissionOption
---@field optionId string
---@field name string
---@field kind "allow_once" | "allow_always" | "reject_once" | "reject_always"

---@class avante.acp.RequestPermissionOutcome
---@field outcome "cancelled" | "selected"
---@field optionId string|nil

---@class avante.acp.ACPTransport
---@field send function
---@field start function
---@field stop function

---@alias ACPConnectionState "disconnected" | "connecting" | "connected" | "initializing" | "ready" | "error"

---@class avante.acp.ACPError
---@field code number
---@field message string
---@field data any|nil

---@class avante.acp.ACPClient
---@field protocol_version number
---@field capabilities avante.acp.ClientCapabilities
---@field agent_capabilities avante.acp.AgentCapabilities|nil
---@field prompt_capabilities avante.acp.PromptCapabilities|nil
---@field config_options avante.acp.ConfigOption[]|nil
---@field _legacy_api boolean|nil Whether agent uses old modes/models API instead of configOptions
---@field config ACPConfig
---@field callbacks table<number, fun(result: table|nil, err: avante.acp.ACPError|nil)>
---@field pending_permissions table<number, boolean> ids of unanswered session/request_permission requests
---@field permission_queue { id: number, tool_call: table, options: table[] }[] permission requests waiting to be shown
---@field active_permission_id number|nil id of the permission request currently shown to the user
---@field active_session_ids table<string, boolean> sessions created/loaded on this connection
---@field fresh_session_ids table<string, boolean> sessions created on this connection that have not been prompted yet
---@field stderr_lines string[] last lines received on the agent's stderr
---@field terminals table<string, avante.acp.Terminal>
---@field terminal_counter integer
---@field debug_log_file file*|nil
local ACPClient = {}

-- ACP Error codes
ACPClient.ERROR_CODES = {
  -- JSON-RPC 2.0
  PARSE_ERROR = -32700,
  INVALID_REQUEST = -32600,
  METHOD_NOT_FOUND = -32601,
  INVALID_PARAMS = -32602,
  INTERNAL_ERROR = -32603,
  -- ACP
  AUTH_REQUIRED = -32000,
  RESOURCE_NOT_FOUND = -32002,
  -- Client-side (implementation defined, -32000..-32099 range)
  PROTOCOL_ERROR = -32010,
  TIMEOUT_ERROR = -32011,
}

-- Number of trailing stderr lines kept for error diagnostics
ACPClient.STDERR_TAIL_LINES = 20

local LOG_SEPARATOR = string.rep("=", 80) .. "\n"

---@class ACPHandlers
---@field on_session_update? fun(update: avante.acp.UserMessageChunk | avante.acp.AgentMessageChunk | avante.acp.AgentThoughtChunk | avante.acp.ToolCallUpdate | avante.acp.PlanUpdate | avante.acp.AvailableCommandsUpdate | avante.acp.CurrentModeUpdate | avante.acp.ConfigOptionUpdate)
---@field on_request_permission? fun(tool_call: table, options: table[], callback: fun(option_id: string | nil)): nil
---@field on_read_file? fun(path: string, line: integer | nil, limit: integer | nil, callback: fun(content: string), error_callback: fun(message: string, code: integer|nil)): nil
---@field on_write_file? fun(path: string, content: string, callback: fun(error: string|nil)): nil
---@field on_terminal_update? fun(terminal: avante.acp.Terminal): nil Called whenever terminal output or exit status changes
---@field on_error? fun(error: table)
---@field on_auth_status_update? fun(status: table|nil) claude-agent-acp `_auth/status_update` payload

---@class ACPConfig
---@field transport_type "stdio" | "websocket" | "tcp"
---@field command? string Command to spawn agent (for stdio)
---@field args string[] Arguments for agent command
---@field env? table Environment variables
---@field host? string Host for tcp/websocket
---@field port? number Port for tcp/websocket
---@field timeout? number Request timeout in milliseconds
---@field reconnect? boolean Enable auto-reconnect
---@field max_reconnect_attempts? number Maximum reconnection attempts
---@field heartbeat_interval? number Heartbeat interval in milliseconds
---@field auth_method? string Authentication method
---@field handlers? ACPHandlers
---@field on_state_change? fun(new_state: ACPConnectionState, old_state: ACPConnectionState)

---Create a new ACP client instance
---@param config ACPConfig
---@return avante.acp.ACPClient
function ACPClient:new(config)
  local client = setmetatable({
    id_counter = 0,
    protocol_version = 1,
    capabilities = {
      fs = {
        readTextFile = true,
        writeTextFile = true,
      },
      terminal = true,
      -- claude-agent-acp runs Bash itself and streams the terminal output
      -- through `_meta.terminal_output` / `_meta.terminal_exit` on tool call
      -- updates when this non-standard capability is advertised.
      _meta = {
        terminal_output = true,
      },
    },
    debug_log_file = nil,
    callbacks = {},
    pending_permissions = {},
    -- session/request_permission requests are shown to the user one at a
    -- time; the rest wait here in arrival order (see _dispatch_next_permission).
    permission_queue = {},
    active_permission_id = nil,
    stderr_lines = {},
    terminals = {},
    terminal_counter = 0,
    transport = nil,
    config = config or {},
    config_options = nil,
    state = "disconnected",
    reconnect_count = 0,
    heartbeat_timer = nil,
    -- Session IDs that have been created/loaded on this agent process.
    -- The agent only knows about sessions established over this connection,
    -- so a persisted session id must go through session/load before prompting.
    active_session_ids = {},
    -- Sessions created (not loaded) on this connection whose first prompt
    -- has not been sent yet; llm.lua hands such a session the chat context.
    fresh_session_ids = {},
  }, { __index = self })

  client:_setup_transport()
  return client
end

---Write debug log message
---@param message string
function ACPClient:_debug_log(message)
  if not Config.debug then
    self:_close_debug_log()
    return
  end

  -- Open file if needed
  if not self.debug_log_file then
    self.debug_log_file = io.open(vim.fs.joinpath(vim.fn.stdpath("log"), "avante-acp-session.log"), "a")
  end

  if self.debug_log_file then
    self.debug_log_file:write(message)
    self.debug_log_file:flush()
  end
end

---Close debug log file
function ACPClient:_close_debug_log()
  if self.debug_log_file then
    self.debug_log_file:close()
    self.debug_log_file = nil
  end
end

---Setup transport layer
function ACPClient:_setup_transport()
  local transport_type = self.config.transport_type or "stdio"

  if transport_type == "stdio" then
    self.transport = self:_create_stdio_transport()
  elseif transport_type == "websocket" then
    self.transport = self:_create_websocket_transport()
  elseif transport_type == "tcp" then
    self.transport = self:_create_tcp_transport()
  else
    error("Unsupported transport type: " .. transport_type)
  end
end

---Set connection state
---@param state ACPConnectionState
function ACPClient:_set_state(state)
  local old_state = self.state
  self.state = state

  if self.config.on_state_change then self.config.on_state_change(state, old_state) end
end

---Create error object
---@param code number
---@param message string
---@param data any?
---@return avante.acp.ACPError
function ACPClient:_create_error(code, message, data)
  return {
    code = code,
    message = message,
    data = data,
  }
end

---Record agent stderr output (tail buffer + debug log)
---@param data string
function ACPClient:_record_stderr(data)
  for _, line in ipairs(vim.split(data, "\n", { plain = true, trimempty = true })) do
    table.insert(self.stderr_lines, line)
    while #self.stderr_lines > ACPClient.STDERR_TAIL_LINES do
      table.remove(self.stderr_lines, 1)
    end
  end
  vim.schedule(function()
    Utils.debug("ACP stderr:", data)
    self:_debug_log("stderr: " .. data .. (data:sub(-1) == "\n" and "" or "\n"))
  end)
end

---Build a human readable message for an agent process that died before becoming ready
---@param code integer
---@param signal integer
---@return string
function ACPClient:_format_spawn_failure(code, signal)
  local cmd = table.concat({ self.config.command or "?", unpack(self.config.args or {}) }, " ")
  local msg = string.format("ACP agent [%s] exited with code %d (signal %d) before becoming ready", cmd, code, signal)
  if #self.stderr_lines > 0 then msg = msg .. "\nstderr:\n" .. table.concat(self.stderr_lines, "\n") end
  return msg
end

---Build a human readable message for an agent process that died mid-session
---@param code integer
---@param signal integer
---@return string
function ACPClient:_format_unexpected_exit(code, signal)
  local cmd = table.concat({ self.config.command or "?", unpack(self.config.args or {}) }, " ")
  local msg = string.format("ACP agent [%s] exited unexpectedly with code %d (signal %d)", cmd, code, signal)
  if #self.stderr_lines > 0 then msg = msg .. "\nstderr:\n" .. table.concat(self.stderr_lines, "\n") end
  return msg
end

---Fail every outstanding request callback with the given error
---@param err avante.acp.ACPError
function ACPClient:_fail_pending_callbacks(err)
  local callbacks = self.callbacks
  self.callbacks = {}
  for _, callback in pairs(callbacks) do
    pcall(callback, nil, err)
  end
end

---Create stdio transport layer
---Build the environment for the agent process: Neovim's own environment with
---the provider's `env` table layered on top.
---
---The agent must inherit the full environment (HOME, XDG_*, SSH_AUTH_SOCK,
---proxy settings, ...). Claude Code, for one, locates its login and settings
---through HOME; spawned with only PATH it reports "Not logged in" and every
---prompt fails with `authRequired`.
---@param config_env table<string, any>|nil provider `env` (nil values are skipped)
---@param base_env table<string, string>|nil defaults to `vim.fn.environ()`
---@return string[] `KEY=VALUE` entries for `uv.spawn`
function ACPClient.build_spawn_env(config_env, base_env)
  local merged = vim.deepcopy(base_env or vim.fn.environ())
  if type(config_env) == "table" then
    for k, v in pairs(config_env) do
      if v ~= nil and v ~= vim.NIL then merged[k] = tostring(v) end
    end
  end
  local keys = vim.tbl_keys(merged)
  table.sort(keys)
  local result = {}
  for _, k in ipairs(keys) do
    result[#result + 1] = k .. "=" .. tostring(merged[k])
  end
  return result
end

function ACPClient:_create_stdio_transport()
  local uv = vim.uv or vim.loop

  --- @class avante.acp.ACPTransportInstance
  local transport = {
    --- @type uv.uv_pipe_t|nil
    stdin = nil,
    --- @type uv.uv_pipe_t|nil
    stdout = nil,
    --- @type uv.uv_process_t|nil
    process = nil,
  }

  --- @param transport_self avante.acp.ACPTransportInstance
  --- @param data string
  function transport.send(transport_self, data)
    if transport_self.stdin and not transport_self.stdin:is_closing() then
      transport_self.stdin:write(data .. "\n")
      return true
    end
    return false
  end

  --- @param transport_self avante.acp.ACPTransportInstance
  --- @param on_message fun(message: any)
  function transport.start(transport_self, on_message)
    self:_set_state("connecting")

    local stdin = uv.new_pipe(false)
    local stdout = uv.new_pipe(false)
    local stderr = uv.new_pipe(false)

    if not stdin or not stdout or not stderr then
      self:_set_state("error")
      error("Failed to create pipes for ACP agent")
    end

    local args = vim.deepcopy(self.config.args)
    local final_env = ACPClient.build_spawn_env(self.config.env)

    ---@diagnostic disable-next-line: missing-fields
    local handle, pid = uv.spawn(self.config.command, {
      args = args,
      env = final_env,
      stdio = { stdin, stdout, stderr },
    }, function(code, signal)
      Utils.debug("ACP agent exited with code " .. code .. " and signal " .. signal)
      local was_ready = self.state == "ready"
      local stopping = self._stopping == true
      self._stopping = nil
      self:_set_state("disconnected")

      -- Any request still waiting for an answer (typically the in-flight
      -- session/prompt) will never be answered by this process. Fail it so the
      -- caller's on_stop runs and the sidebar does not stay "generating" forever.
      local has_pending = next(self.callbacks) ~= nil
      if (code ~= 0 and not was_ready) or has_pending then
        local message
        if stopping then
          message = "ACP agent stopped"
        elseif was_ready then
          message = self:_format_unexpected_exit(code, signal)
        else
          message = self:_format_spawn_failure(code, signal)
        end
        local err = self:_create_error(
          self.ERROR_CODES.PROTOCOL_ERROR,
          message,
          { code = code, signal = signal, stderr = vim.deepcopy(self.stderr_lines) }
        )
        vim.schedule(function()
          if not stopping then vim.notify(err.message, vim.log.levels.ERROR, { title = "Avante ACP" }) end
          self:_fail_pending_callbacks(err)
        end)
      end

      -- Permission prompts and terminals belonging to the dead process are moot.
      self.pending_permissions = {}
      self.permission_queue = {}
      self.active_permission_id = nil
      self:kill_all_terminals()

      if transport_self.process then
        transport_self.process:close()
        transport_self.process = nil
      end

      -- The agent process is gone, so every session it knew about must be
      -- re-created / re-loaded on the next connection.
      self.active_session_ids = {}

      -- Handle auto-reconnect
      if self.config.reconnect and self.reconnect_count < (self.config.max_reconnect_attempts or 3) then
        self.reconnect_count = self.reconnect_count + 1
        vim.defer_fn(function()
          if self.state == "disconnected" then self:connect(function(_err) end) end
        end, 2000) -- Wait 2 seconds before reconnecting
      end
    end)

    Utils.debug("Spawned ACP agent process with PID " .. tostring(pid))

    if not handle then
      self:_set_state("error")
      error("Failed to spawn ACP agent process [" .. table.concat({ self.config.command, unpack(args) }, " ") .. "]")
    end

    transport_self.process = handle
    transport_self.stdin = stdin
    transport_self.stdout = stdout

    self:_set_state("connected")

    -- Read stdout
    local buffer = ""
    stdout:read_start(function(err, data)
      if err then
        vim.notify("ACP stdout error: " .. err, vim.log.levels.ERROR)
        self:_set_state("error")
        return
      end

      if data then
        buffer = buffer .. data

        -- Split on newlines and process complete JSON-RPC messages
        local lines = vim.split(buffer, "\n", { plain = true })
        buffer = lines[#lines] -- Keep incomplete line in buffer

        for i = 1, #lines - 1 do
          local line = vim.trim(lines[i])
          if line ~= "" then
            local ok, message = pcall(vim.json.decode, line)
            if ok then
              on_message(message)
            else
              vim.schedule(
                function() vim.notify("Failed to parse JSON-RPC message: " .. line, vim.log.levels.WARN) end
              )
            end
          end
        end
      end
    end)

    -- Read stderr: keep a tail for diagnostics and write it to the debug log
    stderr:read_start(function(_, data)
      if data then self:_record_stderr(data) end
    end)
  end

  --- @param transport_self avante.acp.ACPTransportInstance
  function transport.stop(transport_self)
    if transport_self.process and not transport_self.process:is_closing() then
      local process = transport_self.process
      transport_self.process = nil

      if not process then return end

      -- Try to terminate gracefully
      pcall(function() process:kill(15) end)
      -- then force kill, it'll fail harmlessly if already exited
      pcall(function() process:kill(9) end)
      process:close()
    end
    if transport_self.stdin then
      transport_self.stdin:close()
      transport_self.stdin = nil
    end
    if transport_self.stdout then
      transport_self.stdout:close()
      transport_self.stdout = nil
    end
    self:_set_state("disconnected")
  end

  return transport
end

---Create WebSocket transport layer (placeholder)
function ACPClient:_create_websocket_transport() error("WebSocket transport not implemented yet") end

---Create TCP transport layer (placeholder)
function ACPClient:_create_tcp_transport() error("TCP transport not implemented yet") end

---Generate next request ID
---@return number
function ACPClient:_next_id()
  self.id_counter = self.id_counter + 1
  return self.id_counter
end

---Send JSON-RPC request
---@param method string
---@param params table?
---@param callback fun(result: table|nil, err: avante.acp.ACPError|nil)
function ACPClient:_send_request(method, params, callback)
  local id = self:_next_id()
  local message = {
    jsonrpc = "2.0",
    id = id,
    method = method,
    params = params or {},
  }

  self.callbacks[id] = callback

  local data = vim.json.encode(message)
  self:_debug_log("request: " .. data .. "\n" .. LOG_SEPARATOR)
  local sent = self.transport and self.transport:send(data)
  if sent == false then
    -- The agent process is gone (stdin closed); nothing will ever answer this
    -- request, so fail it right away instead of leaving the caller hanging.
    self.callbacks[id] = nil
    local err = self:_create_error(
      self.ERROR_CODES.PROTOCOL_ERROR,
      "ACP agent is not connected; could not send " .. method,
      { method = method }
    )
    vim.schedule(function() callback(nil, err) end)
  end
end

---Send JSON-RPC notification
---@param method string
---@param params table?
function ACPClient:_send_notification(method, params)
  local message = {
    jsonrpc = "2.0",
    method = method,
    params = params or {},
  }

  local data = vim.json.encode(message)
  self:_debug_log("notification: " .. data .. string.rep("=", 100) .. "\n")
  self.transport:send(data)
end

---Send JSON-RPC result
---@param id number
---@param result table | string | vim.NIL | nil
---@return nil
function ACPClient:_send_result(id, result)
  local message = { jsonrpc = "2.0", id = id, result = result }

  local data = vim.json.encode(message)
  self:_debug_log("request: " .. data .. "\n" .. string.rep("=", 100) .. "\n")
  self.transport:send(data)
end

---Send JSON-RPC error
---@param id number
---@param message string
---@param code? number
---@return nil
function ACPClient:_send_error(id, message, code)
  code = code or self.ERROR_CODES.INTERNAL_ERROR
  local msg = { jsonrpc = "2.0", id = id, error = { code = code, message = message } }

  local data = vim.json.encode(msg)
  self.transport:send(data)
end

---Handle received message
---@param message table
function ACPClient:_handle_message(message)
  -- Check if this is a notification (has method but no id, or has both method and id for notifications)
  if message.method and not message.result and not message.error then
    -- This is a notification
    self:_handle_notification(message.id, message.method, message.params)
  elseif message.id and (message.result or message.error) then
    self:_debug_log("response: " .. vim.inspect(message) .. "\n" .. string.rep("=", 100) .. "\n")
    local callback = self.callbacks[message.id]
    if callback then
      callback(message.result, message.error)
      self.callbacks[message.id] = nil
    end
  else
    -- Unknown message type
    vim.notify("Unknown message type: " .. vim.inspect(message), vim.log.levels.WARN)
  end
end

---Handle notification
---@param method string
---@param params table
function ACPClient:_handle_notification(message_id, method, params)
  self:_debug_log("method: " .. method .. "\n")
  self:_debug_log(vim.inspect(params) .. "\n" .. string.rep("=", 100) .. "\n")
  if method == "session/update" then
    self:_handle_session_update(params)
  elseif method == "session/request_permission" then
    self:_handle_request_permission(message_id, params)
  elseif method == "fs/read_text_file" then
    self:_handle_read_text_file(message_id, params)
  elseif method == "fs/write_text_file" then
    self:_handle_write_text_file(message_id, params)
  elseif method == "terminal/create" then
    self:_handle_terminal_create(message_id, params)
  elseif method == "terminal/output" then
    self:_handle_terminal_output(message_id, params)
  elseif method == "terminal/wait_for_exit" then
    self:_handle_terminal_wait_for_exit(message_id, params)
  elseif method == "terminal/kill" then
    self:_handle_terminal_kill(message_id, params)
  elseif method == "terminal/release" then
    self:_handle_terminal_release(message_id, params)
  elseif method == "_auth/status_update" then
    -- claude-agent-acp extension: which identity the agent process runs as
    -- ({ kind = "account"|"api_key"|"gateway"|"external"|"none", label = ..., account = {...} }).
    -- Push-only and connection-scoped; kept for the UI and for /login hints.
    self.auth_status = type(params) == "table" and params.authStatus or nil
    local handler = self.config.handlers and self.config.handlers.on_auth_status_update
    if handler then handler(self.auth_status) end
  else
    vim.notify("Unknown notification method: " .. method, vim.log.levels.WARN)
  end
end

---Handle session update notification
---@param params table
function ACPClient:_handle_session_update(params)
  local session_id = params.sessionId
  local update = params.update

  if not session_id then
    vim.notify("Received session/update without sessionId", vim.log.levels.WARN)
    return
  end

  if not update then
    vim.notify("Received session/update without update data", vim.log.levels.WARN)
    return
  end

  if update.sessionUpdate == "config_option_update" and update.configOptions then
    self.config_options = update.configOptions
  end

  -- Handle current_mode_update notification.
  -- The ACP spec (and claude-agent-acp) use `currentModeId`; older agents
  -- used `modeId`. Accept both and normalize so downstream handlers see both.
  if update.sessionUpdate == "current_mode_update" then
    local mode_id = update.currentModeId or update.modeId
    if mode_id then
      update.currentModeId = mode_id
      update.modeId = mode_id
      if self.config_options then
        for _, opt in ipairs(self.config_options) do
          if opt.id == "mode" and opt.category == "mode" then
            opt.currentValue = mode_id
            break
          end
        end
      end
    end
  end

  if self.config.handlers and self.config.handlers.on_session_update then
    vim.schedule(function() self.config.handlers.on_session_update(update) end)
  end
end

---Handle permission request notification
---@param message_id number
---@param params table
function ACPClient:_handle_request_permission(message_id, params)
  local session_id = params.sessionId
  local tool_call = params.toolCall
  local options = params.options

  if not session_id or not tool_call then
    -- Never leave a request unanswered: the agent would wait forever.
    self:_send_error(message_id, "Invalid session/request_permission params", ACPClient.ERROR_CODES.INVALID_PARAMS)
    return
  end

  if not (self.config.handlers and self.config.handlers.on_request_permission) then
    self:_send_error(
      message_id,
      "session/request_permission handler not configured",
      ACPClient.ERROR_CODES.METHOD_NOT_FOUND
    )
    return
  end

  self.pending_permissions[message_id] = true
  table.insert(self.permission_queue, { id = message_id, tool_call = tool_call, options = options or {} })
  self:_dispatch_next_permission()
end

---Show the next queued session/request_permission to the user.
---
---Agents such as Claude Code issue several tool calls in parallel (e.g. one
---Edit per paragraph), each with its own permission request. The confirm UI
---can only display one prompt at a time, so requests are answered strictly
---one after another; a prompt that is replaced before being answered would
---otherwise never be resolved and the whole turn would hang.
function ACPClient:_dispatch_next_permission()
  if self.active_permission_id ~= nil then return end
  local request = table.remove(self.permission_queue, 1)
  -- Skip requests that were resolved (cancelled) while waiting in the queue
  while request and not self.pending_permissions[request.id] do
    request = table.remove(self.permission_queue, 1)
  end
  if not request then return end

  local message_id = request.id
  self.active_permission_id = message_id

  local answered = false
  local function answer(option_id)
    if answered then return end
    answered = true
    local was_pending = self.pending_permissions[message_id] == true
    self.pending_permissions[message_id] = nil
    if self.active_permission_id == message_id then self.active_permission_id = nil end
    -- Late answers for requests already resolved (e.g. by session/cancel) are ignored
    if was_pending then
      if option_id == nil then
        self:_send_result(message_id, { outcome = { outcome = "cancelled" } })
      else
        self:_send_result(message_id, {
          outcome = {
            outcome = "selected",
            optionId = option_id,
          },
        })
      end
    end
    self:_dispatch_next_permission()
  end

  vim.schedule(function()
    local ok, err = pcall(self.config.handlers.on_request_permission, request.tool_call, request.options, answer)
    if not ok then
      Utils.error("ACP permission handler failed: " .. tostring(err), { title = "Avante ACP" })
      answer(nil)
    end
  end)
end

---Answer every unanswered session/request_permission with `outcome = "cancelled"`
---@return integer count number of requests cancelled
function ACPClient:_cancel_pending_permissions()
  local ids = vim.tbl_keys(self.pending_permissions)
  table.sort(ids)
  self.pending_permissions = {}
  self.permission_queue = {}
  self.active_permission_id = nil
  for _, id in ipairs(ids) do
    self:_send_result(id, { outcome = { outcome = "cancelled" } })
  end
  return #ids
end

---Handle fs/read_text_file requests
---@param message_id number
---@param params table
function ACPClient:_handle_read_text_file(message_id, params)
  local session_id = params.sessionId
  local path = params.path

  if not session_id or not path then
    self:_send_error(message_id, "Invalid fs/read_text_file params", ACPClient.ERROR_CODES.INVALID_PARAMS)
    return
  end

  if self.config.handlers and self.config.handlers.on_read_file then
    vim.schedule(function()
      local answered = false
      local ok, err = pcall(
        self.config.handlers.on_read_file,
        path,
        params.line ~= vim.NIL and params.line or nil,
        params.limit ~= vim.NIL and params.limit or nil,
        function(content)
          if answered then return end
          answered = true
          self:_send_result(message_id, { content = content })
        end,
        function(err, code)
          if answered then return end
          answered = true
          self:_send_error(message_id, err or "Failed to read file", code)
        end
      )
      -- A handler that throws must still produce a response or the agent hangs
      if not ok and not answered then
        answered = true
        self:_send_error(message_id, "Failed to read file: " .. tostring(err), ACPClient.ERROR_CODES.INTERNAL_ERROR)
      end
    end)
  else
    self:_send_error(message_id, "fs/read_text_file handler not configured", ACPClient.ERROR_CODES.METHOD_NOT_FOUND)
  end
end

---Handle fs/write_text_file requests
---@param message_id number
---@param params table
function ACPClient:_handle_write_text_file(message_id, params)
  local session_id = params.sessionId
  local path = params.path
  local content = params.content

  if not session_id or not path or not content then
    self:_send_error(message_id, "Invalid fs/write_text_file params", ACPClient.ERROR_CODES.INVALID_PARAMS)
    return
  end

  if self.config.handlers and self.config.handlers.on_write_file then
    vim.schedule(function()
      local answered = false
      local ok, err = pcall(self.config.handlers.on_write_file, path, content, function(error)
        if answered then return end
        answered = true
        if error == nil or error == vim.NIL then
          self:_send_result(message_id, vim.NIL)
        else
          -- A failed write is a JSON-RPC error, not a successful result carrying a string
          self:_send_error(message_id, tostring(error), ACPClient.ERROR_CODES.INTERNAL_ERROR)
        end
      end)
      -- A handler that throws must still produce a response or the agent hangs
      if not ok and not answered then
        answered = true
        self:_send_error(message_id, "Failed to write file: " .. tostring(err), ACPClient.ERROR_CODES.INTERNAL_ERROR)
      end
    end)
  else
    self:_send_error(message_id, "fs/write_text_file handler not configured", ACPClient.ERROR_CODES.METHOD_NOT_FOUND)
  end
end

---------------------------------------------------------------------------
-- Terminals (https://agentclientprotocol.com/protocol/terminals)
---------------------------------------------------------------------------

local SIGNAL_NAMES = {
  [1] = "SIGHUP",
  [2] = "SIGINT",
  [3] = "SIGQUIT",
  [6] = "SIGABRT",
  [9] = "SIGKILL",
  [13] = "SIGPIPE",
  [14] = "SIGALRM",
  [15] = "SIGTERM",
}

---Truncate `output` from the beginning so that it fits in `byte_limit` bytes.
---Truncation happens on a UTF-8 character boundary so the result stays valid.
---@param output string
---@param byte_limit integer|nil
---@return string output
---@return boolean truncated
function ACPClient.truncate_terminal_output(output, byte_limit)
  if not byte_limit or byte_limit <= 0 or #output <= byte_limit then return output, false end
  local start = #output - byte_limit + 1
  -- Skip UTF-8 continuation bytes (10xxxxxx) so we start at a character boundary
  while start <= #output do
    local byte = output:byte(start)
    if byte < 0x80 or byte >= 0xC0 then break end
    start = start + 1
  end
  return output:sub(start), true
end

---Build a spec-shaped snapshot of a terminal (used for terminal/output and UI)
---@param terminal avante.acp.Terminal
---@return { output: string, truncated: boolean, exitStatus: avante.acp.TerminalExitStatus|nil }
function ACPClient.terminal_snapshot(terminal)
  return {
    output = terminal.output,
    truncated = terminal.truncated,
    exitStatus = terminal.exit_status and vim.deepcopy(terminal.exit_status) or nil,
  }
end

---@param terminal avante.acp.Terminal
function ACPClient:_notify_terminal_update(terminal)
  if self.config.handlers and self.config.handlers.on_terminal_update then
    vim.schedule(function() self.config.handlers.on_terminal_update(terminal) end)
  end
end

---Get a terminal by id
---@param terminal_id string
---@return avante.acp.Terminal|nil
function ACPClient:get_terminal(terminal_id) return self.terminals[terminal_id] end

---@class avante.acp.NewTerminalOpts
---@field session_id? string
---@field command? string
---@field args? string[]
---@field cwd? string
---@field byte_limit? integer
---@field virtual? boolean

---Create a terminal record (without spawning anything)
---@param terminal_id string
---@param opts? avante.acp.NewTerminalOpts
---@return avante.acp.Terminal
function ACPClient:_new_terminal(terminal_id, opts)
  opts = opts or {}
  ---@type avante.acp.Terminal
  local terminal = {
    id = terminal_id,
    session_id = opts.session_id,
    command = opts.command or "",
    args = opts.args or {},
    cwd = opts.cwd,
    output = "",
    byte_limit = opts.byte_limit,
    truncated = false,
    exit_status = nil,
    released = false,
    virtual = opts.virtual == true,
    waiters = {},
  }
  self.terminals[terminal_id] = terminal
  return terminal
end

---Append output to a terminal, enforcing the byte limit
---@param terminal avante.acp.Terminal
---@param data string
function ACPClient:_append_terminal_output(terminal, data)
  if data == nil or data == "" then return end
  local output, truncated = ACPClient.truncate_terminal_output(terminal.output .. data, terminal.byte_limit)
  terminal.output = output
  terminal.truncated = terminal.truncated or truncated
  self:_notify_terminal_update(terminal)
end

---Mark a terminal as exited and resolve pending waiters
---@param terminal avante.acp.Terminal
---@param exit_status avante.acp.TerminalExitStatus
function ACPClient:_set_terminal_exit(terminal, exit_status)
  if terminal.exit_status then return end
  terminal.exit_status = exit_status
  local waiters = terminal.waiters
  terminal.waiters = {}
  for _, waiter in ipairs(waiters) do
    waiter(vim.deepcopy(exit_status))
  end
  self:_notify_terminal_update(terminal)
end

---Ensure a "virtual" terminal exists. Used for agents (claude-agent-acp) that
---execute commands themselves and only stream the output to the client.
---@param terminal_id string
---@param session_id string|nil
---@return avante.acp.Terminal
function ACPClient:ensure_virtual_terminal(terminal_id, session_id)
  local terminal = self.terminals[terminal_id]
  if terminal then return terminal end
  return self:_new_terminal(terminal_id, { session_id = session_id, virtual = true })
end

---Feed agent-provided output into a virtual terminal
---@param terminal_id string
---@param data string
---@param session_id string|nil
function ACPClient:push_terminal_output(terminal_id, data, session_id)
  local terminal = self:ensure_virtual_terminal(terminal_id, session_id)
  self:_append_terminal_output(terminal, data)
end

---Feed agent-provided exit status into a virtual terminal
---@param terminal_id string
---@param exit_status avante.acp.TerminalExitStatus
---@param session_id string|nil
function ACPClient:push_terminal_exit(terminal_id, exit_status, session_id)
  local terminal = self:ensure_virtual_terminal(terminal_id, session_id)
  self:_set_terminal_exit(terminal, exit_status)
end

---Spawn the process backing a terminal. Split out so tests can stub it.
---@param terminal avante.acp.Terminal
---@param env table<string, string>|nil
---@return string|nil error
function ACPClient:_spawn_terminal(terminal, env)
  local uv = vim.uv or vim.loop
  local stdout = uv.new_pipe(false)
  local stderr = uv.new_pipe(false)
  if not stdout or not stderr then return "Failed to create pipes for terminal" end

  local final_env = nil
  if env and next(env) ~= nil then
    local merged = vim.fn.environ()
    for k, v in pairs(env) do
      merged[k] = v
    end
    final_env = {}
    for k, v in pairs(merged) do
      final_env[#final_env + 1] = k .. "=" .. v
    end
  end

  local function close_pipes()
    if stdout and not stdout:is_closing() then stdout:close() end
    if stderr and not stderr:is_closing() then stderr:close() end
    terminal.stdout = nil
    terminal.stderr = nil
  end

  ---@diagnostic disable-next-line: missing-fields
  local handle, pid_or_err = uv.spawn(terminal.command, {
    args = terminal.args,
    cwd = terminal.cwd,
    env = final_env,
    stdio = { nil, stdout, stderr },
    hide = true,
  }, function(code, signal)
    if terminal.handle and not terminal.handle:is_closing() then terminal.handle:close() end
    terminal.handle = nil
    close_pipes()
    ---@type avante.acp.TerminalExitStatus
    local exit_status
    if signal and signal ~= 0 then
      exit_status = { exitCode = nil, signal = SIGNAL_NAMES[signal] or ("SIG" .. tostring(signal)) }
    else
      exit_status = { exitCode = code, signal = nil }
    end
    self:_set_terminal_exit(terminal, exit_status)
  end)

  if not handle then
    close_pipes()
    return "Failed to spawn terminal command [" .. terminal.command .. "]: " .. tostring(pid_or_err)
  end

  terminal.handle = handle
  terminal.pid = pid_or_err
  terminal.stdout = stdout
  terminal.stderr = stderr

  local function on_read(err, data)
    if err then return end
    if data then self:_append_terminal_output(terminal, data) end
  end
  stdout:read_start(on_read)
  stderr:read_start(on_read)
  return nil
end

---Kill the process backing a terminal (no-op for virtual/exited terminals)
---@param terminal avante.acp.Terminal
function ACPClient:_kill_terminal(terminal)
  if terminal.exit_status or not terminal.handle then return end
  local handle = terminal.handle
  pcall(function() handle:kill(15) end)
  -- Escalate if the process ignores SIGTERM
  vim.defer_fn(function()
    if not terminal.exit_status and terminal.handle and not terminal.handle:is_closing() then
      pcall(function() terminal.handle:kill(9) end)
    end
  end, 1000)
end

---Kill every terminal (optionally only those belonging to `session_id`).
---Records are kept so the agent can still call terminal/output or terminal/release.
---@param session_id string|nil
function ACPClient:kill_all_terminals(session_id)
  for _, terminal in pairs(self.terminals) do
    if not session_id or terminal.session_id == nil or terminal.session_id == session_id then
      self:_kill_terminal(terminal)
    end
  end
end

---Kill and drop every terminal
function ACPClient:release_all_terminals()
  for id, terminal in pairs(self.terminals) do
    self:_kill_terminal(terminal)
    terminal.released = true
    self.terminals[id] = nil
  end
end

---@param message_id number
---@param params table
---@return avante.acp.Terminal|nil
function ACPClient:_lookup_terminal_for_request(message_id, params, method)
  if not params or not params.sessionId or not params.terminalId then
    self:_send_error(message_id, "Invalid " .. method .. " params", ACPClient.ERROR_CODES.INVALID_PARAMS)
    return nil
  end
  local terminal = self.terminals[params.terminalId]
  if not terminal then
    self:_send_error(
      message_id,
      "Terminal not found: " .. tostring(params.terminalId),
      ACPClient.ERROR_CODES.RESOURCE_NOT_FOUND
    )
    return nil
  end
  return terminal
end

---Handle terminal/create requests
---@param message_id number
---@param params table
function ACPClient:_handle_terminal_create(message_id, params)
  if not params or not params.sessionId or type(params.command) ~= "string" or params.command == "" then
    self:_send_error(message_id, "Invalid terminal/create params", ACPClient.ERROR_CODES.INVALID_PARAMS)
    return
  end

  self.terminal_counter = self.terminal_counter + 1
  local terminal_id = "term-" .. tostring(self.terminal_counter)

  local args = {}
  if type(params.args) == "table" and params.args ~= vim.NIL then
    for _, arg in ipairs(params.args) do
      table.insert(args, tostring(arg))
    end
  end

  local env = {}
  if type(params.env) == "table" and params.env ~= vim.NIL then
    for _, entry in ipairs(params.env) do
      if type(entry) == "table" and entry.name then env[entry.name] = tostring(entry.value or "") end
    end
  end

  local cwd = params.cwd
  if cwd == vim.NIL or cwd == "" then cwd = nil end
  local byte_limit = params.outputByteLimit
  if byte_limit == vim.NIL or type(byte_limit) ~= "number" then byte_limit = nil end

  local terminal = self:_new_terminal(terminal_id, {
    session_id = params.sessionId,
    command = params.command,
    args = args,
    cwd = cwd,
    byte_limit = byte_limit,
  })

  local err = self:_spawn_terminal(terminal, env)
  if err then
    self.terminals[terminal_id] = nil
    self:_send_error(message_id, err, ACPClient.ERROR_CODES.INTERNAL_ERROR)
    return
  end

  self:_notify_terminal_update(terminal)
  self:_send_result(message_id, { terminalId = terminal_id })
end

---Handle terminal/output requests
---@param message_id number
---@param params table
function ACPClient:_handle_terminal_output(message_id, params)
  local terminal = self:_lookup_terminal_for_request(message_id, params, "terminal/output")
  if not terminal then return end
  local snapshot = ACPClient.terminal_snapshot(terminal)
  if snapshot.exitStatus then
    if snapshot.exitStatus.exitCode == nil then snapshot.exitStatus.exitCode = vim.NIL end
    if snapshot.exitStatus.signal == nil then snapshot.exitStatus.signal = vim.NIL end
  end
  self:_send_result(message_id, snapshot)
end

---Handle terminal/wait_for_exit requests
---@param message_id number
---@param params table
function ACPClient:_handle_terminal_wait_for_exit(message_id, params)
  local terminal = self:_lookup_terminal_for_request(message_id, params, "terminal/wait_for_exit")
  if not terminal then return end
  local function respond(exit_status)
    self:_send_result(message_id, {
      exitCode = exit_status.exitCode == nil and vim.NIL or exit_status.exitCode,
      signal = exit_status.signal == nil and vim.NIL or exit_status.signal,
    })
  end
  if terminal.exit_status then
    respond(terminal.exit_status)
    return
  end
  table.insert(terminal.waiters, respond)
end

---Handle terminal/kill requests
---@param message_id number
---@param params table
function ACPClient:_handle_terminal_kill(message_id, params)
  local terminal = self:_lookup_terminal_for_request(message_id, params, "terminal/kill")
  if not terminal then return end
  self:_kill_terminal(terminal)
  self:_send_result(message_id, vim.empty_dict())
end

---Handle terminal/release requests
---@param message_id number
---@param params table
function ACPClient:_handle_terminal_release(message_id, params)
  local terminal = self:_lookup_terminal_for_request(message_id, params, "terminal/release")
  if not terminal then return end
  self:_kill_terminal(terminal)
  terminal.released = true
  self.terminals[terminal.id] = nil
  self:_send_result(message_id, vim.empty_dict())
end

---Start client
---@param callback fun(err: avante.acp.ACPError|nil)
function ACPClient:connect(callback)
  callback = callback or function() end

  if self.state ~= "disconnected" then
    callback(nil)
    return
  end

  self.transport:start(vim.schedule_wrap(function(message) self:_handle_message(message) end))

  self:initialize(callback)
end

---Stop client
function ACPClient:stop()
  self.pending_permissions = {}
  self.permission_queue = {}
  self.active_permission_id = nil
  self.active_session_ids = {}
  self:release_all_terminals()
  -- Tell the exit handler this was requested so it fails pending callbacks quietly
  self._stopping = true
  self.transport:stop()
  self:_close_debug_log()
  self.reconnect_count = 0
end

---Initialize protocol connection
---@param callback fun(err: avante.acp.ACPError|nil)
function ACPClient:initialize(callback)
  callback = callback or function() end

  if self.state ~= "connected" then
    local error = self:_create_error(self.ERROR_CODES.PROTOCOL_ERROR, "Cannot initialize: client not connected")
    callback(error)
    return
  end

  self:_set_state("initializing")

  self:_send_request("initialize", {
    protocolVersion = self.protocol_version,
    clientCapabilities = self.capabilities,
  }, function(result, err)
    if err or not result then
      self:_set_state("error")
      vim.schedule(function() vim.notify("Failed to initialize", vim.log.levels.ERROR) end)
      callback(err or self:_create_error(self.ERROR_CODES.PROTOCOL_ERROR, "Failed to initialize: missing result"))
      return
    end

    -- Update protocol version and capabilities
    self.protocol_version = result.protocolVersion
    self.agent_capabilities = result.agentCapabilities or {}
    self.prompt_capabilities = self.agent_capabilities.promptCapabilities or {}
    self.auth_methods = result.authMethods or {}

    -- Check if we need to authenticate
    local auth_method = self.config.auth_method

    if auth_method then
      Utils.debug("Authenticating with method " .. auth_method)
      self:authenticate(auth_method, function(auth_err)
        if auth_err then
          callback(auth_err)
        else
          self:_set_state("ready")
          callback(nil)
        end
      end)
    else
      Utils.debug("No authentication method found or specified")
      self:_set_state("ready")
      callback(nil)
    end
  end)
end

---Authentication (if required)
---@param method_id string
---@param callback fun(err: avante.acp.ACPError|nil)
function ACPClient:authenticate(method_id, callback)
  callback = callback or function() end

  self:_send_request("authenticate", {
    methodId = method_id,
  }, function(_result, err) callback(err) end)
end

---Convert an env table (`{ KEY = "VAL" }`) into the ACP list form
---(`{ { name = "KEY", value = "VAL" } }`). List-form input is passed through.
---Entries are sorted by name so the output is deterministic.
---@param env table|nil
---@return avante.acp.MCPEnvVar[]
local function normalize_mcp_env(env)
  local result = {}
  if type(env) ~= "table" then return result end
  if vim.islist(env) then
    for _, item in ipairs(env) do
      if type(item) == "table" and item.name ~= nil then
        table.insert(result, { name = tostring(item.name), value = tostring(item.value or "") })
      end
    end
    return result
  end
  local names = {}
  for name, value in pairs(env) do
    if value ~= nil and value ~= false then table.insert(names, name) end
  end
  table.sort(names)
  for _, name in ipairs(names) do
    table.insert(result, { name = tostring(name), value = tostring(env[name]) })
  end
  return result
end

---Normalize the user-facing `mcp_servers` configuration into the ACP
---`mcpServers` list (https://agentclientprotocol.com/protocol/session-setup).
---
---Accepts either:
---  * the raw ACP list form:
---    `{ { name = "x", command = "...", args = {...}, env = { { name = "K", value = "V" } } }, ... }`
---  * the friendlier keyed table form:
---    `{ x = { command = "...", args = {...}, env = { K = "V" } }, ... }`
---
---HTTP/SSE servers (`type = "http"|"sse"` with a `url`) are passed through with
---their `headers` normalized the same way as `env`. Servers without a `command`
---(stdio) or `url` (http/sse) are dropped. Keyed entries are emitted in sorted
---name order so the output is deterministic.
---@param mcp_servers table|nil
---@return avante.acp.MCPServer[]
function ACPClient.normalize_mcp_servers(mcp_servers)
  local result = {}
  if type(mcp_servers) ~= "table" then return result end

  ---@param name string
  ---@param spec table
  ---@return avante.acp.MCPServer|nil
  local function normalize_one(name, spec)
    if type(spec) ~= "table" or spec.disabled == true or spec.enabled == false then return nil end
    local server_type = spec.type
    if server_type == nil and type(spec.url) == "string" then server_type = "http" end
    if server_type == "http" or server_type == "sse" then
      if type(spec.url) ~= "string" or spec.url == "" then return nil end
      return {
        type = server_type,
        name = name,
        url = spec.url,
        headers = normalize_mcp_env(spec.headers),
      }
    end
    if type(spec.command) ~= "string" or spec.command == "" then return nil end
    local args = {}
    if type(spec.args) == "table" then
      for _, arg in ipairs(spec.args) do
        table.insert(args, tostring(arg))
      end
    end
    return {
      name = name,
      command = spec.command,
      args = args,
      env = normalize_mcp_env(spec.env),
    }
  end

  if vim.islist(mcp_servers) then
    for _, spec in ipairs(mcp_servers) do
      if type(spec) == "table" and type(spec.name) == "string" then
        local normalized = normalize_one(spec.name, spec)
        if normalized then table.insert(result, normalized) end
      end
    end
    return result
  end

  local names = {}
  for name, _ in pairs(mcp_servers) do
    if type(name) == "string" then table.insert(names, name) end
  end
  table.sort(names)
  for _, name in ipairs(names) do
    local spec = mcp_servers[name]
    local normalized = normalize_one(spec.name or name, spec)
    if normalized then table.insert(result, normalized) end
  end
  return result
end

---Turn an agent error into something a user can act on.
---
---claude-agent-acp reports most startup failures as a bare "Internal error" with the real cause in
---`data.details`. The most common one is an unsupported `permissions.defaultMode` in the user's Claude
---settings (e.g. Claude Code's `auto` mode, which the deprecated 0.23.x shim does not know). The other
---frequent one is `authRequired` (-32000): the agent's CLI is not logged in. Returns a copy of `err` whose
---`message` carries the explanation; the original message is kept in `data.original_message`.
---@param err avante.acp.ACPError
---@return avante.acp.ACPError
function ACPClient.describe_error(err)
  if type(err) ~= "table" then return err end
  local data = type(err.data) == "table" and err.data or nil
  local details = data and data.details or nil
  if type(details) ~= "string" or details == "" then details = nil end

  local message
  if err.code == ACPClient.ERROR_CODES.AUTH_REQUIRED then
    if data and data.reason == "claude_subscription_not_supported" then
      message = "The agent refused to bill a claude.ai subscription (it runs with --hide-claude-auth). "
        .. "Log in with an API key or a Console account: run `/login --console` in the Avante input."
    else
      message = "The agent is not logged in (it reported: " .. tostring(err.message) .. "). "
        .. "Run `/login` in the Avante input to open the CLI's login flow in a terminal "
        .. "(for Claude Code that is `claude auth login`), then resend your message."
    end
  elseif details then
    local mode = details:match("^Invalid permissions%.defaultMode:%s*(.-)%.?$")
    if mode and mode ~= "" then
      message = string.format(
        'claude-agent-acp rejected `permissions.defaultMode = "%s"` from your Claude settings '
          .. "(~/.claude/settings.json or the project's .claude/settings*.json). This happens with the deprecated "
          .. "@zed-industries/claude-agent-acp shim (frozen at 0.23.1), which only knows default, acceptEdits, "
          .. "dontAsk, plan and bypassPermissions. Fix: `npm uninstall -g @zed-industries/claude-agent-acp && "
          .. "npm i -g @agentclientprotocol/claude-agent-acp`. Alternatively override the mode for this project in "
          .. '.claude/settings.local.json ({ "permissions": { "defaultMode": "default" } }), then reopen avante.',
        mode
      )
    else
      message = tostring(err.message) .. ": " .. details
    end
  else
    return err
  end

  local new_data = data and vim.deepcopy(data) or {}
  new_data.original_message = err.message
  return { code = err.code, message = message, data = new_data }
end

---@deprecated use `ACPClient.describe_error`
ACPClient.describe_session_error = ACPClient.describe_error

---Create new session
---@param cwd string
---@param mcp_servers table[]?
---@param callback fun(session_id: string|nil, err: avante.acp.ACPError|nil)
function ACPClient:create_session(cwd, mcp_servers, callback)
  callback = callback or function() end

  self:_send_request("session/new", {
    cwd = cwd,
    mcpServers = mcp_servers or {},
  }, function(result, err)
    if err then
      err = ACPClient.describe_error(err)
      vim.schedule(function() vim.notify("Failed to create session: " .. err.message, vim.log.levels.ERROR) end)
      callback(nil, err)
      return
    end
    if not result then
      local error = self:_create_error(self.ERROR_CODES.PROTOCOL_ERROR, "Failed to create session: missing result")
      callback(nil, error)
      return
    end
    self:_convert_legacy_session_fields(result)
    self.active_session_ids[result.sessionId] = true
    callback(result.sessionId, nil)
  end)
end

---Whether the given session has been created or loaded on this connection
---@param session_id string
---@return boolean
function ACPClient:is_session_active(session_id) return self.active_session_ids[session_id] == true end

---Whether the connected agent advertises the loadSession capability
---@return boolean
function ACPClient:supports_load_session()
  return self.agent_capabilities ~= nil and self.agent_capabilities.loadSession == true
end

---Whether the connected agent advertises session/list (sessionCapabilities.list)
---@return boolean
function ACPClient:supports_list_sessions()
  local caps = self.agent_capabilities
  return caps ~= nil and type(caps.sessionCapabilities) == "table" and caps.sessionCapabilities.list ~= nil
end

---List sessions known to the agent (session/list)
---@param cwd string|nil
---@param callback fun(sessions: table[]|nil, err: avante.acp.ACPError|nil)
function ACPClient:list_sessions(cwd, callback)
  callback = callback or function() end
  if not self:supports_list_sessions() then
    callback(nil, self:_create_error(self.ERROR_CODES.PROTOCOL_ERROR, "Agent does not support listing sessions"))
    return
  end
  self:_send_request("session/list", { cwd = cwd }, function(result, err)
    if err then
      callback(nil, err)
      return
    end
    callback(result and result.sessions or {}, nil)
  end)
end

---Load existing session
---@param session_id string
---@param cwd string
---@param mcp_servers table[]?
---@param callback fun(result: table|nil, err: avante.acp.ACPError|nil)
function ACPClient:load_session(session_id, cwd, mcp_servers, callback)
  callback = callback or function() end

  if not self.agent_capabilities or not self.agent_capabilities.loadSession then
    vim.schedule(function() vim.notify("Agent does not support loading sessions", vim.log.levels.WARN) end)
    local err = self:_create_error(self.ERROR_CODES.PROTOCOL_ERROR, "Agent does not support loading sessions")
    callback(nil, err)
    return
  end

  self:_send_request("session/load", {
    sessionId = session_id,
    cwd = cwd,
    mcpServers = mcp_servers or {},
  }, function(result, err)
    if result then self:_convert_legacy_session_fields(result) end
    if not err then self.active_session_ids[session_id] = true end
    callback(result, err)
  end)
end

---Set a session config option (model, mode, etc.)
---@param session_id string
---@param config_id string
---@param value string
---@param callback fun(config_options: avante.acp.ConfigOption[]|nil, err: avante.acp.ACPError|nil)
function ACPClient:set_config_option(session_id, config_id, value, callback)
  callback = callback or function() end

  self:_send_request("session/set_config_option", {
    sessionId = session_id,
    configId = config_id,
    value = value,
  }, function(result, err)
    if err then
      callback(nil, err)
      return
    end
    if result and result.configOptions then self.config_options = result.configOptions end
    callback(self.config_options, nil)
  end)
end

---Set session mode via legacy session/set_mode API
---@param session_id string
---@param mode_id string
---@param callback fun(config_options: avante.acp.ConfigOption[]|nil, err: avante.acp.ACPError|nil)
function ACPClient:set_mode(session_id, mode_id, callback)
  callback = callback or function() end

  self:_send_request("session/set_mode", {
    sessionId = session_id,
    modeId = mode_id,
  }, function(_result, err)
    if err then
      callback(nil, err)
      return
    end
    -- Update the synthetic mode config option's currentValue locally
    if self.config_options then
      for _, opt in ipairs(self.config_options) do
        if opt.id == "mode" and opt.category == "mode" then
          opt.currentValue = mode_id
          break
        end
      end
    end
    callback(self.config_options, nil)
  end)
end

---Returns the mode config option (category "mode"), if the agent exposes one.
---@return avante.acp.ConfigOption|nil
function ACPClient:get_mode_option()
  if not self.config_options then return nil end
  for _, opt in ipairs(self.config_options) do
    if opt.category == "mode" then return opt end
  end
  return nil
end

---Returns the currently selected mode id, if known.
---@return string|nil
function ACPClient:get_current_mode()
  local opt = self:get_mode_option()
  if opt and type(opt.currentValue) == "string" then return opt.currentValue end
  return nil
end

---Set session model via non-standard session/set_model API.
---Some agents (e.g. OpenCode) support this even without configOptions.
---Agents that don't support it will return -32601 (Method not found).
---@param session_id string
---@param model_id string
---@param callback fun(config_options: avante.acp.ConfigOption[]|nil, err: avante.acp.ACPError|nil)
function ACPClient:set_model(session_id, model_id, callback)
  callback = callback or function() end

  self:_send_request("session/set_model", {
    sessionId = session_id,
    modelId = model_id,
  }, function(_result, err)
    if err then
      callback(nil, err)
      return
    end
    -- Update the synthetic model config option's currentValue locally
    if self.config_options then
      for _, opt in ipairs(self.config_options) do
        if opt.id == "model" and opt.category == "model" then
          opt.currentValue = model_id
          break
        end
      end
    end
    callback(self.config_options, nil)
  end)
end

---Convert legacy session fields (modes/models) to synthetic config_options.
---If result.configOptions exists, use it directly and clear _legacy_api flag.
---Otherwise, build synthetic ConfigOption[] from result.modes and result.models.
---@param result table The session/new or session/load result
function ACPClient:_convert_legacy_session_fields(result)
  if result.configOptions then
    self.config_options = result.configOptions
    self._legacy_api = false
    return
  end

  local config_options = {}

  -- Convert legacy modes field
  if result.modes and result.modes.availableModes then
    local options = {}
    for _, m in ipairs(result.modes.availableModes) do
      table.insert(options, {
        value = m.id,
        name = m.name or m.id,
        description = m.description,
      })
    end
    table.insert(config_options, {
      id = "mode",
      name = "Mode",
      category = "mode",
      type = "select",
      currentValue = result.modes.currentModeId or "",
      options = options,
    })
  end

  -- Convert legacy models field
  if result.models and result.models.availableModels then
    local options = {}
    for _, m in ipairs(result.models.availableModels) do
      table.insert(options, {
        value = m.modelId,
        name = m.name or m.modelId,
        description = m.description,
      })
    end
    table.insert(config_options, {
      id = "model",
      name = "Model",
      category = "model",
      type = "select",
      currentValue = result.models.currentModelId or "",
      options = options,
    })
  end

  if #config_options > 0 then
    self.config_options = config_options
    self._legacy_api = true
  else
    self.config_options = nil
    self._legacy_api = false
  end
end

---Send prompt
---@param session_id string
---@param prompt table[]
---@param callback fun(result: table|nil, err: avante.acp.ACPError|nil)
function ACPClient:send_prompt(session_id, prompt, callback)
  local params = {
    sessionId = session_id,
    prompt = prompt,
  }
  return self:_send_request("session/prompt", params, callback)
end

---Cancel session
---@param session_id string
function ACPClient:cancel_session(session_id)
  -- Per spec, in-flight permission requests must be resolved with "cancelled"
  -- when the turn is cancelled.
  self:_cancel_pending_permissions()
  self:kill_all_terminals(session_id)
  self:_send_notification("session/cancel", {
    sessionId = session_id,
  })
end

---Helper function: Create text content block
---@param text string
---@param annotations table?
---@return table
function ACPClient:create_text_content(text, annotations)
  return {
    type = "text",
    text = text,
    annotations = annotations,
  }
end

---Get the prompt capabilities advertised by the agent in the `initialize` response.
---Returns an empty table until the client has been initialized.
---@return avante.acp.PromptCapabilities
function ACPClient:get_prompt_capabilities()
  if self.prompt_capabilities then return self.prompt_capabilities end
  if self.agent_capabilities and self.agent_capabilities.promptCapabilities then
    return self.agent_capabilities.promptCapabilities
  end
  return {}
end

---Check whether the agent advertised support for a given prompt capability.
---@param name "image" | "audio" | "embeddedContext"
---@return boolean
function ACPClient:supports_prompt_capability(name) return self:get_prompt_capabilities()[name] == true end

---Helper function: Create image content block
---@param data string Base64 encoded image data
---@param mime_type string
---@param uri string?
---@param annotations table?
---@return table
function ACPClient:create_image_content(data, mime_type, uri, annotations)
  return {
    type = "image",
    data = data,
    mimeType = mime_type,
    uri = uri,
    annotations = annotations,
  }
end

---Helper function: Create audio content block
---@param data string Base64 encoded audio data
---@param mime_type string
---@param annotations table?
---@return table
function ACPClient:create_audio_content(data, mime_type, annotations)
  return {
    type = "audio",
    data = data,
    mimeType = mime_type,
    annotations = annotations,
  }
end

---Helper function: Create resource link content block
---@param uri string
---@param name string
---@param description string?
---@param mime_type string?
---@param size number?
---@param title string?
---@param annotations table?
---@return table
function ACPClient:create_resource_link_content(uri, name, description, mime_type, size, title, annotations)
  return {
    type = "resource_link",
    uri = uri,
    name = name,
    description = description,
    mimeType = mime_type,
    size = size,
    title = title,
    annotations = annotations,
  }
end

---Helper function: Create embedded resource content block
---@param resource table
---@param annotations table?
---@return table
function ACPClient:create_resource_content(resource, annotations)
  return {
    type = "resource",
    resource = resource,
    annotations = annotations,
  }
end

---Helper function: Create text resource
---@param uri string
---@param text string
---@param mime_type string?
---@return table
function ACPClient:create_text_resource(uri, text, mime_type)
  return {
    uri = uri,
    text = text,
    mimeType = mime_type,
  }
end

---Helper function: Create binary resource
---@param uri string
---@param blob string Base64 encoded binary data
---@param mime_type string?
---@return table
function ACPClient:create_blob_resource(uri, blob, mime_type)
  return {
    uri = uri,
    blob = blob,
    mimeType = mime_type,
  }
end

---Convenience method: Check if client is ready
---@return boolean
function ACPClient:is_ready() return self.state == "ready" end

---Convenience method: Check if client is connected
---@return boolean
function ACPClient:is_connected() return self.state ~= "disconnected" and self.state ~= "error" end

---Convenience method: Get current state
---@return ACPConnectionState
function ACPClient:get_state() return self.state end

---Convenience method: Wait for client to be ready
---@param callback function
---@param timeout number? Timeout in milliseconds
function ACPClient:wait_ready(callback, timeout)
  if self:is_ready() then
    callback(nil)
    return
  end

  local timeout_ms = timeout or 10000 -- 10 seconds default
  local start_time = vim.loop.now()

  local function check_ready()
    if self:is_ready() then
      callback(nil)
    elseif self.state == "error" then
      callback(self:_create_error(self.ERROR_CODES.PROTOCOL_ERROR, "Client entered error state while waiting"))
    elseif vim.loop.now() - start_time > timeout_ms then
      callback(self:_create_error(self.ERROR_CODES.TIMEOUT_ERROR, "Timeout waiting for client to be ready"))
    else
      vim.defer_fn(check_ready, 100) -- Check every 100ms
    end
  end

  check_ready()
end

---Convenience method: Send simple text prompt
---@param session_id string
---@param text string
---@param callback fun(result: table|nil, err: avante.acp.ACPError|nil)
function ACPClient:send_text_prompt(session_id, text, callback)
  local prompt = { self:create_text_content(text) }
  self:send_prompt(session_id, prompt, callback)
end

return ACPClient

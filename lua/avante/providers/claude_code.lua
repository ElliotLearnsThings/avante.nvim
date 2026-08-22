---@mod avante-providers-claude_code Claude Code provider
---@brief [[
--- Drives the native Claude Code CLI (`claude`) through a small Python adapter
--- that lives in `py/claude-code-adapter`.
---
--- Unlike the HTTP providers, this one does not talk to an API endpoint. The
--- adapter runs `claude --print --output-format stream-json`, merges the CLI's
--- agentic loop into a single assistant message, and re-emits it as Anthropic
--- Messages API server-sent events — so everything downstream of
--- `parse_response` is unchanged.
---
--- Claude Code runs its own tools (Read, Edit, Bash, ...). Avante's tool runner
--- is therefore disabled for this provider, and the CLI's tool activity is shown
--- inline in the sidebar.
---
--- Claude Code's native slash commands, skills and plugins are surfaced too:
--- the CLI announces them at the start of every turn, they are cached to disk,
--- and Avante offers them alongside its own. A command Avante does not handle
--- itself is passed through untouched for the CLI to resolve.
---
--- Authentication is the CLI's own (`claude auth`); no API key is read. Use
--- |:AvanteClaudeCodeAuth| to sign in and |:AvanteClaudeCodeStatus| to inspect
--- the local installation.
---@brief ]]

local Utils = require("avante.utils")
local P = require("avante.providers")
local HistoryMessage = require("avante.history.message")

---@class AvanteClaudeCodeProviderFunctor: AvanteProviderFunctor
local M = {}

M.transport = "subprocess"
-- The CLI owns authentication, so Avante must never prompt for a key.
M.api_key_name = ""
M.tokenizer_id = "gpt-4o"
M.role_map = {
  user = "user",
  assistant = "assistant",
}

--- Claude Code session ids, keyed by conversation. See `M.session_key`.
---@type table<string, string>
M._sessions = {}

--- What the running Claude Code install offers: its slash commands, skills,
--- plugins, MCP servers, tools, model and auth source. Populated from the
--- `avante_capabilities` event at the start of every turn, and reloaded from
--- disk at startup so commands are available before the first message.
---@type table<string, any>
M._capabilities = {}

--- Where `M._capabilities` is persisted between sessions.
---@return string
local function capabilities_cache_path()
  local dir = vim.fs.joinpath(vim.fn.stdpath("cache"), "avante")
  vim.fn.mkdir(dir, "p")
  return vim.fs.joinpath(dir, "claude_code_capabilities.json")
end

--- Replace the contents of `M._capabilities` in place.
---
--- Rebinding the field would break the reference it shares with the provider
--- table `Providers.__index` builds, leaving that copy permanently empty.
---@param capabilities table<string, any>
local function set_capabilities(capabilities)
  for key in pairs(M._capabilities) do
    M._capabilities[key] = nil
  end
  for key, value in pairs(capabilities) do
    M._capabilities[key] = value
  end
end

--- Load the cached capabilities, if any. Failures are not worth reporting:
--- the next turn repopulates them.
function M.load_capabilities()
  local path = capabilities_cache_path()
  if vim.fn.filereadable(path) == 0 then return end
  local ok, decoded = pcall(function() return vim.json.decode(table.concat(vim.fn.readfile(path), "\n")) end)
  if ok and type(decoded) == "table" then set_capabilities(decoded) end
end

---@param capabilities table<string, any>
local function save_capabilities(capabilities)
  set_capabilities(capabilities)
  pcall(function() vim.fn.writefile(vim.split(vim.json.encode(capabilities), "\n"), capabilities_cache_path()) end)
end

--- Absolute path to the bundled Python adapter package's parent directory.
---@return string
local function adapter_dir()
  -- Normalized first so this works with Windows' backslash separators too.
  local this_file = vim.fs.normalize(debug.getinfo(1, "S").source:sub(2))
  local plugin_root = this_file:gsub("/lua/avante/providers/claude_code%.lua$", "")
  return vim.fs.joinpath(plugin_root, "py", "claude-code-adapter")
end

--- Resolve the Python interpreter used to run the adapter.
---@param provider_conf table
---@return string?
local function resolve_python(provider_conf)
  if provider_conf.python_path and provider_conf.python_path ~= "" then return provider_conf.python_path end
  for _, candidate in ipairs({ "python3", "python" }) do
    local resolved = vim.fn.exepath(candidate)
    if resolved ~= "" then return resolved end
  end
  return nil
end

--- Resolve the Claude Code executable.
---@param provider_conf table
---@return string?
local function resolve_cli(provider_conf)
  local candidate = provider_conf.cli_path
  if candidate == nil or candidate == "" then candidate = "claude" end
  -- An explicit path is taken at face value; a bare name is looked up on $PATH.
  if candidate:find("[/\\]") then return vim.fn.executable(candidate) == 1 and candidate or nil end
  local resolved = vim.fn.exepath(candidate)
  return resolved ~= "" and resolved or nil
end

--- Flatten a message's content down to the text Claude Code will receive.
---@param content AvanteLLMMessageContent
---@return string
local function content_to_text(content)
  if type(content) == "string" then return content end
  if type(content) ~= "table" then return "" end
  local parts = {}
  for _, item in ipairs(content) do
    if type(item) == "string" then
      table.insert(parts, item)
    elseif type(item) == "table" then
      if item.type == "text" then
        table.insert(parts, item.text)
      elseif item.type == "thinking" then
        table.insert(parts, item.thinking)
      elseif item.type == "tool_result" then
        table.insert(parts, type(item.content) == "string" and item.content or vim.inspect(item.content))
      end
    end
  end
  return table.concat(vim.tbl_filter(function(part) return part ~= nil and part ~= "" end, parts), "\n")
end

--- A stable identifier for the conversation a request belongs to.
---
--- The first user message never changes for the life of a chat, so hashing it
--- lets consecutive turns find the Claude Code session they should resume.
---@param messages AvanteLLMMessage[]
---@return string?
function M.session_key(messages)
  for _, message in ipairs(messages) do
    if message.role == "user" then
      local text = content_to_text(message.content)
      if text ~= "" then return vim.fn.sha256(text) end
    end
  end
  return nil
end

function M:is_disable_stream() return false end

function M:is_env_set() return resolve_cli(P.get_config("claude_code")) ~= nil end

function M:setup()
  local provider_conf = P.get_config("claude_code")
  if resolve_cli(provider_conf) == nil then
    Utils.warn(
      "Claude Code CLI not found. Install it from https://claude.com/claude-code, "
        .. "or set providers.claude_code.cli_path.",
      { once = true }
    )
  end
  M.load_capabilities()
  require("avante.tokenizers").setup(M.tokenizer_id)
end

---@param opts AvantePromptOptions
---@return table[]
function M:parse_messages(opts)
  local messages = {}
  for _, message in ipairs(opts.messages) do
    local text = content_to_text(message.content)
    if text ~= "" then
      table.insert(messages, { role = self.role_map[message.role] or message.role, content = text })
    end
  end
  -- Claude Code reads images with its own tools, so point it at the files.
  if opts.image_paths and #opts.image_paths > 0 and #messages > 0 then
    local last = messages[#messages]
    last.content = last.content .. "\n\nAttached images:\n- " .. table.concat(opts.image_paths, "\n- ")
  end
  return messages
end

---@param prompt_opts AvantePromptOptions
---@return AvanteSubprocessOutput | nil
function M:parse_subprocess_args(prompt_opts)
  local provider_conf, extra_request_body = P.parse_config(self)

  local cli_path = resolve_cli(provider_conf)
  if cli_path == nil then
    Utils.error(
      "Claude Code CLI not found. Install it from https://claude.com/claude-code, "
        .. "or set providers.claude_code.cli_path.",
      { once = true, title = "Avante" }
    )
    return nil
  end

  local python = resolve_python(provider_conf)
  if python == nil then
    Utils.error(
      "No Python interpreter found. Set providers.claude_code.python_path.",
      { once = true, title = "Avante" }
    )
    return nil
  end

  local messages = self:parse_messages(prompt_opts)
  local session_key = M.session_key(prompt_opts.messages)
  local resume = nil
  if provider_conf.stateful ~= false and session_key then resume = M._sessions[session_key] end

  local request = vim.tbl_deep_extend("force", {
    messages = messages,
    system_prompt = prompt_opts.system_prompt,
    append_system_prompt = provider_conf.append_system_prompt,
    model = provider_conf.model,
    fallback_model = provider_conf.fallback_model,
    effort = provider_conf.effort,
    cwd = provider_conf.cwd or Utils.get_project_root(),
    resume = resume,
    permission_mode = provider_conf.permission_mode,
    tools = provider_conf.tools,
    allowed_tools = provider_conf.allowed_tools,
    disallowed_tools = provider_conf.disallowed_tools,
    add_dirs = provider_conf.add_dirs or {},
    mcp_config = provider_conf.mcp_config or {},
    strict_mcp_config = provider_conf.strict_mcp_config or false,
    plugin_dirs = provider_conf.plugin_dirs or {},
    plugin_urls = provider_conf.plugin_urls or {},
    disable_slash_commands = provider_conf.disable_slash_commands or false,
    settings = provider_conf.settings,
    setting_sources = provider_conf.setting_sources,
    agents = provider_conf.agents,
    max_budget_usd = provider_conf.max_budget_usd,
    emit_tool_activity = provider_conf.emit_tool_activity ~= false,
    cli_path = cli_path,
    extra_args = provider_conf.extra_args or {},
    env = provider_conf.env or {},
    -- `timeout` is milliseconds across Avante's provider config; the adapter
    -- works in seconds. 0 means no timeout on both sides.
    timeout = (provider_conf.timeout or 0) / 1000,
  }, extra_request_body)

  return {
    cmd = python,
    args = { "-m", "avante_claude_code" },
    stdin = vim.json.encode(request),
    cwd = adapter_dir(),
    env = vim.tbl_extend("force", { PYTHONPATH = adapter_dir() }, provider_conf.env or {}),
    -- Seeded onto the turn context so `parse_response` can file the session id.
    ctx = { session_key = session_key },
  }
end

---@param usage table | nil
---@return avante.LLMTokenUsage | nil
function M.transform_usage(usage)
  if usage == nil then return nil end
  local input = (usage.input_tokens or 0)
    + (usage.cache_creation_input_tokens or 0)
    + (usage.cache_read_input_tokens or 0)
  return {
    prompt_tokens = input,
    completion_tokens = usage.output_tokens or 0,
  }
end

function M:parse_response(ctx, data_stream, event_state, opts)
  if event_state == nil or event_state == "" then
    local matched = data_stream:match('"type"%s*:%s*"([%w_]+)"')
    if matched == nil then return end
    event_state = matched
  end

  if ctx.content_blocks == nil then ctx.content_blocks = {} end

  ---@param content AvanteLLMMessageContentItem
  ---@param uuid? string
  ---@param final? boolean
  ---@return avante.HistoryMessage
  local function new_assistant_message(content, uuid, final)
    return HistoryMessage:new("assistant", content, {
      state = final and "generated" or "generating",
      turn_id = ctx.turn_id,
      uuid = uuid,
    })
  end

  local ok, jsn = pcall(vim.json.decode, data_stream)
  if not ok then return end

  if event_state == "avante_session" then
    -- Remember the CLI session so the next turn can resume instead of replaying.
    if jsn.session_id and ctx.session_key then M._sessions[ctx.session_key] = jsn.session_id end
    return
  end

  if event_state == "avante_capabilities" then
    jsn.type = nil
    save_capabilities(jsn)
    return
  end

  if event_state == "message_start" then
    ctx.usage = jsn.message and jsn.message.usage or nil
  elseif event_state == "content_block_start" then
    local content_block = jsn.content_block
    if content_block == nil then return end
    ctx.content_blocks[jsn.index + 1] = content_block
    if content_block.type == "text" then
      local msg = new_assistant_message(content_block.text or "")
      content_block.uuid = msg.uuid
      if opts.on_messages_add then opts.on_messages_add({ msg }) end
    elseif content_block.type == "thinking" then
      if opts.on_chunk then opts.on_chunk("<think>\n") end
      local msg = new_assistant_message({
        type = "thinking",
        thinking = content_block.thinking or "",
        signature = content_block.signature,
      })
      content_block.uuid = msg.uuid
      if opts.on_messages_add then opts.on_messages_add({ msg }) end
    end
  elseif event_state == "content_block_delta" then
    local content_block = ctx.content_blocks[jsn.index + 1]
    if content_block == nil or jsn.delta == nil then return end
    if jsn.delta.type == "text_delta" then
      content_block.text = (content_block.text or "") .. jsn.delta.text
      if opts.on_chunk then opts.on_chunk(jsn.delta.text) end
      if opts.on_messages_add then
        opts.on_messages_add({ new_assistant_message(content_block.text, content_block.uuid) })
      end
    elseif jsn.delta.type == "thinking_delta" then
      content_block.thinking = (content_block.thinking or "") .. jsn.delta.thinking
      if opts.on_chunk then opts.on_chunk(jsn.delta.thinking) end
      if opts.on_messages_add then
        opts.on_messages_add({
          new_assistant_message({
            type = "thinking",
            thinking = content_block.thinking,
            signature = content_block.signature,
          }, content_block.uuid),
        })
      end
    elseif jsn.delta.type == "signature_delta" then
      content_block.signature = (content_block.signature or "") .. jsn.delta.signature
    end
  elseif event_state == "content_block_stop" then
    local content_block = ctx.content_blocks[jsn.index + 1]
    if content_block == nil then return end
    if content_block.type == "text" then
      if opts.on_messages_add then
        opts.on_messages_add({ new_assistant_message(content_block.text or "", content_block.uuid, true) })
      end
    elseif content_block.type == "thinking" then
      if opts.on_chunk then
        local thinking = content_block.thinking
        if thinking and thinking ~= vim.NIL and thinking:sub(-1) ~= "\n" then
          opts.on_chunk("\n</think>\n\n")
        else
          opts.on_chunk("</think>\n\n")
        end
      end
      if opts.on_messages_add then
        opts.on_messages_add({
          new_assistant_message({
            type = "thinking",
            thinking = content_block.thinking or "",
            signature = content_block.signature,
          }, content_block.uuid, true),
        })
      end
    end
  elseif event_state == "message_delta" then
    if jsn.usage then ctx.usage = jsn.usage end
    local stop_reason = jsn.delta and jsn.delta.stop_reason or "end_turn"
    -- Claude Code resolves its own tool calls, so a turn only ever completes.
    if stop_reason == "max_tokens" then
      opts.on_stop({ reason = "max_tokens", usage = M.transform_usage(ctx.usage) })
    else
      opts.on_stop({ reason = "complete", usage = M.transform_usage(ctx.usage) })
    end
  elseif event_state == "error" then
    opts.on_stop({ reason = "error", error = jsn.error or jsn })
  end
end

--- Claude Code's own slash commands, as Avante slash commands.
---
--- They carry no callback: Avante passes the text through and the CLI resolves
--- the command itself. Avante's built-in commands of the same name win, since
--- those act on the Avante-side conversation.
---@return AvanteSlashCommand[]
function M.list_slash_commands()
  local commands = {}
  for _, name in ipairs(M._capabilities.slash_commands or {}) do
    if type(name) == "string" and name ~= "" then
      table.insert(commands, {
        name = name,
        description = "Claude Code: /" .. name,
        details = "Native Claude Code command, resolved by the CLI",
      })
    end
  end
  return commands
end

--- Everything Avante knows about the local Claude Code installation.
---
--- Runs the adapter's probe, which only calls CLI subcommands that answer
--- locally — no turn is started and no tokens are spent.
---@param timeout? integer Milliseconds to wait; defaults to 30000
---@return table<string, any> | nil report, string | nil error
function M.probe(timeout)
  local provider_conf = P.get_config("claude_code")
  local cli_path = resolve_cli(provider_conf)
  if cli_path == nil then return nil, "Claude Code CLI not found" end
  local python = resolve_python(provider_conf)
  if python == nil then return nil, "No Python interpreter found" end

  local result = vim
    .system({ python, "-m", "avante_claude_code", "--probe", "--cli-path", cli_path }, {
      text = true,
      cwd = adapter_dir(),
      env = vim.tbl_extend("force", { PYTHONPATH = adapter_dir() }, provider_conf.env or {}),
    })
    :wait(timeout or 30000)

  if result.code ~= 0 then return nil, Utils.trim_spaces(result.stderr or "") end
  local ok, decoded = pcall(vim.json.decode, result.stdout or "")
  if not ok then return nil, "could not parse the probe output" end
  return decoded, nil
end

--- Whether Claude Code is signed in, and how.
---@return boolean logged_in, string detail
function M.auth_status()
  local report, err = M.probe()
  if report == nil then return false, err or "probe failed" end
  local auth = report.auth or {}
  if not auth.ok then return false, tostring(auth.error or "could not read auth status") end
  local value = auth.value or {}
  if not value.loggedIn then return false, "not signed in" end
  return true, string.format("%s (%s)", value.authMethod or "signed in", value.apiProvider or "unknown provider")
end

--- Start Claude Code's interactive sign-in flow in a terminal split.
function M.auth_login()
  local provider_conf = P.get_config("claude_code")
  local cli_path = resolve_cli(provider_conf)
  if cli_path == nil then
    Utils.error("Claude Code CLI not found. Install it from https://claude.com/claude-code.", { title = "Avante" })
    return
  end
  -- Sign-in is interactive, so it needs a real terminal rather than a job.
  vim.cmd("botright split")
  vim.cmd("terminal " .. vim.fn.fnameescape(cli_path) .. " auth login")
  vim.cmd("startinsert")
end

---@return AvanteProviderModelList | nil
function M:list_models()
  local provider_conf = P.get_config("claude_code")
  local names = provider_conf.model_names or {}
  return vim.tbl_map(function(name) return { name = name, id = name, display_name = name } end, names)
end

return M

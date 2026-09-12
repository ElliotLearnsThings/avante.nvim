---@mod avante-slashcommands Slash commands
---@brief [[
---Built-in slash commands available in the Avante input buffer.
---
--- Slash commands are triggered by typing `/` at the beginning of a chat
--- message. Commands with callbacks are handled locally by Avante; other
--- commands may rewrite the prompt before it is submitted.
---
--- - `/help`: show available commands
--- - `/init`: initialize AGENTS.md based on the current project
--- - `/clear`: clear chat history
--- - `/new`: start a new chat
--- - `/compact`: compact history messages
--- - `/model`: select model
--- - `/lines <start>-<end> <question>`: ask about specific lines
--- - `/commit`: generate a commit message
---
--- ACP agents (e.g. Claude Code via `claude-agent-acp`) may advertise their
--- own commands through `available_commands_update`. Those are registered in
--- `Config.slash_commands` with `source = "acp"` and are replaced wholesale on
--- every update, so commands from a previous agent never linger. When an ACP
--- command is submitted the raw `/name args` text is forwarded to the agent
--- unchanged.
---
--- Precedence when an agent advertises a command with the same name as a
--- built-in one: `/clear`, `/model` and `/login` always act locally (they manage
--- Avante's own history / provider selection / CLI login); every other name is
--- handled by the agent.
--- - `/plan [mode]`: toggle ACP plan mode (or switch to a specific ACP mode)
--- - `/login [args]`: run the ACP agent CLI's native login flow in a terminal split
---   (Claude Code: `claude auth login`; `/login --console` for API billing)
---@brief ]]

---@class avante.SlashCommands
---@field get_builtin_commands fun(): AvanteSlashCommand[]

local M = {}

---@type AvanteSlashCommand[]
local builtin_commands = {
  {
    description = "Show help message",
    details = "Show help message",
    name = "help",
  },
  {
    description = "Init AGENTS.md based on the current project",
    details = "Init AGENTS.md based on the current project",
    name = "init",
  },
  {
    description = "Clear chat history",
    details = "Clear chat history",
    name = "clear",
  },
  {
    description = "New chat",
    details = "New chat",
    name = "new",
  },
  {
    description = "Compact history messages to save tokens",
    details = "Compact history messages to save tokens",
    name = "compact",
  },
  {
    description = "Select model",
    details = "Select model",
    name = "model",
  },
  {
    shorthelp = "Ask a question about specific lines",
    description = "/lines <start>-<end> <question>",
    details = "Ask a question about specific lines\n/lines <start>-<end> <question>",
    name = "lines",
  },
  {
    description = "Commit the changes",
    details = "Commit the changes",
    name = "commit",
  },
  {
    shorthelp = "Toggle ACP plan mode (or `/plan <mode>` to set a mode)",
    description = "/plan [mode]",
    details = "Toggle plan mode on the ACP agent session.\n/plan            toggle plan mode\n/plan <mode>     switch to a specific mode (e.g. default, acceptEdits)",
    name = "plan",
  },
  {
    shorthelp = "Log in to the ACP agent's CLI (Claude Code: `claude auth login`)",
    description = "/login [args]",
    details = "Run the ACP agent CLI's native login flow in a terminal split.\n"
      .. "/login            claude.ai subscription login (Claude Code)\n"
      .. "/login --console  Anthropic Console (API billing) login",
    name = "login",
  },
}

---Split `/login` arguments into a list.
---@param args string|nil
---@return string[]
local function split_args(args)
  local result = {}
  for _, part in ipairs(vim.split(vim.trim(args or ""), "%s+")) do
    if part ~= "" then table.insert(result, part) end
  end
  return result
end

---Work out which command implements the login flow for the active ACP provider.
---
---Preference order:
--- 1. a `terminal`-type entry in the agent's advertised `authMethods` (ACP
---    `initialize` result), run as the agent command plus the method's args, or
---    the `_meta["terminal-auth"]` command when the agent provides one;
--- 2. for Claude Code (`claude-agent-acp`), the CLI's own `claude auth login`,
---    using the same executable the shim is configured with;
--- 3. nothing, with a reason.
---@param provider_name string|nil
---@param acp_provider table|nil the `acp_providers[provider_name]` entry
---@param acp_client avante.acp.ACPClient|nil the sidebar's live client, if any
---@param args string|nil extra arguments typed after `/login`
---@return string[]|nil cmd
---@return string|nil reason why no command is available
function M.resolve_login_command(provider_name, acp_provider, acp_client, args)
  if type(acp_provider) ~= "table" then
    return nil, "/login is only available with ACP providers (e.g. claude-code)"
  end
  local extra = split_args(args)

  local methods = acp_client and acp_client.auth_methods or nil
  if type(methods) == "table" then
    for _, method in ipairs(methods) do
      if type(method) == "table" and method.type == "terminal" then
        local meta = type(method._meta) == "table" and method._meta["terminal-auth"] or nil
        local cmd
        if type(meta) == "table" and type(meta.command) == "string" then
          cmd = { meta.command }
          vim.list_extend(cmd, type(meta.args) == "table" and meta.args or {})
        elseif type(acp_provider.command) == "string" then
          cmd = { acp_provider.command }
          vim.list_extend(cmd, type(acp_provider.args) == "table" and acp_provider.args or {})
          vim.list_extend(cmd, type(method.args) == "table" and method.args or {})
        end
        if cmd then
          vim.list_extend(cmd, extra)
          return cmd, nil
        end
      end
    end
  end

  local command = tostring(acp_provider.command or "")
  if provider_name == "claude-code" or command:find("claude%-agent%-acp") then
    local env = type(acp_provider.env) == "table" and acp_provider.env or {}
    local exe = env.CLAUDE_CODE_EXECUTABLE or env.ACP_PATH_TO_CLAUDE_CODE_EXECUTABLE
    if type(exe) ~= "string" or exe == "" then exe = vim.fn.exepath("claude") end
    if exe == "" then exe = "claude" end
    local cmd = { exe, "auth", "login" }
    vim.list_extend(cmd, extra)
    return cmd, nil
  end

  return nil,
    "No login flow is known for ACP provider '"
      .. tostring(provider_name)
      .. "'; log in with its CLI in a terminal and resend your message."
end

---Run `cmd` in a terminal split so the user can complete an interactive login
---(browser hand-off, pasted code, ...). The split closes itself on success.
---@param cmd string[]
---@param env table<string, string>|nil extra environment for the process
function M.open_login_terminal(cmd, env)
  local Utils = require("avante.utils")
  local api = vim.api
  local buf = api.nvim_create_buf(false, true)
  vim.cmd("botright 15split")
  local win = api.nvim_get_current_win()
  api.nvim_win_set_buf(win, buf)

  local job_env = {}
  for k, v in pairs(env or {}) do
    if type(v) == "string" then job_env[k] = v end
  end

  local opts = {
    env = next(job_env) ~= nil and job_env or nil,
    on_exit = function(_, code)
      vim.schedule(function()
        if code == 0 then
          Utils.info("Login finished. Resend your message to continue.")
          if api.nvim_win_is_valid(win) then pcall(api.nvim_win_close, win, true) end
        else
          Utils.warn("Login exited with code " .. tostring(code) .. "; see the terminal for details.")
        end
      end)
    end,
  }
  local job
  if vim.fn.has("nvim-0.11") == 1 then
    opts.term = true
    job = vim.fn.jobstart(cmd, opts)
  else
    job = vim.fn.termopen(cmd, opts)
  end
  if job <= 0 then
    Utils.error("Failed to start login command: " .. table.concat(cmd, " "))
    if api.nvim_win_is_valid(win) then pcall(api.nvim_win_close, win, true) end
    return
  end
  vim.cmd("startinsert")
end

---@param commands AvanteSlashCommand[]
---@return string
local function get_help_text(commands)
  local help_text = ""
  for _, command in ipairs(commands) do
    help_text = help_text .. "- " .. command.name .. ": " .. (command.shorthelp or command.description) .. "\n"
  end
  return help_text
end

---@type {[AvanteSlashCommandBuiltInName]: AvanteSlashCommandCallback}
local callbacks = {
  help = function(sidebar, args, cb)
    -- includes user-configured and ACP agent commands, with precedence applied
    sidebar:update_content(get_help_text(require("avante.utils").get_commands()), { focus = false, scroll = false })
    if cb then cb(args) end
  end,
  clear = function(sidebar, args, cb) sidebar:clear_history(args, cb) end,
  new = function(sidebar, args, cb) sidebar:new_chat(args, cb) end,
  compact = function(sidebar, args, cb) sidebar:compact_history_messages(args, cb) end,
  init = function(sidebar, args, cb) sidebar:init_current_project(args, cb) end,
  lines = function(_, args, cb)
    if cb then cb(args) end
  end,
  commit = function(_, _, cb)
    local question = "Please commit the changes"
    if cb then cb(question) end
  end,
  model = function(_, _, cb)
    local Config = require("avante.config")
    local api = require("avante.api")
    if Config.acp_providers[Config.provider] then
      api.select_acp_model()
    else
      api.select_model()
    end
    if cb then cb("") end
  end,
  login = function(sidebar, args, cb)
    local Config = require("avante.config")
    local acp_provider = Config.acp_providers[Config.provider]
    local acp_client = type(sidebar) == "table" and sidebar.acp_client or nil
    local cmd, reason = M.resolve_login_command(Config.provider, acp_provider, acp_client, args)
    if not cmd then
      require("avante.utils").warn(reason or "/login is not available")
    else
      M.open_login_terminal(cmd, acp_provider and acp_provider.env or nil)
    end
    if cb then cb("") end
  end,
  plan = function(_, args, cb)
    local Config = require("avante.config")
    if not Config.acp_providers[Config.provider] then
      require("avante.utils").warn("/plan is only available with ACP providers (e.g. claude-code)")
    else
      local selector = require("avante.acp_config_selector")
      local mode = vim.trim(args or "")
      if mode ~= "" then
        selector.set_mode(mode)
      else
        selector.toggle_plan_mode()
      end
    end
    if cb then cb("") end
  end,
}

--- Built-in commands that keep acting locally even if an ACP agent advertises
--- a command with the same name.
---@type table<string, boolean>
M.LOCAL_PRECEDENCE = { clear = true, model = true, login = true }

---@param command AvanteSlashCommand
---@return boolean
function M.is_acp_command(command) return command.source == "acp" end

---Build the raw prompt text that is forwarded to an ACP agent for a command.
---@param name string
---@param args? string
---@return string
function M.format_acp_prompt(name, args)
  args = vim.trim(args or "")
  if args == "" then return "/" .. name end
  return "/" .. name .. " " .. args
end

---Convert an ACP `AvailableCommand` into an Avante slash command whose callback
---forwards the raw `/name args` text to the agent unchanged.
---@param command avante.acp.AvailableCommand
---@return AvanteSlashCommand
function M.from_acp_command(command)
  -- JSON `null` arrives as `vim.NIL` (a userdata), so type-check instead of
  -- relying on truthiness: newer shims send `input: null` for plain commands.
  local hint = type(command.input) == "table" and command.input.hint or nil
  if type(hint) ~= "string" or hint == "" then hint = nil end
  local description = type(command.description) == "string" and command.description or ""
  local details = description
  if hint then details = (details ~= "" and (details .. "\n") or "") .. "/" .. command.name .. " " .. hint end
  return {
    name = command.name,
    description = description,
    details = details,
    shorthelp = description ~= "" and description or nil,
    hint = hint,
    source = "acp",
    callback = function(_, args, cb)
      if cb then cb(M.format_acp_prompt(command.name, args)) end
    end,
  }
end

---Replace the ACP-sourced set of slash commands in `Config.slash_commands`.
---Previously registered ACP commands are dropped; user-configured commands are
---kept. Names listed in `M.LOCAL_PRECEDENCE` are skipped so the built-in
---implementation keeps handling them.
---@param commands avante.acp.AvailableCommand[]|nil
---@return AvanteSlashCommand[] registered ACP commands
function M.set_acp_commands(commands)
  local Config = require("avante.config")
  -- `Config` is a metatable proxy over `Config._options` without `__newindex`,
  -- so assigning `Config.slash_commands = ...` would create a shadow field.
  -- Mutate the existing table in place instead (other modules hold a
  -- reference to it as well).
  local slash_commands = Config.slash_commands
  if type(slash_commands) ~= "table" then
    slash_commands = {}
    Config._options.slash_commands = slash_commands
  end
  for i = #slash_commands, 1, -1 do
    if M.is_acp_command(slash_commands[i]) then table.remove(slash_commands, i) end
  end
  local registered = {}
  local seen = {}
  for _, command in ipairs(commands or {}) do
    if type(command.name) == "string" and command.name ~= "" and not M.LOCAL_PRECEDENCE[command.name] then
      if not seen[command.name] then
        seen[command.name] = true
        local slash_command = M.from_acp_command(command)
        table.insert(slash_commands, slash_command)
        table.insert(registered, slash_command)
      end
    end
  end
  return registered
end

---Drop every ACP-sourced slash command (e.g. when the agent session ends).
function M.clear_acp_commands() M.set_acp_commands({}) end

---@return AvanteSlashCommand[]
function M.get_acp_commands()
  local Config = require("avante.config")
  return vim.tbl_filter(M.is_acp_command, Config.slash_commands or {})
end

---@return AvanteSlashCommand[]
function M.get_builtin_commands()
  return vim
    .iter(builtin_commands)
    :map(
      ---@param command AvanteSlashCommand
      function(command)
        local command_ = vim.deepcopy(command)
        command_.callback = callbacks[command.name]
        return command_
      end
    )
    :totable()
end

return M

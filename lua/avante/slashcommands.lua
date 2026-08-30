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
--- built-in one: `/clear` and `/model` always act locally (they manage
--- Avante's own history / provider selection); every other name is handled
--- by the agent.
--- - `/plan [mode]`: toggle ACP plan mode (or switch to a specific ACP mode)
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
}

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
M.LOCAL_PRECEDENCE = { clear = true, model = true }

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
  local hint = command.input and command.input.hint or nil
  if hint == "" then hint = nil end
  local description = command.description or ""
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
  local kept = {}
  for _, command in ipairs(Config.slash_commands or {}) do
    if not M.is_acp_command(command) then table.insert(kept, command) end
  end
  local registered = {}
  local seen = {}
  for _, command in ipairs(commands or {}) do
    if type(command.name) == "string" and command.name ~= "" and not M.LOCAL_PRECEDENCE[command.name] then
      if not seen[command.name] then
        seen[command.name] = true
        local slash_command = M.from_acp_command(command)
        table.insert(kept, slash_command)
        table.insert(registered, slash_command)
      end
    end
  end
  Config.slash_commands = kept
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

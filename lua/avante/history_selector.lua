local History = require("avante.history")
local Utils = require("avante.utils")
local Path = require("avante.path")
local Config = require("avante.config")
local Selector = require("avante.ui.selector")
local ACPSessions = require("avante.acp_sessions")

---@class avante.HistorySelector
local M = {}

---Name of the ACP agent that produced the history (recorded on user submissions)
---@param messages avante.HistoryMessage[]
---@return string
local function history_agent_name(messages)
  for i = #messages, 1, -1 do
    local message = messages[i]
    if message.is_user_submission and type(message.provider) == "string" and message.provider ~= "" then
      return message.provider
    end
  end
  if Config.acp_providers[Config.provider] then return Config.provider end
  return "acp"
end

---Badge describing the ACP session bound to a history, or "" when none.
---@param history avante.ChatHistory
---@param messages avante.HistoryMessage[]
---@param project_root string
---@return string
function M.acp_badge(history, messages, project_root)
  local session_id = history.acp_session_id
  if type(session_id) ~= "string" or session_id == "" then return "" end
  local agent = history_agent_name(messages)
  local status
  if ACPSessions.find_session_file(session_id, project_root) then
    status = "resumable"
  else
    local sidebar = require("avante").get()
    local client = sidebar and sidebar.acp_client
    if client and client:supports_load_session() then
      status = "loadable"
    elseif client then
      status = "not resumable"
    else
      status = "no session file"
    end
  end
  return string.format("[ACP %s:%s %s] ", agent, ACPSessions.short_id(session_id), status)
end

---@param history avante.ChatHistory
---@param project_root string
---@return table?
local function to_selector_item(history, project_root)
  local messages = History.get_history_messages(history)
  local timestamp = #messages > 0 and messages[#messages].timestamp or history.timestamp
  local name = M.acp_badge(history, messages, project_root)
    .. history.title
    .. " - "
    .. timestamp
    .. " ("
    .. #messages
    .. ")"
  name = name:gsub("\n", "\\n")
  return {
    name = name,
    filename = history.filename,
  }
end

---@param bufnr integer
---@param cb fun(filename: string)
function M.open(bufnr, cb)
  local selector_items = {}

  local histories = Path.history.list(bufnr)
  local project_root = Utils.root.get({ buf = bufnr })

  for _, history in ipairs(histories) do
    table.insert(selector_items, to_selector_item(history, project_root))
  end

  if #selector_items == 0 then
    Utils.warn("No history items found.")
    return
  end

  local current_selector -- To be able to close it from the keymap

  current_selector = Selector:new({
    provider = Config.selector.provider, -- This should be 'native' for the current setup
    title = "Avante History (Select, then choose action)", -- Updated title
    items = vim
      .iter(selector_items)
      :map(
        function(item)
          return {
            id = item.filename,
            title = item.name,
          }
        end
      )
      :totable(),
    on_select = function(item_ids)
      if not item_ids then return end
      if #item_ids == 0 then return end
      cb(item_ids[1])
    end,
    get_preview_content = function(item_id)
      local history = Path.history.load(vim.api.nvim_get_current_buf(), item_id)
      local Sidebar = require("avante.sidebar")
      local content = Sidebar.render_history_content(history)
      return content, "markdown"
    end,
    on_delete_item = function(item_id_to_delete)
      if not item_id_to_delete then
        Utils.warn("No item ID provided for deletion.")
        return
      end
      Path.history.delete(bufnr, item_id_to_delete) -- bufnr from M.open's scope
    end,
    on_open = function() M.open(bufnr, cb) end,
  })
  current_selector:open()
end

return M

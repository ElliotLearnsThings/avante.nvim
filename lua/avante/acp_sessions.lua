---Discovery of Claude Code CLI sessions and a picker that attaches one of
---them to a new avante chat history via ACP `session/load`.
---
---Claude Code stores one transcript per session under
---`~/.claude/projects/<encoded cwd>/<sessionId>.jsonl` where the encoded cwd
---has every non-alphanumeric character replaced by `-`.
local M = {}

---@class avante.acp.CliSession
---@field session_id string
---@field path string absolute path to the .jsonl transcript
---@field cwd string|nil cwd recorded in the transcript
---@field summary string first user prompt (or stored summary), single line
---@field mtime integer unix mtime of the transcript file
---@field size integer file size in bytes

-- Maximum number of transcript lines scanned when looking for the first prompt
local MAX_SCAN_LINES = 400
-- Prefixes of user messages that are injected by the CLI rather than typed
local SYSTEM_USER_PREFIXES = {
  "<command-name>",
  "<command-message>",
  "<local-command-stdout>",
  "<local-command-caveat>",
  "<system-reminder>",
  "<ide_",
  "Caveat: The messages below",
}

---Encode a project directory the way Claude Code does for `~/.claude/projects`.
---@param cwd string
---@return string
function M.encode_project_dir(cwd)
  local encoded = cwd:gsub("[^A-Za-z0-9]", "-")
  return encoded
end

---@return string
function M.get_claude_config_dir()
  local dir = vim.env.CLAUDE_CONFIG_DIR
  if dir == nil or dir == "" then dir = vim.fs.joinpath(vim.uv.os_homedir(), ".claude") end
  return dir
end

---@return string
function M.get_projects_dir() return vim.fs.joinpath(M.get_claude_config_dir(), "projects") end

---Directory holding the transcripts for a project root
---@param cwd string
---@return string
function M.get_project_sessions_dir(cwd) return vim.fs.joinpath(M.get_projects_dir(), M.encode_project_dir(cwd)) end

---@param id string
---@return string
function M.short_id(id)
  if type(id) ~= "string" then return "" end
  return id:sub(1, 8)
end

---@param s string
---@return string
local function to_single_line(s)
  s = s:gsub("%s+", " ")
  s = vim.trim(s)
  return s
end

---@param text string
---@return boolean
local function is_system_user_text(text)
  for _, prefix in ipairs(SYSTEM_USER_PREFIXES) do
    if text:sub(1, #prefix) == prefix then return true end
  end
  return false
end

---Extract the prompt text from a transcript `user` record, or nil when the
---record is a tool result / meta record.
---@param record table
---@return string|nil
function M.user_record_text(record)
  if record.type ~= "user" or record.isMeta then return nil end
  local message = record.message
  if type(message) ~= "table" or message.role ~= "user" then return nil end
  local content = message.content
  local text
  if type(content) == "string" then
    text = content
  elseif type(content) == "table" then
    local parts = {}
    for _, item in ipairs(content) do
      if type(item) == "table" and item.type == "text" and type(item.text) == "string" then
        table.insert(parts, item.text)
      elseif type(item) == "table" and item.type == "tool_result" then
        return nil
      end
    end
    text = table.concat(parts, "\n")
  end
  if text == nil or vim.trim(text) == "" then return nil end
  if is_system_user_text(text) then return nil end
  return text
end

---Parse the head of a transcript file.
---@param path string
---@return { session_id: string|nil, cwd: string|nil, summary: string|nil, first_prompt: string|nil }
function M.parse_session_file(path)
  local info = { session_id = nil, cwd = nil, summary = nil, first_prompt = nil }
  local fd = io.open(path, "r")
  if not fd then return info end
  local n = 0
  for line in fd:lines() do
    n = n + 1
    if n > MAX_SCAN_LINES then break end
    local ok, record = pcall(vim.json.decode, line)
    if ok and type(record) == "table" then
      if info.session_id == nil and type(record.sessionId) == "string" then info.session_id = record.sessionId end
      if info.cwd == nil and type(record.cwd) == "string" then info.cwd = record.cwd end
      if record.type == "summary" and type(record.summary) == "string" then info.summary = record.summary end
      if info.first_prompt == nil then
        local text = M.user_record_text(record)
        if text then info.first_prompt = text end
      end
      if info.session_id and info.cwd and info.first_prompt then break end
    end
  end
  fd:close()
  return info
end

---List Claude Code CLI sessions recorded for a project root, newest first.
---@param cwd string
---@return avante.acp.CliSession[]
function M.list_sessions(cwd)
  local dir = M.get_project_sessions_dir(cwd)
  local files = vim.fn.glob(vim.fs.joinpath(dir, "*.jsonl"), true, true)
  ---@type avante.acp.CliSession[]
  local sessions = {}
  for _, path in ipairs(files) do
    local stat = vim.uv.fs_stat(path)
    if stat and stat.type == "file" and stat.size > 0 then
      local info = M.parse_session_file(path)
      local session_id = info.session_id or vim.fn.fnamemodify(path, ":t:r")
      local summary = info.summary or info.first_prompt
      if summary then
        summary = to_single_line(summary)
        if #summary > 120 then summary = summary:sub(1, 117) .. "..." end
      end
      table.insert(sessions, {
        session_id = session_id,
        path = path,
        cwd = info.cwd,
        summary = summary or "(no prompt)",
        mtime = stat.mtime.sec,
        size = stat.size,
      })
    end
  end
  table.sort(sessions, function(a, b)
    if a.mtime ~= b.mtime then return a.mtime > b.mtime end
    return a.session_id < b.session_id
  end)
  return sessions
end

---Locate the transcript for a session id under the project root.
---@param session_id string
---@param cwd string
---@return string|nil path
function M.find_session_file(session_id, cwd)
  if type(session_id) ~= "string" or session_id == "" then return nil end
  if session_id:find("[/\\]") then return nil end
  local path = vim.fs.joinpath(M.get_project_sessions_dir(cwd), session_id .. ".jsonl")
  local stat = vim.uv.fs_stat(path)
  if stat and stat.type == "file" then return path end
  return nil
end

---@param mtime integer
---@return string
local function format_mtime(mtime) return os.date("%Y-%m-%d %H:%M", mtime) end

---@param session avante.acp.CliSession
---@return string
function M.format_session(session)
  return string.format("%s  %s  %s", format_mtime(session.mtime), M.short_id(session.session_id), session.summary)
end

---Open the picker for the current project and attach the chosen session to a
---fresh avante chat history.
---@param bufnr integer|nil
function M.open(bufnr)
  local Utils = require("avante.utils")
  local Config = require("avante.config")
  local Selector = require("avante.ui.selector")

  bufnr = bufnr or vim.api.nvim_get_current_buf()

  local acp_provider = Config.acp_providers[Config.provider]
  if not acp_provider then
    Utils.warn("Current provider '" .. tostring(Config.provider) .. "' is not an ACP provider; cannot load ACP sessions.")
    return
  end

  local project_root = Utils.root.get({ buf = bufnr })
  local sessions = M.list_sessions(project_root)
  if #sessions == 0 then
    Utils.warn("No Claude Code sessions found in " .. M.get_project_sessions_dir(project_root))
    return
  end

  local by_id = {}
  local items = {}
  for _, session in ipairs(sessions) do
    by_id[session.session_id] = session
    table.insert(items, { id = session.session_id, title = M.format_session(session) })
  end

  Selector:new({
    provider = Config.selector.provider,
    title = "Claude Code sessions (" .. project_root .. ")",
    items = items,
    on_select = function(item_ids)
      if not item_ids or #item_ids == 0 then return end
      local session = by_id[item_ids[1]]
      if session then M.attach_session(bufnr, session) end
    end,
    get_preview_content = function(item_id)
      local session = by_id[item_id]
      if not session then return "", "markdown" end
      local lines = {
        "# " .. session.summary,
        "",
        "- session: " .. session.session_id,
        "- updated: " .. format_mtime(session.mtime),
        "- cwd: " .. tostring(session.cwd),
        "- file: " .. session.path,
      }
      return table.concat(lines, "\n"), "markdown"
    end,
  }):open()
end

---Create a new avante history bound to `session.session_id` and ask the agent
---to load it. The agent replays the transcript via `session/update`.
---@param bufnr integer
---@param session avante.acp.CliSession
function M.attach_session(bufnr, session)
  local Utils = require("avante.utils")
  local Path = require("avante.path")

  vim.api.nvim_buf_call(bufnr, function()
    local Avante = require("avante")
    if not Avante.is_sidebar_open() then Avante.open_sidebar({}) end
    local sidebar = Avante.get()
    if not sidebar then
      Utils.error("Failed to open avante sidebar")
      return
    end
    if sidebar.is_generating then
      Utils.warn("Avante is still generating; wait for it to finish before loading another session.")
      return
    end
    if sidebar.acp_client and not sidebar.acp_client:supports_load_session() then
      Utils.error("The connected ACP agent does not advertise the loadSession capability; cannot resume " .. session.session_id)
      return
    end

    local history = Path.history.new(sidebar.code.bufnr)
    history.title = session.summary
    history.acp_session_id = session.session_id
    Path.history.save(sidebar.code.bufnr, history)

    sidebar.current_state = nil
    sidebar.expanded_message_uuids = {}
    sidebar.tool_message_positions = {}
    sidebar.current_tool_use_extmark_id = nil
    sidebar:update_content_with_history()
    sidebar:create_todos_container()
    sidebar:initialize_token_count()

    Utils.info("Loading Claude Code session " .. M.short_id(session.session_id) .. "...")
    -- An empty submission only (re)connects the ACP client; because the new
    -- history carries an acp_session_id unknown to the agent process, llm.lua
    -- issues session/load and the replayed transcript is rendered.
    sidebar:handle_submit("")
    vim.schedule(function() sidebar:focus_input() end)
  end)
end

return M

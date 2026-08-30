local Config = require("avante.config")
local Utils = require("avante.utils")

---@class avante.ACPConfigSelector
local M = {}

---Mode id used by Claude Code (via claude-agent-acp) for plan mode.
M.PLAN_MODE_ID = "plan"

---Mode to return to when leaving plan mode via `/plan` if we never observed a previous mode.
M.DEFAULT_MODE_ID = "default"

---Last non-plan mode observed before switching into plan mode, per sidebar.
---@type table<any, string>
local pre_plan_modes = setmetatable({}, { __mode = "k" })

---Apply a config option value on the ACP session, handling both the
---configOptions API and the legacy session/set_mode / set_model API.
---@param sidebar avante.Sidebar
---@param config_id string "mode" | "model" | any config id
---@param value string
---@param callback? fun(err: avante.acp.ACPError|nil)
function M.set_value(sidebar, config_id, value, callback)
  callback = callback or function() end
  local client = sidebar.acp_client
  if not client then
    callback({ code = -1, message = "ACP client is not initialized" })
    return
  end
  local session_id = sidebar.chat_history and sidebar.chat_history.acp_session_id
  if not session_id then
    callback({ code = -1, message = "ACP session is not initialized yet" })
    return
  end

  local function done(err)
    vim.schedule(function()
      if not err and sidebar:is_open() then sidebar:render_result() end
      callback(err)
    end)
  end

  if client._legacy_api then
    if config_id == "mode" then
      client:set_mode(session_id, value, function(_, err) done(err) end)
    elseif config_id == "model" then
      client:set_model(session_id, value, function(_, err) done(err) end)
    else
      done({ code = -1, message = "Unsupported config option: " .. config_id })
    end
  else
    client:set_config_option(session_id, config_id, value, function(_, err) done(err) end)
  end
end

---Run `fn` once the ACP session has config options available, kicking off
---session initialization if needed.
---@param sidebar avante.Sidebar
---@param category string used for warning messages
---@param fn fun()
local function with_config_options(sidebar, category, fn)
  if sidebar.acp_client and sidebar.acp_client.config_options then
    fn()
    return
  end

  sidebar:handle_submit("")

  local attempts = 0
  local timer = vim.uv.new_timer()
  if not timer then return end
  timer:start(
    200,
    200,
    vim.schedule_wrap(function()
      attempts = attempts + 1
      if sidebar.acp_client and sidebar.acp_client.config_options then
        timer:stop()
        timer:close()
        fn()
      elseif
        sidebar.acp_client
        and sidebar.acp_client:is_ready()
        and sidebar.chat_history
        and sidebar.chat_history.acp_session_id
        and not sidebar.acp_client.config_options
      then
        timer:stop()
        timer:close()
        Utils.warn("No " .. category .. " options available from " .. (Config.provider or "current") .. " ACP agent")
      elseif attempts > 50 then
        timer:stop()
        timer:close()
        Utils.warn("Timed out waiting for ACP session to initialize")
      end
    end)
  )
end

---@return avante.Sidebar|nil
local function get_acp_sidebar()
  if not Config.acp_providers[Config.provider] then
    Utils.warn("Current provider is not an ACP provider")
    return nil
  end

  local sidebar = require("avante").get(false)
  if not sidebar then
    Utils.warn("Please open the Avante sidebar first")
    return nil
  end
  return sidebar
end

---@param category string "model" | "mode"
---@param prompt_label string
function M.open(category, prompt_label)
  local sidebar = get_acp_sidebar()
  if not sidebar then return end

  local function show_selector()
    local client = sidebar.acp_client
    if not client or not client.config_options then
      Utils.warn("No ACP config options available")
      return
    end

    local items = {}
    local display = {}
    for _, opt in ipairs(client.config_options) do
      if opt.category == category and opt.options then
        for _, val in ipairs(opt.options) do
          local prefix = val.value == opt.currentValue and "* " or "  "
          local label = prefix .. val.name
          if val.description then label = label .. " - " .. val.description end
          table.insert(display, label)
          table.insert(items, { config_id = opt.id, value = val.value })
        end
      end
    end

    if #items == 0 then
      Utils.warn("No " .. category .. " options available from " .. (Config.provider or "current") .. " ACP agent")
      return
    end

    vim.ui.select(display, { prompt = prompt_label }, function(_, idx)
      if not idx then return end

      local choice = items[idx]
      M.set_value(sidebar, choice.config_id, choice.value, function(err)
        if err then
          if choice.config_id == "model" and client._legacy_api then
            Utils.warn("Model switching is not supported by this ACP agent")
          else
            Utils.error("Failed: " .. (err.message or ""))
          end
          return
        end
        Utils.info("ACP " .. category .. " updated")
      end)
    end)
  end

  with_config_options(sidebar, category, show_selector)
end

function M.open_model() M.open("model", "ACP Agent Models> ") end

function M.open_mode() M.open("mode", "ACP Agent Modes> ") end

---Switch the ACP session mode to `mode_id`.
---@param mode_id string
---@param callback? fun(err: avante.acp.ACPError|nil)
function M.set_mode(mode_id, callback)
  local sidebar = get_acp_sidebar()
  if not sidebar then return end

  with_config_options(sidebar, "mode", function()
    local client = sidebar.acp_client
    local opt = client and client:get_mode_option()
    if not opt then
      Utils.warn("No mode options available from " .. (Config.provider or "current") .. " ACP agent")
      return
    end
    local valid = false
    for _, val in ipairs(opt.options or {}) do
      if val.value == mode_id then
        valid = true
        break
      end
    end
    if not valid then
      Utils.warn("Mode '" .. mode_id .. "' is not offered by the " .. (Config.provider or "current") .. " ACP agent")
      return
    end
    local current = client:get_current_mode()
    if current and current ~= M.PLAN_MODE_ID and mode_id == M.PLAN_MODE_ID then pre_plan_modes[sidebar] = current end
    M.set_value(sidebar, opt.id, mode_id, function(err)
      -- On success the agent emits current_mode_update, which llm.lua reports.
      if err then Utils.error("Failed to switch ACP mode: " .. (err.message or "")) end
      if callback then callback(err) end
    end)
  end)
end

---Toggle plan mode: enter plan mode if not in it, otherwise return to the
---mode that was active before plan mode (falling back to "default").
---@param callback? fun(err: avante.acp.ACPError|nil)
function M.toggle_plan_mode(callback)
  local sidebar = get_acp_sidebar()
  if not sidebar then return end

  with_config_options(sidebar, "mode", function()
    local client = sidebar.acp_client
    local current = client and client:get_current_mode()
    if current == M.PLAN_MODE_ID then
      M.set_mode(pre_plan_modes[sidebar] or M.DEFAULT_MODE_ID, callback)
    else
      M.set_mode(M.PLAN_MODE_ID, callback)
    end
  end)
end

return M

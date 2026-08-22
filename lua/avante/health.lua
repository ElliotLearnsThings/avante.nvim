local M = {}
local H = require("vim.health")
local Utils = require("avante.utils")
local Config = require("avante.config")

function M.check()
  H.start("avante.nvim")

  -- Required dependencies with their module names
  local required_plugins = {
    ["plenary.nvim"] = {
      path = "nvim-lua/plenary.nvim",
      module = "plenary",
    },
    ["nui.nvim"] = {
      path = "MunifTanjim/nui.nvim",
      module = "nui.popup",
    },
  }

  for name, plugin in pairs(required_plugins) do
    if Utils.has(name) or Utils.has(plugin.module) then
      H.ok(string.format("Found required plugin: %s", plugin.path))
    else
      H.error(string.format("Missing required plugin: %s", plugin.path))
    end
  end

  -- Optional dependencies
  if Utils.icons_enabled() then
    H.ok("Found icons plugin (nvim-web-devicons or mini.icons)")
  else
    H.warn("No icons plugin found (nvim-web-devicons or mini.icons). Icons will not be displayed")
  end

  -- Check input UI provider
  local input_provider = Config.input and Config.input.provider or "native"
  if input_provider == "dressing" then
    Utils.warn(
      "The 'dressing' provider is deprecated. Update your config 'input.provider' to 'native' for instance (see "
    )

    if Utils.has("dressing.nvim") or Utils.has("dressing") then
      H.ok("Found configured input provider: dressing.nvim")
    else
      H.error("Input provider is set to 'dressing' but dressing.nvim is not installed")
    end
  elseif input_provider == "snacks" then
    if Utils.has("snacks.nvim") or Utils.has("snacks") then
      H.ok("Found configured input provider: snacks.nvim")
    else
      H.error("Input provider is set to 'snacks' but snacks.nvim is not installed")
    end
  else
    H.ok("Using native input provider (no additional dependencies required)")
  end

  -- Check the Claude Code CLI and the Python interpreter its adapter needs
  M.check_claude_code()

  -- Check TreeSitter dependencies
  M.check_treesitter()
end

-- Check the Claude Code CLI and the Python interpreter running its adapter
function M.check_claude_code()
  local provider_conf = (Config.providers and Config.providers.claude_code) or {}

  local cli = provider_conf.cli_path
  if cli == nil or cli == "" then cli = "claude" end
  local cli_path = vim.fn.exepath(cli)
  if cli_path == "" and vim.fn.executable(cli) == 1 then cli_path = cli end
  if cli_path ~= "" then
    H.ok(string.format("Found Claude Code CLI: %s", cli_path))
  else
    H.error(
      string.format(
        "Claude Code CLI not found: %s. Install it from https://claude.com/claude-code, or set providers.claude_code.cli_path",
        cli
      )
    )
  end

  local python = provider_conf.python_path
  if python ~= nil and python ~= "" then
    local resolved = vim.fn.exepath(python)
    if resolved == "" and vim.fn.executable(python) == 1 then resolved = python end
    if resolved ~= "" then
      H.ok(string.format("Found Python interpreter: %s", resolved))
    else
      H.error(string.format("Configured providers.claude_code.python_path is not executable: %s", python))
    end
    return
  end

  local found_python = false
  for _, candidate in ipairs({ "python3", "python" }) do
    local resolved = vim.fn.exepath(candidate)
    if resolved ~= "" then
      H.ok(string.format("Found Python interpreter: %s", resolved))
      found_python = true
      break
    end
  end
  if not found_python then
    H.warn("No Python 3 interpreter found (tried python3, python). Set providers.claude_code.python_path")
    return
  end

  M.check_claude_code_auth(cli_path)
end

--- Report whether the Claude Code CLI is signed in
---
--- This shells out, so it is skipped when the CLI or Python is missing —
--- there would be nothing to ask.
---@param cli_path string
function M.check_claude_code_auth(cli_path)
  if cli_path == "" then return end
  local ok, logged_in, detail = pcall(require("avante.providers.claude_code").auth_status)
  if not ok then
    H.warn("Could not read Claude Code authentication status: " .. tostring(logged_in))
    return
  end
  if logged_in then
    H.ok(string.format("Claude Code is signed in: %s", detail))
  else
    H.error(string.format("Claude Code is not authenticated (%s). Run :AvanteClaudeCodeAuth", detail))
  end
end

-- Check TreeSitter functionality and parsers
function M.check_treesitter()
  H.start("TreeSitter Dependencies")

  -- List of important parsers for avante.nvim
  local essential_parsers = {
    "markdown",
  }

  local missing_parsers = {} ---@type string[]

  for _, parser_name in ipairs(essential_parsers) do
    local loaded_parser = vim.treesitter.language.add(parser_name)
    if not loaded_parser then missing_parsers[#missing_parsers + 1] = parser_name end
  end

  if #missing_parsers == 0 then
    H.ok("All essential TreeSitter parsers are installed")
  else
    H.warn(
      string.format(
        "Missing recommended parsers: %s. Install with :TSInstall %s",
        table.concat(missing_parsers, ", "),
        table.concat(missing_parsers, " ")
      )
    )
  end

  -- Check TreeSitter highlight
  local _, highlighter = pcall(require, "vim.treesitter.highlighter")
  if not highlighter then
    H.warn("TreeSitter highlighter not available. Syntax highlighting might be limited")
  else
    H.ok("TreeSitter highlighter is available")
  end
end

return M

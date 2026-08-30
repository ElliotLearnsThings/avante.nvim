local SlashCommands = require("avante.slashcommands")

describe("slashcommands", function()
  it("exposes a /plan builtin with a callback", function()
    local plan = vim.iter(SlashCommands.get_builtin_commands()):find(function(cmd) return cmd.name == "plan" end)
    assert.is_not_nil(plan)
    assert.is_not_nil(plan.callback)
    assert.is_string(plan.description)
  end)

  it("/plan warns and completes for non-ACP providers", function()
    local Config = require("avante.config")
    local Utils = require("avante.utils")
    local orig_provider, orig_acp = Config.provider, Config.acp_providers
    Config.provider = "openai"
    Config.acp_providers = {}
    local warned = nil
    local orig_warn = Utils.warn
    Utils.warn = function(msg) warned = msg end

    local plan = vim.iter(SlashCommands.get_builtin_commands()):find(function(cmd) return cmd.name == "plan" end)
    local cb_args = nil
    plan.callback(nil, "", function(args) cb_args = args end)

    Utils.warn = orig_warn
    Config.provider, Config.acp_providers = orig_provider, orig_acp

    assert.is_not_nil(warned)
    assert.equals("", cb_args)
  end)
end)

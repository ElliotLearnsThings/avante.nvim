local Config = require("avante.config")
local SlashCommands = require("avante.slashcommands")
local Utils = require("avante.utils")

describe("slashcommands ACP integration", function()
  before_each(function()
    Config.slash_commands = {
      { name = "mine", description = "user command", details = "user command" },
    }
  end)

  after_each(function() Config.slash_commands = {} end)

  it("tags agent commands with source = acp and keeps user commands", function()
    local registered = SlashCommands.set_acp_commands({
      { name = "context", description = "Show context usage", input = nil },
      { name = "compact", description = "Compact conversation", input = { hint = "[instructions]" } },
    })

    assert.equals(2, #registered)
    local names = vim.tbl_map(function(c) return c.name end, Config.slash_commands)
    assert.same({ "mine", "context", "compact" }, names)
    assert.is_nil(Config.slash_commands[1].source)
    assert.equals("acp", Config.slash_commands[2].source)
    assert.equals("acp", Config.slash_commands[3].source)
    assert.is_true(SlashCommands.is_acp_command(Config.slash_commands[3]))
    assert.is_false(SlashCommands.is_acp_command(Config.slash_commands[1]))
  end)

  it("replaces the previous ACP set instead of appending", function()
    SlashCommands.set_acp_commands({
      { name = "old-one", description = "from previous agent" },
      { name = "compact", description = "old compact" },
    })
    SlashCommands.set_acp_commands({
      { name = "compact", description = "new compact" },
      { name = "cost", description = "cost" },
    })

    local acp = SlashCommands.get_acp_commands()
    local names = vim.tbl_map(function(c) return c.name end, acp)
    assert.same({ "compact", "cost" }, names)
    assert.equals("new compact", acp[1].description)
    assert.equals("mine", Config.slash_commands[1].name)
    assert.equals(3, #Config.slash_commands)
  end)

  it("mutates Config.slash_commands in place (no shadow field on the proxy)", function()
    local ref = Config.slash_commands
    SlashCommands.set_acp_commands({ { name = "context", description = "" } })
    assert.equals(ref, Config.slash_commands)
    assert.equals(2, #ref)
    SlashCommands.clear_acp_commands()
    assert.equals(ref, Config.slash_commands)
    assert.equals(1, #ref)
    assert.equals("mine", ref[1].name)
  end)

  it("clears all ACP commands", function()
    SlashCommands.set_acp_commands({ { name = "context", description = "" } })
    SlashCommands.clear_acp_commands()
    assert.same({}, SlashCommands.get_acp_commands())
    assert.equals(1, #Config.slash_commands)
  end)

  it("handles a nil/empty update and duplicate names", function()
    SlashCommands.set_acp_commands(nil)
    assert.same({}, SlashCommands.get_acp_commands())
    SlashCommands.set_acp_commands({
      { name = "dup", description = "first" },
      { name = "dup", description = "second" },
      { name = "", description = "empty" },
    })
    local acp = SlashCommands.get_acp_commands()
    assert.equals(1, #acp)
    assert.equals("first", acp[1].description)
  end)

  it("uses input.hint in details and exposes it on the command", function()
    SlashCommands.set_acp_commands({
      { name = "model", description = "ignored" },
      { name = "compact", description = "Compact conversation", input = { hint = "[instructions]" } },
      { name = "context", description = "Show context", input = { hint = "" } },
    })
    local acp = SlashCommands.get_acp_commands()
    assert.equals("[instructions]", acp[1].hint)
    assert.equals("Compact conversation\n/compact [instructions]", acp[1].details)
    assert.is_nil(acp[2].hint)
    assert.equals("Show context", acp[2].details)
  end)

  it("callback forwards the raw /name args text unchanged", function()
    SlashCommands.set_acp_commands({
      { name = "compact", description = "", input = { hint = "[instructions]" } },
    })
    local cmd = SlashCommands.get_acp_commands()[1]
    local got
    cmd.callback(nil, "focus on the tests", function(prompt) got = prompt end)
    assert.equals("/compact focus on the tests", got)
    cmd.callback(nil, "", function(prompt) got = prompt end)
    assert.equals("/compact", got)
    cmd.callback(nil, nil, function(prompt) got = prompt end)
    assert.equals("/compact", got)
  end)

  describe("precedence", function()
    it("keeps /clear and /model local even when the agent advertises them", function()
      SlashCommands.set_acp_commands({
        { name = "clear", description = "agent clear" },
        { name = "model", description = "agent model", input = { hint = "[model]" } },
        { name = "compact", description = "agent compact" },
      })
      local acp_names = vim.tbl_map(function(c) return c.name end, SlashCommands.get_acp_commands())
      assert.same({ "compact" }, acp_names)

      local by_name = {}
      for _, c in ipairs(Utils.get_commands()) do
        by_name[c.name] = c
      end
      assert.is_nil(by_name.clear.source)
      assert.is_nil(by_name.model.source)
      assert.is_function(by_name.clear.callback)
      assert.is_function(by_name.model.callback)
    end)

    it("lets the agent win for other built-in names (e.g. /compact, /init)", function()
      SlashCommands.set_acp_commands({
        { name = "compact", description = "agent compact" },
        { name = "init", description = "agent init" },
      })
      local by_name = {}
      local seen = {}
      for _, c in ipairs(Utils.get_commands()) do
        assert.is_nil(seen[c.name], "duplicate command " .. c.name)
        seen[c.name] = true
        by_name[c.name] = c
      end
      assert.equals("acp", by_name.compact.source)
      assert.equals("agent compact", by_name.compact.description)
      assert.equals("acp", by_name.init.source)
      -- built-ins that the agent did not advertise are still there
      assert.is_nil(by_name.help.source)
      assert.is_nil(by_name.lines.source)
    end)
  end)
end)

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

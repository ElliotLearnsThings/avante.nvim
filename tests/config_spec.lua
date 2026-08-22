describe("config", function()
  local Config
  local previous_avante

  --- A second, user-defined provider. `claude_code` is the only built-in one,
  --- so tests that need two distinct providers bring their own.
  local function custom_provider() return { model = "custom-model", endpoint = "https://example.invalid" } end

  before_each(function()
    previous_avante = vim.g.avante
    package.loaded["avante.config"] = nil
    Config = require("avante.config")
    Config.get_last_used_model = function() end
  end)

  after_each(function()
    vim.g.avante = previous_avante
    package.loaded["avante.config"] = nil
  end)

  it("exposes the claude_code defaults when nothing is configured", function()
    Config.setup({})

    assert.are.same("claude_code", Config.provider)
    assert.are.same({}, Config.acp_providers)
    assert.are.same({ "claude_code" }, vim.tbl_keys(Config.providers))

    local claude_code = Config.providers.claude_code
    assert.are.same("sonnet", claude_code.model)
    assert.are.same({ "opus", "sonnet", "haiku" }, claude_code.model_names)
    assert.are.same("claude", claude_code.cli_path)
    assert.are.same("acceptEdits", claude_code.permission_mode)
    assert.is_true(claude_code.stateful)
    assert.is_true(claude_code.disable_tools)
  end)

  it("loads setup options from vim.g.avante", function()
    vim.g.avante = {
      provider = "custom_agent",
      providers = {
        custom_agent = custom_provider(),
      },
      behaviour = {
        auto_suggestions = true,
      },
    }

    Config.setup({})

    assert.are.same("custom_agent", Config.provider)
    assert.are.same("custom-model", Config.providers.custom_agent.model)
    assert.is_true(Config.behaviour.auto_suggestions)
    -- The built-in provider survives alongside a user-defined one.
    assert.are.same("sonnet", Config.providers.claude_code.model)
  end)

  it("merges user overrides into the claude_code defaults", function()
    Config.setup({
      providers = {
        claude_code = {
          model = "opus",
          permission_mode = "plan",
          allowed_tools = { "Read", "Grep" },
        },
      },
    })

    local claude_code = Config.providers.claude_code
    assert.are.same("opus", claude_code.model)
    assert.are.same("plan", claude_code.permission_mode)
    assert.are.same({ "Read", "Grep" }, claude_code.allowed_tools)
    -- Untouched defaults are kept rather than replaced wholesale.
    assert.are.same("claude", claude_code.cli_path)
    assert.are.same({ "opus", "sonnet", "haiku" }, claude_code.model_names)
    assert.is_true(claude_code.disable_tools)
  end)

  it("lets explicit setup options override vim.g.avante", function()
    vim.g.avante = {
      provider = "custom_agent",
      providers = {
        custom_agent = custom_provider(),
      },
      behaviour = {
        auto_suggestions = true,
      },
    }

    Config.setup({
      provider = "claude_code",
      behaviour = {
        auto_suggestions = false,
      },
    })

    assert.are.same("claude_code", Config.provider)
    assert.is_false(Config.behaviour.auto_suggestions)
  end)

  it("uses the last provider and model when no provider is configured", function()
    Config.get_last_used_model = function() return "alt-model", "custom_agent" end

    Config.setup({
      providers = {
        custom_agent = custom_provider(),
      },
      windows = {
        sidebar_header = {
          include_model = true,
        },
      },
    })

    assert.are.same("custom_agent", Config.provider)
    assert.are.same("alt-model", Config.providers.custom_agent.model)
    -- Switching providers must not rewrite the model of the one left behind.
    assert.are.same("sonnet", Config.providers.claude_code.model)
  end)

  it("does not let the last provider override an explicit setup provider", function()
    Config.get_last_used_model = function() return "alt-model", "custom_agent" end

    Config.setup({
      provider = "claude_code",
      providers = {
        custom_agent = custom_provider(),
      },
    })

    assert.are.same("claude_code", Config.provider)
    assert.are.same("sonnet", Config.providers.claude_code.model)
    assert.are.same("custom-model", Config.providers.custom_agent.model)
  end)

  it("does not let the last provider override vim.g.avante.provider", function()
    vim.g.avante = {
      provider = "claude_code",
      providers = {
        custom_agent = custom_provider(),
      },
    }
    Config.get_last_used_model = function() return "alt-model", "custom_agent" end

    Config.setup({})

    assert.are.same("claude_code", Config.provider)
    assert.are.same("sonnet", Config.providers.claude_code.model)
    assert.are.same("custom-model", Config.providers.custom_agent.model)
  end)

  it("applies the last used model to the provider that is already configured", function()
    Config.get_last_used_model = function() return "haiku", "claude_code" end

    Config.setup({
      windows = {
        sidebar_header = {
          include_model = true,
        },
      },
    })

    assert.are.same("claude_code", Config.provider)
    assert.are.same("haiku", Config.providers.claude_code.model)
  end)
end)

describe("providers", function()
  local Config
  local previous_avante
  local previous_avante_module

  before_each(function()
    previous_avante = vim.g.avante
    previous_avante_module = package.loaded["avante"]
    package.loaded["avante.config"] = nil
    package.loaded["avante.providers"] = nil

    Config = require("avante.config")
    Config.get_last_used_model = function() end
    Config.setup({
      provider = "test_http",
      providers = {
        test_http = {
          api_key_name = "",
          model = "http-test-model",
          parse_curl_args = function() end,
          setup = function() end,
        },
        test_alt = {
          api_key_name = "",
          model = "alt-test-model",
          parse_curl_args = function() end,
          setup = function() end,
        },
      },
      windows = {
        sidebar_header = {
          include_model = true,
        },
      },
    })
  end)

  after_each(function()
    vim.g.avante = previous_avante
    package.loaded["avante"] = previous_avante_module
    package.loaded["avante.config"] = nil
    package.loaded["avante.providers"] = nil
  end)

  it("redraws the sidebar header after switching providers", function()
    local rendered = 0
    package.loaded["avante"] = {
      get = function()
        return {
          is_open = function() return true end,
          render_result = function() rendered = rendered + 1 end,
        }
      end,
    }

    require("avante.providers").refresh("test_alt")

    assert.are.same("test_alt", Config.provider)
    assert.are.same(1, rendered)
  end)
end)

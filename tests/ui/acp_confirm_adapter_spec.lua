local ACPConfirmAdapter = require("avante.ui.acp_confirm_adapter")

describe("ACPConfirmAdapter", function()
  describe("map_acp_options", function()
    it("should ignore reject_always", function()
      local options = { { kind = "reject_always", optionId = "opt4" } }
      local result = ACPConfirmAdapter.map_acp_options(options)
      assert.is_nil(result.yes)
      assert.is_nil(result.all)
      assert.is_nil(result.no)
    end)

    it("should map multiple options correctly", function()
      local options = {
        { kind = "allow_once", optionId = "yes_id" },
        { kind = "allow_always", optionId = "all_id" },
        { kind = "reject_once", optionId = "no_id" },
        { kind = "reject_always", optionId = "ignored_id" },
      }
      local result = ACPConfirmAdapter.map_acp_options(options)
      assert.equals("yes_id", result.yes)
      assert.equals("all_id", result.all)
      assert.equals("no_id", result.no)
    end)

    it("should handle empty options", function()
      local options = {}
      local result = ACPConfirmAdapter.map_acp_options(options)
      assert.is_nil(result.yes)
      assert.is_nil(result.all)
      assert.is_nil(result.no)
    end)
  end)

  describe("generate_buttons_for_acp_options", function()
    it("should generate buttons with correct properties for each option kind", function()
      local options = {
        { kind = "allow_once", optionId = "opt1", name = "Allow" },
        { kind = "allow_always", optionId = "opt2", name = "Allow always" },
        { kind = "reject_once", optionId = "opt3", name = "Reject" },
        { kind = "reject_always", optionId = "opt4", name = "Reject always" },
      }
      local result = ACPConfirmAdapter.generate_buttons_for_acp_options(options)
      assert.equals(4, #result)

      for _, button in ipairs(result) do
        assert.is_not_nil(button.id)
        assert.is_not_nil(button.name)
        assert.is_not_nil(button.icon)
        assert.is_string(button.icon)

        if button.name == "Reject" or button.name == "Reject always" then
          assert.is_not_nil(button.hl)
        else
          assert.is_nil(button.hl)
        end
      end
    end)

    it("should handle multiple options and sort by name", function()
      local options = {
        { kind = "reject_once", optionId = "opt3", name = "Reject" },
        { kind = "allow_once", optionId = "opt1", name = "Allow" },
        { kind = "allow_always", optionId = "opt2", name = "Allow always" },
      }
      local result = ACPConfirmAdapter.generate_buttons_for_acp_options(options)
      assert.equals(3, #result)
      assert.equals("Allow", result[1].name)
      assert.equals("Allow always", result[2].name)
      assert.equals("Reject", result[3].name)
    end)

    it("should handle empty options", function()
      local options = {}
      local result = ACPConfirmAdapter.generate_buttons_for_acp_options(options)
      assert.equals(0, #result)
    end)

    it("should preserve all button properties", function()
      local options = {
        { kind = "allow_once", optionId = "id1", name = "Button 1" },
        { kind = "reject_once", optionId = "id2", name = "Button 2" },
      }
      local result = ACPConfirmAdapter.generate_buttons_for_acp_options(options)
      assert.equals(2, #result)
      for _, button in ipairs(result) do
        assert.is_not_nil(button.id)
        assert.is_not_nil(button.name)
        assert.is_not_nil(button.icon)
      end
    end)
  end)
end)

describe("ACPConfirmAdapter.map_acp_option_labels", function()
  it("maps ExitPlanMode option labels consistently with map_acp_options", function()
    -- claude-agent-acp ExitPlanMode options (non-root: bypassPermissions is prepended)
    local options = {
      { kind = "allow_always", name = "Yes, and bypass permissions", optionId = "bypassPermissions" },
      { kind = "allow_always", name = "Yes, and auto-accept edits", optionId = "acceptEdits" },
      { kind = "allow_once", name = "Yes, and manually approve edits", optionId = "default" },
      { kind = "reject_once", name = "No, keep planning", optionId = "plan" },
    }
    local labels = ACPConfirmAdapter.map_acp_option_labels(options)
    local ids = ACPConfirmAdapter.map_acp_options(options)
    assert.equals("Yes, and manually approve edits", labels.yes)
    assert.equals("default", ids.yes)
    assert.equals("Yes, and auto-accept edits", labels.all)
    assert.equals("acceptEdits", ids.all)
    assert.equals("No, keep planning", labels.no)
    assert.equals("plan", ids.no)
  end)

  it("returns nil labels for missing kinds", function()
    local labels = ACPConfirmAdapter.map_acp_option_labels({ { kind = "reject_always", name = "x", optionId = "x" } })
    assert.is_nil(labels.yes)
    assert.is_nil(labels.all)
    assert.is_nil(labels.no)
  end)
end)

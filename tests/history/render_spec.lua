local Render = require("avante.history.render")
local Message = require("avante.history.message")

---@param lines avante.ui.Line[]
---@return string[]
local function to_text(lines)
  return vim.tbl_map(function(line) return tostring(line) end, lines)
end

---@param texts string[]
---@param pattern string
---@return boolean
local function any_matches(texts, pattern)
  for _, text in ipairs(texts) do
    if text:find(pattern, 1, true) then return true end
  end
  return false
end

---@param acp_tool_call table
---@param fields? table
---@return avante.HistoryMessage
local function acp_tool_message(acp_tool_call, fields)
  local message = Message:new("assistant", {
    type = "tool_use",
    id = acp_tool_call.toolCallId,
    name = acp_tool_call.kind or acp_tool_call.title,
    input = acp_tool_call.rawInput or {},
  }, { uuid = acp_tool_call.toolCallId })
  message.acp_tool_call = acp_tool_call
  for k, v in pairs(fields or {}) do
    message[k] = v
  end
  return message
end

---@param tool_use_id string
---@param is_error? boolean
---@return avante.HistoryMessage
local function tool_result_message(tool_use_id, is_error)
  return Message:new("assistant", {
    type = "tool_result",
    tool_use_id = tool_use_id,
    content = nil,
    is_error = is_error or false,
  })
end

local function text_content(text) return { { type = "content", content = { type = "text", text = text } } } end

describe("history.render ACP tool calls", function()
  describe("is_subagent_tool_call / is_plan_tool_call", function()
    it("detects Claude Code Task/Agent via acp_tool_name", function()
      local message = acp_tool_message(
        { toolCallId = "t1", title = "Explore repo", kind = "think", status = "pending" },
        { acp_tool_name = "Task" }
      )
      assert.is_true(Render.is_subagent_tool_call(message))
      assert.is_false(Render.is_plan_tool_call(message))
    end)

    it("falls back to think tool calls that received nested children", function()
      local message = acp_tool_message({ toolCallId = "t1", title = "Explore repo", kind = "think" })
      assert.is_false(Render.is_subagent_tool_call(message))
      message.acp_children = { { type = "text", text = "hi" } }
      assert.is_true(Render.is_subagent_tool_call(message))
    end)

    it("detects ExitPlanMode via kind switch_mode or tool name", function()
      local by_kind = acp_tool_message({ toolCallId = "p1", title = "Ready to code?", kind = "switch_mode" })
      assert.is_true(Render.is_plan_tool_call(by_kind))
      local by_name = acp_tool_message({ toolCallId = "p2", title = "x", kind = "other" }, { acp_tool_name = "ExitPlanMode" })
      assert.is_true(Render.is_plan_tool_call(by_name))
      local plain = acp_tool_message({ toolCallId = "p3", title = "ls", kind = "execute" })
      assert.is_false(Render.is_plan_tool_call(plain))
    end)
  end)

  describe("get_tool_display_name", function()
    it("prefixes subagent and plan tool calls", function()
      local subagent = acp_tool_message(
        { toolCallId = "t1", title = "Explore repo", kind = "think", rawInput = { description = "Explore repo" } },
        { acp_tool_name = "Task" }
      )
      assert.equals("Subagent: Explore repo", (Render.get_tool_display_name(subagent)))

      local plan = acp_tool_message({
        toolCallId = "p1",
        title = "Ready to code?",
        kind = "switch_mode",
        rawInput = { plan = "# Plan" },
      })
      assert.equals("Plan: Ready to code?", (Render.get_tool_display_name(plan)))
    end)

    it("still honours displayed_tool_name", function()
      local subagent = acp_tool_message(
        { toolCallId = "t1", title = "Explore repo", kind = "think" },
        { acp_tool_name = "Task", displayed_tool_name = "custom" }
      )
      assert.equals("custom", (Render.get_tool_display_name(subagent)))
    end)
  end)

  describe("subagent rendering", function()
    it("does not dispatch ACP 'think' tool calls to llm_tools/think", function()
      local message = acp_tool_message({
        toolCallId = "t1",
        title = "Explore repo",
        kind = "think",
        status = "pending",
        content = text_content("Find all specs"),
        rawInput = { description = "Explore repo", prompt = "Find all specs" },
      }, { acp_tool_name = "Task" })
      local lines = to_text(Render.message_to_lines(message, { message }, false))
      assert.is_true(#lines >= 2)
      assert.is_true(lines[1]:find("╭─", 1, true) ~= nil, lines[1])
      assert.is_true(lines[1]:find("Subagent: Explore repo", 1, true) ~= nil, lines[1])
      assert.is_true(lines[#lines]:find("╰─", 1, true) ~= nil, lines[#lines])
    end)

    it("renders prompt, nested tool calls, streamed text and status", function()
      local message = acp_tool_message({
        toolCallId = "t1",
        title = "Explore repo",
        kind = "think",
        status = "in_progress",
        content = text_content("Find all specs"),
        rawInput = { description = "Explore repo", prompt = "Find all specs", subagent_type = "Explore" },
      }, {
        acp_tool_name = "Task",
        acp_subagent_prompt = "Find all specs",
        acp_children = {
          { type = "text", text = "Looking around" },
          { type = "tool_call", tool_call = { toolCallId = "c1", title = "Find `tests` `*_spec.lua`", kind = "search", status = "completed" } },
          { type = "tool_call", tool_call = { toolCallId = "c2", title = "Read tests/a_spec.lua", kind = "read", status = "in_progress" } },
          { type = "thought", text = "hmm" },
        },
      })
      local lines = to_text(Render.message_to_lines(message, { message }, false))
      assert.is_true(any_matches(lines, "generating"))
      assert.is_true(any_matches(lines, "Agent: Explore"))
      assert.is_true(any_matches(lines, "Prompt:"))
      assert.is_true(any_matches(lines, "Find all specs"))
      assert.is_true(any_matches(lines, "Progress:"))
      assert.is_true(any_matches(lines, "│  Looking around"))
      assert.is_true(any_matches(lines, "├─  ✓ Find `tests` `*_spec.lua` "))
      assert.is_true(any_matches(lines, "├─  … Read tests/a_spec.lua "))
      assert.is_true(any_matches(lines, "│  > hmm"))
      -- no result section while still running
      assert.is_false(any_matches(lines, "Result:"))
    end)

    it("collapses long streamed text unless expanded", function()
      local text = "l1\nl2\nl3\nl4\nl5"
      local message = acp_tool_message(
        { toolCallId = "t1", title = "Explore repo", kind = "think", status = "in_progress" },
        { acp_tool_name = "Task", acp_children = { { type = "text", text = text } } }
      )
      local collapsed = to_text(Render.message_to_lines(message, { message }, false))
      assert.is_true(any_matches(collapsed, "earlier lines not shown"))
      assert.is_false(any_matches(collapsed, "│  l1"))
      assert.is_true(any_matches(collapsed, "│  l5"))

      local expanded = to_text(Render.message_to_lines(message, { message }, true))
      assert.is_false(any_matches(expanded, "earlier lines not shown"))
      assert.is_true(any_matches(expanded, "│  l1"))
    end)

    it("shows the final result once completed", function()
      local message = acp_tool_message({
        toolCallId = "t1",
        title = "Explore repo",
        kind = "think",
        status = "completed",
        content = text_content("Found 3 specs"),
        rawInput = { description = "Explore repo", prompt = "Find all specs" },
      }, { acp_tool_name = "Task", acp_subagent_prompt = "Find all specs" })
      local result = tool_result_message("t1")
      local lines = to_text(Render.message_to_lines(message, { message, result }, false))
      assert.is_true(any_matches(lines, "succeeded"))
      assert.is_true(any_matches(lines, "Result:"))
      assert.is_true(any_matches(lines, "Found 3 specs"))
    end)

    it("does not repeat the prompt as a result when content did not change", function()
      local message = acp_tool_message({
        toolCallId = "t1",
        title = "Explore repo",
        kind = "think",
        status = "completed",
        content = text_content("Find all specs"),
        rawInput = { description = "Explore repo", prompt = "Find all specs" },
      }, { acp_tool_name = "Task", acp_subagent_prompt = "Find all specs" })
      local lines = to_text(Render.message_to_lines(message, { message, tool_result_message("t1") }, false))
      assert.is_false(any_matches(lines, "Result:"))
    end)

    it("labels failures as errors", function()
      local message = acp_tool_message({
        toolCallId = "t1",
        title = "Explore repo",
        kind = "think",
        status = "failed",
        content = text_content("```\nboom\n```"),
      }, { acp_tool_name = "Task", acp_subagent_prompt = "Find all specs" })
      local lines = to_text(Render.message_to_lines(message, { message, tool_result_message("t1", true) }, false))
      assert.is_true(any_matches(lines, "failed"))
      assert.is_true(any_matches(lines, "Error:"))
      assert.is_true(any_matches(lines, "boom"))
    end)
  end)

  describe("plan rendering", function()
    local plan = "# Plan\n\n1. one\n2. two\n3. three\n4. four\n5. five\n6. six"

    it("renders the full plan without truncation while awaiting approval", function()
      local message = acp_tool_message({
        toolCallId = "p1",
        title = "Ready to code?",
        kind = "switch_mode",
        status = "pending",
        content = text_content(plan),
        rawInput = { plan = plan },
      }, { acp_tool_name = "ExitPlanMode", is_calling = true })
      local lines = to_text(Render.message_to_lines(message, { message }, false))
      assert.is_true(lines[1]:find("Plan: Ready to code?", 1, true) ~= nil, lines[1])
      assert.is_true(any_matches(lines, "# Plan"))
      assert.is_true(any_matches(lines, "6. six"))
      assert.is_false(any_matches(lines, "truncated"))
      assert.is_true(any_matches(lines, "Waiting for approval"))
    end)

    it("keeps the plan visible after rejection even though content became an error", function()
      local message = acp_tool_message({
        toolCallId = "p1",
        title = "Ready to code?",
        kind = "switch_mode",
        status = "failed",
        content = text_content("```\nUser rejected request to exit plan mode.\n```"),
        rawInput = { plan = plan },
      }, { acp_tool_name = "ExitPlanMode", acp_plan = plan })
      local lines = to_text(Render.message_to_lines(message, { message, tool_result_message("p1", true) }, false))
      assert.is_true(any_matches(lines, "6. six"))
      assert.is_true(any_matches(lines, "Plan rejected"))
    end)

    it("reports approval", function()
      local message = acp_tool_message({
        toolCallId = "p1",
        title = "Exited Plan Mode",
        kind = "switch_mode",
        status = "completed",
        rawInput = { plan = plan },
      }, { acp_tool_name = "ExitPlanMode", acp_plan = plan })
      local lines = to_text(Render.message_to_lines(message, { message, tool_result_message("p1") }, false))
      assert.is_true(lines[1]:find("Plan: Exited Plan Mode", 1, true) ~= nil, lines[1])
      assert.is_true(any_matches(lines, "Plan approved"))
    end)

    it("get_plan_text prefers acp_plan, then rawInput, then content", function()
      local from_content = acp_tool_message({ toolCallId = "p1", kind = "switch_mode", content = text_content("c") })
      assert.equals("c", Render.get_plan_text(from_content))
      local from_raw = acp_tool_message({ toolCallId = "p1", kind = "switch_mode", rawInput = { plan = "r" }, content = text_content("c") })
      assert.equals("r", Render.get_plan_text(from_raw))
      from_raw.acp_plan = "a"
      assert.equals("a", Render.get_plan_text(from_raw))
    end)
  end)
end)

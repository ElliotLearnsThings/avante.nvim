local ACPSessions = require("avante.acp_sessions")

describe("acp_sessions", function()
  describe("encode_project_dir", function()
    it("replaces path separators with dashes like Claude Code", function()
      assert.equals("-home-ellioth-Repos-avante-claude", ACPSessions.encode_project_dir("/home/ellioth/Repos/avante-claude"))
    end)

    it("replaces every non-alphanumeric character, including dots and underscores", function()
      assert.equals("-home-ellioth--config-hypr", ACPSessions.encode_project_dir("/home/ellioth/.config/hypr"))
      assert.equals(
        "-home-ellioth-Repos-hotel-automation--claude-worktrees-gsap-static-styling",
        ACPSessions.encode_project_dir("/home/ellioth/Repos/hotel-automation/.claude/worktrees/gsap-static-styling")
      )
      assert.equals("-tmp-my-proj-v1-0", ACPSessions.encode_project_dir("/tmp/my_proj v1.0"))
    end)
  end)

  describe("directories", function()
    local saved

    before_each(function() saved = vim.env.CLAUDE_CONFIG_DIR end)
    after_each(function() vim.env.CLAUDE_CONFIG_DIR = saved end)

    it("defaults to ~/.claude/projects", function()
      vim.env.CLAUDE_CONFIG_DIR = nil
      assert.equals(vim.fs.joinpath(vim.uv.os_homedir(), ".claude", "projects"), ACPSessions.get_projects_dir())
    end)

    it("honours CLAUDE_CONFIG_DIR", function()
      vim.env.CLAUDE_CONFIG_DIR = "/tmp/claude-cfg"
      assert.equals("/tmp/claude-cfg/projects/-work-app", ACPSessions.get_project_sessions_dir("/work/app"))
    end)
  end)

  describe("user_record_text", function()
    it("returns the prompt for string content", function()
      assert.equals("hello", ACPSessions.user_record_text({ type = "user", message = { role = "user", content = "hello" } }))
    end)

    it("joins text blocks and ignores tool results", function()
      local rec = { type = "user", message = { role = "user", content = { { type = "text", text = "a" }, { type = "text", text = "b" } } } }
      assert.equals("a\nb", ACPSessions.user_record_text(rec))
      local tool = {
        type = "user",
        message = { role = "user", content = { { type = "tool_result", tool_use_id = "x", content = "out" } } },
      }
      assert.is_nil(ACPSessions.user_record_text(tool))
    end)

    it("skips meta, non-user and CLI-injected records", function()
      assert.is_nil(ACPSessions.user_record_text({ type = "assistant", message = { role = "assistant", content = "x" } }))
      assert.is_nil(ACPSessions.user_record_text({ type = "user", isMeta = true, message = { role = "user", content = "x" } }))
      assert.is_nil(
        ACPSessions.user_record_text({ type = "user", message = { role = "user", content = "<command-name>/clear</command-name>" } })
      )
      assert.is_nil(ACPSessions.user_record_text({ type = "user", message = { role = "user", content = "   " } }))
    end)
  end)

  describe("session file discovery", function()
    local tmp
    local cwd = "/work/proj"
    local saved

    local function write(name, lines)
      local dir = ACPSessions.get_project_sessions_dir(cwd)
      vim.fn.mkdir(dir, "p")
      local path = vim.fs.joinpath(dir, name)
      local fd = assert(io.open(path, "w"))
      if #lines > 0 then fd:write(table.concat(lines, "\n"), "\n") end
      fd:close()
      return path
    end

    before_each(function()
      saved = vim.env.CLAUDE_CONFIG_DIR
      tmp = vim.fn.tempname()
      vim.env.CLAUDE_CONFIG_DIR = tmp
    end)

    after_each(function()
      vim.env.CLAUDE_CONFIG_DIR = saved
      vim.fn.delete(tmp, "rf")
    end)

    it("parses session id, cwd and the first real prompt", function()
      local path = write("11111111-aaaa-bbbb-cccc-000000000000.jsonl", {
        vim.json.encode({ type = "queue-operation", sessionId = "11111111-aaaa-bbbb-cccc-000000000000" }),
        vim.json.encode({ type = "user", isMeta = true, cwd = cwd, message = { role = "user", content = "meta" } }),
        vim.json.encode({ type = "user", cwd = cwd, message = { role = "user", content = "Fix the  login\nbug" } }),
        vim.json.encode({ type = "assistant", message = { role = "assistant", content = { { type = "text", text = "ok" } } } }),
      })
      local info = ACPSessions.parse_session_file(path)
      assert.equals("11111111-aaaa-bbbb-cccc-000000000000", info.session_id)
      assert.equals(cwd, info.cwd)
      assert.equals("Fix the  login\nbug", info.first_prompt)
      assert.is_nil(info.summary)
    end)

    it("prefers a stored summary over the first prompt", function()
      local path = write("s.jsonl", {
        vim.json.encode({ type = "summary", summary = "Login bug fix", leafUuid = "x" }),
        vim.json.encode({ type = "user", sessionId = "s", cwd = cwd, message = { role = "user", content = "Fix it" } }),
      })
      local info = ACPSessions.parse_session_file(path)
      assert.equals("Login bug fix", info.summary)
      assert.equals("Fix it", info.first_prompt)
    end)

    it("lists sessions newest first with single-line summaries", function()
      local old = write("22222222-0000-0000-0000-000000000000.jsonl", {
        vim.json.encode({ type = "user", sessionId = "22222222-0000-0000-0000-000000000000", cwd = cwd, message = { role = "user", content = "old\nprompt" } }),
      })
      local new = write("33333333-0000-0000-0000-000000000000.jsonl", {
        vim.json.encode({ type = "user", sessionId = "33333333-0000-0000-0000-000000000000", cwd = cwd, message = { role = "user", content = "new prompt" } }),
      })
      write("empty.jsonl", {})
      write("not-a-session.txt", { "ignored" })
      vim.uv.fs_utime(old, 1000, 1000)
      vim.uv.fs_utime(new, 2000, 2000)

      local sessions = ACPSessions.list_sessions(cwd)
      assert.equals(2, #sessions)
      assert.equals("33333333-0000-0000-0000-000000000000", sessions[1].session_id)
      assert.equals("new prompt", sessions[1].summary)
      assert.equals(2000, sessions[1].mtime)
      assert.equals("22222222-0000-0000-0000-000000000000", sessions[2].session_id)
      assert.equals("old prompt", sessions[2].summary)
      assert.equals(new, sessions[1].path)
    end)

    it("falls back to the file name when no sessionId is recorded", function()
      write("44444444-0000-0000-0000-000000000000.jsonl", { vim.json.encode({ type = "user", message = { role = "user", content = "x" } }) })
      local sessions = ACPSessions.list_sessions(cwd)
      assert.equals(1, #sessions)
      assert.equals("44444444-0000-0000-0000-000000000000", sessions[1].session_id)
    end)

    it("returns an empty list for unknown projects", function()
      assert.same({}, ACPSessions.list_sessions("/nowhere/at/all"))
    end)

    it("finds a session transcript by id and rejects path traversal", function()
      local path = write("55555555-0000-0000-0000-000000000000.jsonl", { "{}" })
      assert.equals(path, ACPSessions.find_session_file("55555555-0000-0000-0000-000000000000", cwd))
      assert.is_nil(ACPSessions.find_session_file("missing", cwd))
      assert.is_nil(ACPSessions.find_session_file("../../etc/passwd", cwd))
      assert.is_nil(ACPSessions.find_session_file("", cwd))
      assert.is_nil(ACPSessions.find_session_file(nil, cwd))
    end)

    it("formats a list entry with time, short id and summary", function()
      local line = ACPSessions.format_session({ session_id = "abcdefgh-1234", summary = "hello", mtime = 0, path = "", size = 1 })
      assert.truthy(line:find("abcdefgh  hello", 1, true))
      assert.equals("abcdefgh", ACPSessions.short_id("abcdefgh-1234"))
    end)
  end)
end)

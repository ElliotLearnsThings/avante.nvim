<div align="center">
  <img alt="logo" width="120" src="https://github.com/user-attachments/assets/2e2f2a58-2b28-4d11-afd1-87b65612b2de" />
  <h1>avante.nvim</h1>
</div>

<p align="center">
  <a href="https://neovim.io/" target="_blank"><img src="https://img.shields.io/static/v1?style=flat-square&label=Neovim&message=v0.11%2b&logo=neovim&labelColor=282828&logoColor=8faa80&color=414b32" alt="Neovim: v0.11+" /></a>
  <a href="https://claude.com/claude-code" target="_blank"><img src="https://img.shields.io/static/v1?style=flat-square&label=engine&message=Claude%20Code%20CLI&logo=anthropic&labelColor=282828&logoColor=d97757&color=a8563a" alt="Engine: Claude Code CLI" /></a>
  <a href="https://github.com/ElliotLearnsThings/avante.nvim/actions/workflows/tests.yaml" target="_blank"><img src="https://img.shields.io/github/actions/workflow/status/ElliotLearnsThings/avante.nvim/tests.yaml?style=flat-square&logo=lua&logoColor=c7c7c7&label=Lua+CI&labelColor=1E40AF&color=347D39&event=push" alt="Lua CI status" /></a>
  <a href="https://github.com/ElliotLearnsThings/avante.nvim/actions/workflows/rust.yaml" target="_blank"><img src="https://img.shields.io/github/actions/workflow/status/ElliotLearnsThings/avante.nvim/rust.yaml?style=flat-square&logo=rust&logoColor=ffffff&label=Rust+CI&labelColor=BC826A&color=347D39&event=push" alt="Rust CI status" /></a>
  <a href="https://github.com/ElliotLearnsThings/avante.nvim/actions/workflows/pre-commit.yaml" target="_blank"><img src="https://img.shields.io/github/actions/workflow/status/ElliotLearnsThings/avante.nvim/pre-commit.yaml?style=flat-square&logo=pre-commit&logoColor=ffffff&label=pre-commit&labelColor=FAAF3F&color=347D39&event=push" alt="pre-commit status" /></a>
  <a href="https://github.com/yetone/avante.nvim" target="_blank"><img src="https://img.shields.io/static/v1?style=flat-square&label=fork%20of&message=yetone/avante.nvim&logo=github&labelColor=282828&logoColor=ffffff&color=6f42c1" alt="Fork of yetone/avante.nvim" /></a>
</p>

**avante.nvim** 是一个 Neovim 插件，旨在模拟 [Cursor](https://www.cursor.com) AI IDE 的行为。它为用户提供 AI 驱动的代码建议，并能够轻松地将这些建议直接应用到源文件中。

**本仓库是一个分支。** 它保留了上述全部能力，只是换掉了底层引擎：不再访问十几个 HTTP 模型 API，而是驱动**原生的 [Claude Code CLI](https://claude.com/claude-code)**，并通过 MCP 桥接把 avante 自己的工具交还给它，让这些工具仍旧在 Neovim 内部执行。

[View in English](README.md)

> [!IMPORTANT]
>
> **`ElliotLearnsThings/avante.nvim` 是 [yetone/avante.nvim](https://github.com/yetone/avante.nvim) 的硬分支（hard fork），而不是它的超集。**
>
> 整个提供者层已经被替换成唯一的一个提供者 `claude_code`。`openai`、`claude`、`copilot`、
> `gemini`、`ollama`、`azure`、`bedrock`、`vertex`、`cohere`、`watsonx_code_assistant`
> 以及它们所有仅存在于配置中的别名都已被**移除**——为上游写的 `setup()` 配置在这里无法
> 工作。这里也没有 API 密钥需要配置：认证完全由 Claude Code CLI 负责。
>
> 安装之前请先阅读[关于本分支](#关于本分支)。

<https://github.com/user-attachments/assets/510e6270-b6cf-459d-9a2f-15b397d1fe53>

<https://github.com/user-attachments/assets/86140bfd-08b4-483d-a887-1b701d9e37dd>

## 关于本分支

上游 avante.nvim 通过 HTTP 访问模型，并为每一家厂商提供一个 provider。本分支把它们全部
移除，改用唯一的一个提供者 `claude_code`，直接驱动您已经装好的 Claude Code CLI：

- **由 CLI 跑完整轮对话。** avante 通过一个小巧、无第三方依赖的 Python 适配器
  （`py/claude-code-adapter`）启动 `claude --print`，并把结果流式送回侧边栏。您的
  Claude Code 订阅、`CLAUDE.md` 发现机制、skills、插件、MCP 服务器和权限模式都一并带过来。
- **avante 自己的工具依然在 Neovim 里执行。** 它们会以 MCP 服务器的形式重新提供给
  Claude Code，模型发起的调用被转发回编辑器，因此 diff 审阅、内联权限按钮、todos 容器、
  RAG 检索和 Web 搜索的行为都和以前完全一样。模型能调用哪一套工具由
  [工具模式 tools_mode](#工具模式-tools_mode) 决定。
- **没有 API 密钥。** 唯一涉及的凭据就是 `claude auth`，avante 永远不会向您索要密钥。

|              | 上游 `yetone/avante.nvim`                | 本分支                                                   |
| ------------ | ---------------------------------------- | -------------------------------------------------------- |
| 提供者       | 约 12 个 HTTP 提供者及其别名             | 只有一个：`claude_code`                                  |
| 凭据         | 每个提供者一份 API 密钥                  | `claude auth`，任何地方都不需要密钥                      |
| 传输         | 用 `curl` 访问 HTTP 端点                 | 子进程 → Python 适配器 → `claude --print`                 |
| 工具         | avante 的工具，在 Neovim 中执行          | avante 的工具、Claude Code 的工具，或两者——见 `tools_mode` |
| 斜杠命令     | 只有 avante 自己的                       | avante 的，外加 Claude Code 的命令、skills 和插件命令    |
| 会话         | 每轮都重发整个对话记录                   | 在多轮之间恢复 CLI 会话，保持提示词缓存有效              |
| ACP 智能体   | 默认带一个包装第三方 npm shim 的 `claude-code` 条目 | `acp_providers = {}`，需要时自行配置             |

除此之外的一切都来自上游，并且和过去一样在下文中有文档：侧边栏、键绑定、`avante.md`
项目说明、自定义工具、自定义提示词、MCP 支持以及 RAG 服务。

各部分如何拼在一起见[架构](#架构)一节；每一处改动背后的理由——包括那些被考虑过又被否决
的设计——记录在 [DECISIONS.md](./DECISIONS.md) 中。

## 功能

- **在 Neovim 中驱动原生 Claude Code**：每一轮都由真正的 `claude` 可执行文件执行，
  因此 CLI 在终端里能做的事，在侧边栏里同样能做。
- **avante 的工具被桥接回编辑器**：文件改动依旧会进入 avante 的 diff 审阅，可以内联
  接受或拒绝；确认流程、todos、RAG 检索和 Web 搜索也都照常工作。
- **AI 驱动的代码辅助**：与 AI 互动，询问有关当前代码文件的问题，并接收智能建议以进行改进或修改。
- **一键应用**：通过单个命令快速将 AI 的建议更改应用到源代码中，简化编辑过程并节省时间。
- **项目级说明文件**：在项目根目录放一个 markdown 文件（默认是 `avante.md`）即可定制 AI 的行为。
- **Claude Code 自己的扩展面**：它的斜杠命令、skills 和插件会和 avante 的一起出现在输入框中。
- **无需管理 API 密钥**：认证交给 CLI，并且会在多轮之间恢复会话，而不是重放整个对话记录。

## 赞助 ❤️

本分支能够存在，全靠 [yetone](https://github.com/yetone) 的工作。如果 avante.nvim 对您
有帮助，请考虑赞助上游作者——这里的一切都建立在他维护的插件之上：

[赞助 yetone](https://patreon.com/yetone)

## 安装

如果您希望从源代码构建二进制文件，则需要 `cargo`。否则，将使用 `curl` 和 `tar` 从 GitHub 获取预构建的二进制文件。

### 先决条件

请先按顺序完成下面三件事，其中没有任何一步需要 API 密钥。

1. **安装 Claude Code CLI**：从 <https://claude.com/claude-code> 安装，并确保 `claude`
   在 `$PATH` 中——`claude --version` 应该能给出回答。如果您把它放在了别的地方，请改用
   `providers.claude_code.cli_path` 指向它。
2. **登录一次**：在终端里执行 `claude auth login`，或者在插件装好之后执行
   `:AvanteClaudeCodeAuth`，它会在终端分屏中打开同一个交互式流程。`claude auth status`
   应当显示您已登录。这里没有 `ANTHROPIC_API_KEY` 需要导出，也不需要在 shell 配置里写
   任何东西；您在终端里 `claude` 能用什么，avante 就用什么。
3. **确保 `$PATH` 中有 Python 3.9 或更高版本**：自带的适配器（`py/claude-code-adapter`）
   只使用标准库编写——不需要 `pip install`，不需要创建虚拟环境，也不需要 `uv sync`。
   如果您的解释器不叫 `python3` 或 `python`，请设置
   `providers.claude_code.python_path`。

然后**从本分支**安装插件——是 `ElliotLearnsThings/avante.nvim`，不是
`yetone/avante.nvim`——插件管理器任选。需要 Neovim 0.11.0 或更高版本。

> [!TIP]
>
> 安装完成后，执行 `:AvanteClaudeCodeStatus`（或 `:checkhealth avante`）确认 CLI、Python
> 解释器和登录状态都在 avante 期待的位置上。

<details open>

  <summary><a href="https://github.com/folke/lazy.nvim">lazy.nvim</a> (推荐)</summary>

```lua
{
  "ElliotLearnsThings/avante.nvim",
  -- 如果您想从源代码构建，请执行 `make BUILD_FROM_SOURCE=true`
  -- ⚠️ 一定要加上这一行配置！！！！！
  build = vim.fn.has("win32") ~= 0
      and "powershell -ExecutionPolicy Bypass -File Build.ps1 -BuildFromSource false"
      or "make",
  event = "VeryLazy",
  version = false, -- 永远不要将此值设置为 "*"！永远不要！
  ---@module 'avante'
  ---@type avante.Config
  opts = {
    -- 在此处添加任何选项
    -- avante 通过 Claude Code CLI 工作，详见下方的“提供者”一节
    provider = "claude_code",
    providers = {
      claude_code = {
        model = "sonnet",
        tools_mode = "avante", -- avante 自己的工具，在 Neovim 内部执行
        permission_mode = "acceptEdits",
      },
    },
  },
  dependencies = {
    "nvim-lua/plenary.nvim",
    "MunifTanjim/nui.nvim",
    --- 以下依赖项是可选的，
    "echasnovski/mini.pick", -- 用于文件选择器提供者 mini.pick
    "nvim-telescope/telescope.nvim", -- 用于文件选择器提供者 telescope
    "hrsh7th/nvim-cmp", -- avante 命令和提及的自动完成
    "ibhagwan/fzf-lua", -- 用于文件选择器提供者 fzf
    "nvim-tree/nvim-web-devicons", -- 或 echasnovski/mini.icons
    {
      -- 支持图像粘贴
      "HakonHarnes/img-clip.nvim",
      event = "VeryLazy",
      opts = {
        -- 推荐设置
        default = {
          embed_image_as_base64 = false,
          prompt_for_file_name = false,
          drag_and_drop = {
            insert_mode = true,
          },
          -- Windows 用户必需
          use_absolute_path = true,
        },
      },
    },
    {
      -- 如果您有 lazy=true，请确保正确设置
      'MeanderingProgrammer/render-markdown.nvim',
      opts = {
        file_types = { "markdown", "Avante" },
      },
      ft = { "markdown", "Avante" },
    },
  },
}
```

</details>

<details>

  <summary>vim-plug</summary>

```vim

call plug#begin()

" 依赖项
Plug 'nvim-lua/plenary.nvim'
Plug 'MunifTanjim/nui.nvim'
Plug 'MeanderingProgrammer/render-markdown.nvim'

" 可选依赖项
Plug 'hrsh7th/nvim-cmp'
Plug 'nvim-tree/nvim-web-devicons' "或 Plug 'echasnovski/mini.icons'
Plug 'HakonHarnes/img-clip.nvim'
Plug 'folke/snacks.nvim' " 更现代的输入界面

" Yay，如果您想从源代码构建，请传递 source=true
Plug 'ElliotLearnsThings/avante.nvim', { 'branch': 'main', 'do': 'make' }

call plug#end()

autocmd! User avante.nvim lua << EOF
require('avante').setup()
EOF
```

</details>

<details>

  <summary><a href="https://github.com/echasnovski/mini.deps">mini.deps</a></summary>

```lua
local add, later, now = MiniDeps.add, MiniDeps.later, MiniDeps.now

add({
  source = 'ElliotLearnsThings/avante.nvim',
  monitor = 'main',
  depends = {
    'nvim-lua/plenary.nvim',
    'MunifTanjim/nui.nvim',
    'echasnovski/mini.icons'
  },
  hooks = { post_checkout = function() vim.cmd('make') end }
})
--- 可选
add({ source = 'hrsh7th/nvim-cmp' })
add({ source = 'HakonHarnes/img-clip.nvim' })
add({ source = 'MeanderingProgrammer/render-markdown.nvim' })

later(function() require('render-markdown').setup({...}) end)
later(function()
  require('img-clip').setup({...}) -- 配置 img-clip
  require("avante").setup({...}) -- 配置 avante.nvim
end)
```

</details>

<details>

  <summary><a href="https://github.com/wbthomason/packer.nvim">Packer</a></summary>

```vim

  -- 必需插件
  use 'nvim-lua/plenary.nvim'
  use 'MunifTanjim/nui.nvim'
  use 'MeanderingProgrammer/render-markdown.nvim'

  -- 可选依赖项
  use 'hrsh7th/nvim-cmp'
  use 'nvim-tree/nvim-web-devicons' -- 或使用 'echasnovski/mini.icons'
  use 'HakonHarnes/img-clip.nvim'

  -- Avante.nvim 带有构建过程
  use {
    'ElliotLearnsThings/avante.nvim',
    branch = 'main',
    run = 'make',
    config = function()
      require('avante').setup()
    end
  }
```

</details>

<details>

  <summary><a href="https://github.com/nix-community/home-manager">Home Manager</a></summary>

```nix
programs.neovim = {
  plugins = [
    {
      plugin = pkgs.vimPlugins.avante-nvim;
      type = "lua";
      config = ''
              require("avante").setup()
      '' # 或 builtins.readFile ./plugins/avante.lua;
    }
  ];
};
```

</details>

<details>

  <summary><a href="https://nix-community.github.io/nixvim/plugins/avante/index.html">Nixvim</a></summary>

```nix
  plugins.avante.enable = true;
  plugins.avante.settings = {
    # 在此处设置选项
  };
```

</details>

<details>

  <summary>Lua</summary>

```lua
-- 依赖项：
require('cmp').setup ({
  -- 使用上面的推荐设置
})
require('img-clip').setup ({
  -- 使用上面的推荐设置
})
require('render-markdown').setup ({
  -- 使用上面的推荐设置
})
require('avante').setup ({
  -- 在此处配置！
})
```

</details>

> [!IMPORTANT]
>
> `avante.nvim` 目前仅兼容 Neovim 0.10.1 或更高版本。请确保您的 Neovim 版本符合这些要求后再继续。

> [!NOTE]
>
> 在同步加载插件时，我们建议在您的配色方案之后的某个时间 `require` 它。

> [!NOTE]
>
> 推荐的 **Neovim** 选项：
>
> ```lua
> -- 视图只能通过全局状态栏完全折叠
> vim.opt.laststatus = 3
> ```

> [!TIP]
>
> 任何支持 markdown 的渲染插件都可以与 Avante 一起使用，只要您添加支持的文件类型 `Avante`。有关更多信息，请参见 <https://github.com/yetone/avante.nvim/issues/175> 和 [此评论](https://github.com/yetone/avante.nvim/issues/175#issuecomment-2313749363)。

### 默认设置配置

_请参见 [config.lua#L9](./lua/avante/config.lua) 以获取完整配置_

<details>
<summary>默认配置</summary>

```lua
{
  ---@type avante.ProviderName
  provider = "claude_code", -- 唯一内置的提供者：原生 Claude Code CLI
  ---@alias Mode "agentic" | "legacy"
  ---@type Mode
  mode = "agentic", -- 默认的交互模式。"agentic" 使用工具自动生成代码，"legacy" 使用旧的规划方式生成代码。
  -- ACP 智能体需要自行配置。原生的 Claude Code 提供者已经取代了旧的 `claude-code`
  -- ACP 条目，因此默认不提供任何 ACP 智能体。
  acp_providers = {},
  providers = {
    --- 唯一内置的提供者：原生 Claude Code CLI，通过 `py/claude-code-adapter` 中的
    --- Python 适配器驱动。详见下文的“提供者”一节。
    claude_code = {
      display_name = "Claude Code",
      model = "sonnet", -- 模型别名（"opus"、"sonnet"、"haiku"）或完整的模型名称
      model_names = { "opus", "sonnet", "haiku" }, -- `:AvanteModels` 中列出的模型
      cli_path = "claude", -- `claude` 可执行文件。裸名称会在 $PATH 中查找
      python_path = nil, -- 运行适配器的 Python 3.9+ 解释器。为 nil 时自动探测
      -- Claude Code 的行为尺度：
      -- "acceptEdits" | "plan" | "bypassPermissions" | "manual" | "dontAsk" | "auto"
      permission_mode = "acceptEdits",
      -- Claude Code 可以使用的内置工具。nil 表示使用它的默认工具集，空表则全部禁用
      tools = nil,
      allowed_tools = nil,
      disallowed_tools = nil,
      add_dirs = {}, -- 允许 Claude Code 访问的额外目录
      mcp_config = {}, -- MCP 服务器配置文件路径或 JSON 字符串
      strict_mcp_config = false, -- 忽略所有未在 `mcp_config` 中列出的 MCP 服务器
      -- Claude Code 插件，仅在本次会话中加载，叠加在 `claude plugin install`
      -- 已经全局安装好的插件之上
      plugin_dirs = {},
      plugin_urls = {},
      -- Claude Code 自己的斜杠命令会和 avante 的一起出现在输入框中。
      -- 设为 true 则只保留 avante 自己的
      disable_slash_commands = false,
      settings = nil, -- 设置文件路径或 JSON 字符串
      setting_sources = nil, -- 需要加载的设置来源
      agents = nil, -- 自定义 agent 定义，JSON 字符串
      effort = nil, -- 推理强度："low" | "medium" | "high" | "xhigh" | "max"
      fallback_model = nil, -- 主模型过载时回退使用的模型
      max_budget_usd = nil, -- 单轮对话的花费上限（美元）
      cwd = nil, -- Claude Code 的工作目录。默认为项目根目录
      -- 在多轮对话之间恢复 Claude Code 会话，而不是重放整个对话记录
      stateful = true,
      emit_tool_activity = true, -- 在侧边栏中显示 Claude Code 自己的工具调用与结果
      extra_args = {}, -- 原样追加到 CLI 调用后面的参数
      env = {}, -- 传给 CLI 的额外环境变量
      timeout = 0, -- 超过该毫秒数后中止本轮对话。0 表示不限制
      context_window = 200000,
      -- 模型可以调用谁的工具：
      --   "avante" -- avante 自己的工具，经 MCP 桥接在 Neovim 内部执行，
      --              diff 审阅、确认、todos、RAG 和 Web 搜索都照旧工作
      --   "native" -- Claude Code 的内置工具，直接把改动写入磁盘
      --   "both"   -- 两套都用，代价是能力互相重叠
      tools_mode = "avante",
      -- 与 `tools_mode` 保持一致：只有真的会有人调用时，avante 才构建工具列表。
      -- 使用 tools_mode = "native" 时请同时设为 true
      disable_tools = false,
    },
  },
  },
  ---指定特殊的 dual_boost 模式
  ---1. enabled: 是否启用 dual_boost 模式。默认为 false。
  ---2. first_provider: 第一个提供者用于生成响应。默认为 "claude_code"。
  ---3. second_provider: 第二个提供者用于生成响应。默认为 "claude_code"。
  ---4. prompt: 用于根据两个参考输出生成响应的提示。
  ---5. timeout: 超时时间（毫秒）。默认为 60000。
  ---工作原理：
  --- 启用 dual_boost 后，avante 将分别从 first_provider 和 second_provider 生成两个响应。然后使用 first_provider 的响应作为 provider1_output，second_provider 的响应作为 provider2_output。最后，avante 将根据提示和两个参考输出生成响应，默认提供者与正常情况相同。
  ---注意：这是一个实验性功能，可能无法按预期工作。
  dual_boost = {
    enabled = false,
    first_provider = "claude_code",
    second_provider = "claude_code",
    prompt = "根据以下两个参考输出，生成一个结合两者元素但反映您自己判断和独特视角的响应。不要提供任何解释，只需直接给出响应。参考输出 1: [{{provider1_output}}], 参考输出 2: [{{provider2_output}}]",
    timeout = 60000, -- 超时时间（毫秒）
  },
  behaviour = {
    auto_suggestions = false, -- 实验阶段
    auto_set_highlight_group = true,
    auto_set_keymaps = true,
    auto_apply_diff_after_generation = false,
    support_paste_from_clipboard = false,
    minimize_diff = true, -- 是否在应用代码块时删除未更改的行
    enable_token_counting = true, -- 是否启用令牌计数。默认为 true。
    auto_add_current_file = true, -- 打开新聊天时是否自动添加当前文件。默认为 true。
    ---@type "popup" | "inline_buttons"
    confirmation_ui_style = "inline_buttons",
  },
  mappings = {
    --- @class AvanteConflictMappings
    diff = {
      ours = "co",
      theirs = "ct",
      all_theirs = "ca",
      both = "cb",
      cursor = "cc",
      next = "]x",
      prev = "[x",
    },
    suggestion = {
      accept = "<M-l>",
      next = "<M-]>",
      prev = "<M-[>",
      dismiss = "<C-]>",
    },
    jump = {
      next = "]]",
      prev = "[[",
    },
    submit = {
      normal = "<CR>",
      insert = "<C-s>",
    },
    cancel = {
      normal = { "<C-c>", "<Esc>", "q" },
      insert = { "<C-c>" },
    },
    sidebar = {
      apply_all = "A",
      apply_cursor = "a",
      retry_user_request = "r",
      edit_user_request = "e",
      switch_windows = "<Tab>",
      reverse_switch_windows = "<S-Tab>",
      remove_file = "d",
      add_file = "@",
      close = { "<Esc>", "q" },
      close_from_input = nil, -- 例如，{ normal = "<Esc>", insert = "<C-d>" }
    },
  },
  selection = {
    enabled = true,
    hint_display = "delayed",
  },
  windows = {
    ---@type "right" | "left" | "top" | "bottom"
    position = "right", -- 侧边栏的位置
    wrap = true, -- 类似于 vim.o.wrap
    width = 30, -- 默认基于可用宽度的百分比
    sidebar_header = {
      enabled = true, -- true, false 启用/禁用标题
      align = "center", -- left, center, right 用于标题
      rounded = true,
    },
    spinner = {
      editing = { "⡀", "⠄", "⠂", "⠁", "⠈", "⠐", "⠠", "⢀", "⣀", "⢄", "⢂", "⢁", "⢈", "⢐", "⢠", "⣠", "⢤", "⢢", "⢡", "⢨", "⢰", "⣰", "⢴", "⢲", "⢱", "⢸", "⣸", "⢼", "⢺", "⢹", "⣹", "⢽", "⢻", "⣻", "⢿", "⣿" },
      generating = { "·", "✢", "✳", "∗", "✻", "✽" }, -- '生成中' 状态的旋转字符
      thinking = { "🤯", "🙄" }, -- '思考中' 状态的旋转字符
    },
    input = {
      prefix = "> ",
      height = 8, -- 垂直布局中输入窗口的高度
    },
    edit = {
      border = "rounded",
      start_insert = true, -- 打开编辑窗口时开始插入模式
    },
    ask = {
      floating = false, -- 在浮动窗口中打开 'AvanteAsk' 提示
      start_insert = true, -- 打开询问窗口时开始插入模式
      border = "rounded",
      ---@type "ours" | "theirs"
      focus_on_apply = "ours", -- 应用后聚焦的差异
    },
  },
  highlights = {
    ---@type AvanteConflictHighlights
    diff = {
      current = "DiffText",
      incoming = "DiffAdd",
    },
  },
  --- @class AvanteConflictUserConfig
  diff = {
    autojump = true,
    ---@type string | fun(): any
    list_opener = "copen",
    --- 覆盖悬停在差异上时的 'timeoutlen' 设置（请参阅 :help timeoutlen）。
    --- 有助于避免进入以 `c` 开头的差异映射的操作员挂起模式。
    --- 通过设置为 -1 禁用。
    override_timeoutlen = 500,
  },
  suggestion = {
    debounce = 600,
    throttle = 600,
  },
}
```

</details>

## 提供者

Avante 只有一个内置提供者：`claude_code`。它并不调用 HTTP API，而是通过插件自带的
一个小型 Python 适配器（`py/claude-code-adapter`）驱动**原生的 Claude Code CLI**。
适配器会运行 `claude --print --input-format stream-json --output-format stream-json`，
把 CLI 的整个 agent 循环合并成一条助手消息，再以 Anthropic Messages API 事件的形式
发出，因此侧边栏、聊天历史和 token 统计的行为都和以前完全一致。

在这个过程中 avante 自己的工具并没有被丢掉：它们会以一个 MCP 服务器的形式重新提供给
Claude Code，模型发起的每一次调用都会被转发回 Neovim，由 avante 的执行器在编辑器内
真正执行。详见下文的[工具模式 tools_mode](#工具模式-tools_mode)，以及[架构](#架构)
一节。

### 设置

完整的前置条件见[安装](#先决条件)一节，简单来说：

1. **安装 Claude Code CLI**：从 <https://claude.com/claude-code> 安装，然后执行一次
   `claude auth login`（或在 Neovim 中执行 `:AvanteClaudeCodeAuth`）登录。认证完全由
   CLI 负责：avante 既不会读取也不会提示输入 API 密钥，也不需要导出
   `ANTHROPIC_API_KEY`。如果该可执行文件不在 `$PATH` 中，请用 `cli_path` 指定它。
2. **确保 `$PATH` 中有 Python 3.9 或更高版本**：自带的适配器只使用标准库编写——不需要
   `pip install`，也不需要创建虚拟环境。如果您的解释器不叫 `python3` 或 `python`，
   请设置 `python_path`。

设置到此为止。即使 `require("avante").setup({})` 不带任何选项，也已经可以和
Claude Code 对话了；下面这段配置只是把默认值明确写出来，方便您看清自己拿到的是什么：

```lua
require("avante").setup({
  provider = "claude_code",
  providers = {
    claude_code = {
      model = "sonnet",
      tools_mode = "avante",
      permission_mode = "acceptEdits",
    },
  },
})
```

### 工具模式 tools_mode

这个插件里有两套完整的工具：avante 自己的工具（在 Neovim 内部执行）和 Claude Code 的
内置工具（在 CLI 进程中执行）。`tools_mode` 决定模型可以调用其中的哪一套。

| 取值       | 模型看到的工具               | 执行位置              | 您得到的体验                                                             |
| ---------- | ---------------------------- | --------------------- | ------------------------------------------------------------------------ |
| `"avante"` | 只有 avante 的工具（**默认**） | Neovim 内部，经 MCP 桥接 | diff 审阅、内联权限按钮、todos 容器、RAG 检索与 Web 搜索                 |
| `"native"` | 只有 Claude Code 的内置工具   | CLI 进程中            | Claude Code 自己的 Read/Edit/Write/Bash/Grep，直接把改动写入磁盘          |
| `"both"`   | 两套工具同时提供             | 两边都有              | 什么都能做，代价是同一件事有两种重叠的做法                               |

**`"avante"`——默认值。** avante 的工具 schema 会以 MCP 服务器的形式交给 Claude Code，
每一次 `tools/call` 都会被桥接回 Neovim，由真正的 Lua 工具执行。实际效果是：这个模式
让插件用起来仍然是 avante——文件改动会作为可审阅的 diff 出现在侧边栏，并且可以用快捷键
接受或拒绝；需要确认的工具会画出内联按钮；todos 容器会被填满；`@codebase`/RAG 检索和
Web 搜索也和以前一样工作。本轮对话中 Claude Code 自己的内置工具会被关闭——只要您没有自己
设置 `tools`，适配器就会传入 `--tools ""`——因此文件不会在您不知情的情况下被写入，也不会
有工具被执行两次。

**`"native"`。** Claude Code 使用自己的工具，**直接把改动写入磁盘**，并且只有在整轮
任务结束后才把结果返回给 avante。avante 的 diff 审阅不会拦在这些改动之前——响应到达时
文件其实已经被修改了，所以 `git` 和 `permission_mode` 才是您的安全网。作为交换，您得到
的正是 CLI 在终端里的行为：在大规模、机械性的重构上更快，而这也正是 Claude Code 自身
被调优的场景。使用该模式时请同时设置 `disable_tools = true`，免得 avante 白白花费提示
词 token 去描述永远不会被调用的工具。

**`"both"`。** 两套工具都提供。适合既想要 avante 可审阅的改动，又想用 Claude Code 自己
的 `Bash` 之类的场景。此时模型会有两种方式读文件、两种方式写文件，具体选哪一种由它自己
决定——因此行为会比只用其中一套时更难预测。

```lua
providers = {
  claude_code = {
    tools_mode = "avante", -- "avante" | "native" | "both"
    disable_tools = false, -- 仅在 tools_mode = "native" 时设为 true
  },
}
```

### 权限模式

`permission_mode` 会被原样传给 `claude --permission-mode`，所以以 CLI 自身的文档为准，
简单来说：

| 取值                | 行为                                                                       |
| ------------------- | -------------------------------------------------------------------------- |
| `acceptEdits`       | **默认值。** 文件改动直接应用，不再询问。                                  |
| `plan`              | 仅规划：Claude Code 只做调研并提出方案，不做任何修改。                     |
| `bypassPermissions` | 跳过所有权限检查。最快，也最危险——只建议在可丢弃或沙箱化的目录中使用。     |
| `manual`            | 不预先批准任何操作，每个动作都需要显式授权。                               |
| `dontAsk`           | Claude Code 不再弹出权限询问，直接继续执行。                               |
| `auto`              | 由 Claude Code 在执行过程中自行决定需要多少授权。                          |

它管的是 **Claude Code 自己的工具**，因此只有在 `tools_mode = "native"` 或 `"both"` 时
才真正起作用。在默认的 `tools_mode = "avante"` 下，这些内置工具本就被完全关闭，真正决定
一个动作能否发生的是 avante 自己的确认流程——内联权限按钮、diff 审阅，以及
`behaviour.auto_approve_tool_permissions`。

avante 以非交互方式驱动 CLI，因此那些本来会停下来询问的模式无法从侧边栏得到回答——
Claude Code 会直接拒绝该操作，而不是一直等待。这正是默认使用 `acceptEdits` 的原因。
如果您希望先看清一个请求会做什么，再决定是否落地，请从 `plan` 开始。

### 配置项

以下配置项都位于 `providers.claude_code` 下。最权威的清单是
[`lua/avante/config.lua`](./lua/avante/config.lua) 中的默认值。

| 配置项                   | 类型                   | 说明                                                                             |
| ------------------------ | ---------------------- | -------------------------------------------------------------------------------- |
| `model`                  | `string`               | 模型别名（`"opus"`、`"sonnet"`、`"haiku"`）或完整模型名称。默认 `"sonnet"`。      |
| `model_names`            | `string[]`             | `:AvanteModels` 中列出的模型。默认 `{ "opus", "sonnet", "haiku" }`。              |
| `display_name`           | `string`               | 在侧边栏和提供者选择器中显示的名称。默认 `"Claude Code"`。                        |
| `cli_path`               | `string`               | `claude` 可执行文件。裸名称会在 `$PATH` 中查找，路径则直接使用。默认 `"claude"`。 |
| `python_path`            | `string?`              | 运行适配器的解释器。未设置时会自动从 `python3`/`python` 探测。                    |
| `tools_mode`             | `string`               | 模型可以调用谁的工具：`"avante"`（默认）、`"native"` 或 `"both"`，见上文。        |
| `disable_tools`          | `boolean`              | 让 avante 干脆不构建工具列表。默认 `false`；配合 `tools_mode = "native"` 设为 `true`。 |
| `permission_mode`        | `string`               | Claude Code 自己的工具能有多大自由度，见上表。默认 `"acceptEdits"`。              |
| `tools`                  | `string[]?`            | Claude Code 可以使用的内置工具。`nil` 表示使用其默认工具集，`{}` 表示全部禁用。   |
| `allowed_tools`          | `string[]?`            | 显式允许的内置工具，例如只读会话可用 `{ "Read", "Grep", "Glob" }`。               |
| `disallowed_tools`       | `string[]?`            | 显式禁止的内置工具，例如 `{ "Bash" }`。                                          |
| `add_dirs`               | `string[]`             | 除 `cwd` 之外，允许 Claude Code 访问的额外目录。默认 `{}`。                       |
| `mcp_config`             | `string[]`             | MCP 服务器配置文件路径或 JSON 字符串，每一项对应一个 `--mcp-config`。默认 `{}`。  |
| `strict_mcp_config`      | `boolean`              | 忽略所有未在 `mcp_config` 中列出的 MCP 服务器。默认 `false`。                    |
| `plugin_dirs`            | `string[]`             | Claude Code 插件目录或 `.zip` 文件，仅在本次会话中加载。默认 `{}`。               |
| `plugin_urls`            | `string[]`             | Claude Code 插件 `.zip` 文件的 URL，仅在本次会话中加载。默认 `{}`。               |
| `disable_slash_commands` | `boolean`              | 只提供 avante 自己的斜杠命令，不提供 Claude Code 的。默认 `false`。              |
| `settings`               | `string?`              | Claude Code 的设置文件路径或 JSON 字符串。                                       |
| `setting_sources`        | `string?`              | CLI 需要加载的设置来源，例如 `"user,project,local"`。                             |
| `agents`                 | `string?`              | 自定义 agent 定义，JSON 字符串。                                                 |
| `effort`                 | `string?`              | 推理强度：`"low"`、`"medium"`、`"high"`、`"xhigh"` 或 `"max"`。                  |
| `fallback_model`         | `string?`              | 主模型过载时回退使用的模型。                                                     |
| `max_budget_usd`         | `number?`              | 单轮对话的花费上限（美元）。                                                     |
| `cwd`                    | `string?`              | Claude Code 的工作目录，它的工具都被限制在该目录内。默认为项目根目录。           |
| `stateful`               | `boolean`              | 在多轮之间恢复 Claude Code 会话，而不是重放整个对话记录。默认 `true`。           |
| `emit_tool_activity`     | `boolean`              | 在侧边栏中显示 Claude Code 自己的工具调用与结果。默认 `true`。                   |
| `append_system_prompt`   | `string?`              | 追加到系统提示词后面的文本，对应 `--append-system-prompt`。                       |
| `extra_args`             | `string[]`             | 原样追加到 CLI 调用后面的参数——用于承载这里没有建模的一切能力。                  |
| `env`                    | `table<string,string>` | 传给 CLI 进程的额外环境变量。默认 `{}`。                                          |
| `timeout`                | `number`               | 超过该**毫秒**数后中止本轮对话。默认 `0`，表示不限制。                            |
| `context_window`         | `integer`              | avante 统计 token 时使用的上下文长度。默认 `200000`。                            |

例如，一份依赖 Claude Code 自身工具的只读配置可以这样写：

```lua
providers = {
  claude_code = {
    model = "opus",
    tools_mode = "native",
    disable_tools = true,
    permission_mode = "plan",
    allowed_tools = { "Read", "Grep", "Glob" },
  },
}
```

### 原生斜杠命令

Claude Code 自己的斜杠命令——`/context`、`/compact`、您的 skills，以及各类插件提供的
命令——都会和 avante 自己的斜杠命令一起出现在 avante 的输入框中。输入其中之一时，文本
会被原样透传给 CLI 并由它解析，因此它们的行为与在终端会话中完全一致。

当同一个名字在两边都存在时，以 avante 的为准：avante 的 `/compact` 作用于 avante 这一
侧的对话，而这正是在侧边栏中输入它所要表达的意思。

CLI 会在每一轮对话开始时公布自己的命令列表，因此 avante 会从您的第一条消息中学到它，
并缓存到 `stdpath("cache")/avante/claude_code_capabilities.json`。此后每次启动时这些
命令都可以立即使用。设置 `disable_slash_commands = true`，则只提供 avante 自己的斜杠
命令。

### 插件

您用 `claude plugin install` 安装的插件会被自动识别。如果某个插件只想在 avante 会话中
加载——例如一个还在开发中的插件——把 `plugin_dirs` 或 `plugin_urls` 指向它即可：

```lua
providers = {
  claude_code = {
    plugin_dirs = { "~/src/my-plugin", "~/Downloads/reviewer.zip" },
    plugin_urls = { "https://example.com/plugins/linting.zip" },
  },
}
```

运行 `:AvanteClaudeCodeStatus` 即可查看当前生效的插件。

### 认证

这里没有需要设置的 API 密钥。Claude Code 自己完成认证，avante 直接复用 CLI 已有的会话：

```sh
claude auth login     # 或在 Neovim 中执行 :AvanteClaudeCodeAuth
claude auth status
```

`:AvanteClaudeCodeAuth` 会在一个终端分屏中打开交互式登录流程，因为登录需要一个真正的
TTY。`:AvanteClaudeCodeStatus` 会报告 CLI 版本、您的登录方式、已安装的插件，以及有多少
原生命令可用；`:checkhealth avante` 给出的信息也是一样的。两者背后都是适配器的 `--probe`
模式，它只调用可以在本地解析的 CLI 子命令——不会发起任何对话，也不会消耗 token。

## 架构

在一轮对话中 Neovim 从不使用 HTTP。`llm.lua` 会根据
`provider.transport == "subprocess"` 分支，由提供者构造一次进程调用而不是 curl 参数：
描述本次请求的一个 JSON 对象被写入适配器的 stdin，适配器则在 stdout 上写回 Anthropic
的 server-sent events。`parse_response` 之后的一切——agent 循环、历史记录、侧边栏渲染、
token 统计——都保持原样，因为收到的字节和 `api.anthropic.com` 会发出的字节完全相同。

适配器是一个只依赖标准库的 Python 程序。它把请求变成一条 `claude` 命令行，读取 CLI 的
`stream-json` NDJSON，并把实际上是*一整个 agent 循环*的输出（多条助手消息，每条都有
自己的 `message_start`/`message_stop`）合并成 avante 期待的那一条流式消息：重新编号
content block 索引、累加 usage，并从 CLI 最后的 `result` 记录合成唯一一组终止用的
`message_delta`/`message_stop`。

工具则沿着相反的方向流动。当 `tools_mode` 为 `"avante"` 或 `"both"` 时，avante 的工具
schema 会随请求一起送出；适配器通过 `--mcp-config` 给 Claude Code 挂上一个 MCP 服务器
（`mcp_server.py`）。这个服务器本身不含任何工具逻辑——它只是把 `tools/list` 和
`tools/call` 经由 Unix socket 转发给适配器，适配器随即发出 `avante_tool_call` 事件并
阻塞，直到 Neovim 从 stdin 回答。真正的 Lua 工具在编辑器里执行，这正是 diff 审阅、
权限询问和历史渲染依然有效的原因。

```
  ┌────────────────────────────────────────────────────────────────────┐
  │  Neovim —— 侧边栏 · 历史 · diff 审阅 · todos                       │
  │            avante.llm_tools（真正的 Lua 工具）                     │
  └──────────────┬──────────────────────────────────────▲──────────────┘
                 │ stdin：一个 JSON 请求，              │  stdout：Anthropic SSE
                 │ 其后每行一个工具结果                 │  （外加 avante_session、
                 │                                      │    avante_capabilities、
                 │                                      │    avante_tool_call）
  ┌──────────────▼──────────────────────────────────────┴──────────────┐
  │  py/claude-code-adapter —— 只依赖标准库的 Python                   │
  │    命令行构造 · StreamTranslator · bridge.py（Unix socket）        │
  └──────────────┬──────────────────────────────────────▲──────────────┘
                 │ claude --print                       │  stream-json NDJSON
                 │ --input-format stream-json           │
                 │ --output-format stream-json          │
  ┌──────────────▼──────────────────────────────────────┴──────────────┐
  │  claude —— 原生 Claude Code CLI                                    │
  └──────────────┬──────────────────────────────────────▲──────────────┘
                 │ stdio（JSON-RPC），由 CLI            │  工具的执行结果
                 │ 根据 --mcp-config 启动               │
  ┌──────────────▼──────────────────────────────────────┴──────────────┐
  │  mcp_server.py —— 不含工具逻辑，只有一条通往适配器的 socket        │
  └────────────────────────────────────────────────────────────────────┘

  桥接工具调用的完整路径 —— 请求向下走，结果原路返回：

    claude --stdio--> mcp_server --socket--> adapter --stdout--> Neovim
                                                     <--stdin---
```

这些取舍背后的理由——为什么用 Python 适配器而不是纯 Lua、为什么选择 Anthropic SSE 而不是
自定义协议、为什么走 MCP 而不是 ACP，以及一路上尝试过又被否决的方案——都记录在
[DECISIONS.md](./DECISIONS.md) 中。适配器自身的协议则记录在
[`py/claude-code-adapter/README.md`](./py/claude-code-adapter/README.md)。

## Blink.cmp 用户

对于 blink cmp 用户（nvim-cmp 替代品），请查看以下配置说明
这是通过使用 blink.compat 模拟 nvim-cmp 实现的
或者您可以使用 [Kaiser-Yang/blink-cmp-avante](https://github.com/Kaiser-Yang/blink-cmp-avante)。

<details>
  <summary>Lua</summary>

```lua
      selector = {
        --- @alias avante.SelectorProvider "native" | "fzf_lua" | "mini_pick" | "snacks" | "telescope" | fun(selector: avante.ui.Selector): nil
        provider = "fzf",
        -- 自定义提供者的选项覆盖
        provider_opts = {},
      }
```

要创建自定义选择器，您可以指定一个自定义函数来启动选择器以选择项目，并将选定的项目传递给 `on_select` 回调。

```lua
      selector = {
        ---@param selector avante.ui.Selector
        provider = function(selector)
          local items = selector.items ---@type avante.ui.SelectorItem[]
          local title = selector.title ---@type string
          local on_select = selector.on_select ---@type fun(selected_item_ids: string[]|nil): nil

          --- 在这里添加您的自定义选择器逻辑
        end,
      }
```

选择 native 以外的选择器，默认情况下目前存在问题
对于 lazyvim 用户，请从网站复制 blink.cmp 的完整配置或扩展选项

```lua
      compat = {
        "avante_commands",
        "avante_mentions",
        "avante_files",
      }
```

对于其他用户，只需添加自定义提供者

### 可用的补全项

Avante.nvim 提供了多个可以与 blink.cmp 集成的补全项：

#### 提及功能 (`@` 触发器)
提及功能允许您快速引用特定功能或将文件添加到聊天上下文：

- `@codebase` - 启用项目上下文和仓库映射
- `@diagnostics` - 启用诊断信息
- `@file` - 打开文件选择器以将文件添加到聊天上下文
- `@quickfix` - 将快速修复列表中的文件添加到聊天上下文
- `@buffers` - 将打开的缓冲区添加到聊天上下文

#### 斜杠命令 (`/` 触发器)
内置斜杠命令用于常见操作：

- `/help` - 显示可用命令的帮助信息
- `/init` - 基于当前项目初始化 AGENTS.md
- `/clear` - 清除聊天历史
- `/new` - 开始新聊天
- `/compact` - 压缩历史消息以节省令牌
- `/lines <start>-<end> <question>` - 询问特定行的问题
- `/commit` - 为更改生成提交消息

#### 快捷方式 (`#` 触发器)
快捷方式提供对预定义提示模板的快速访问。您可以在配置中自定义这些：

```lua
{
  shortcuts = {
    {
      name = "refactor",
      description = "使用最佳实践重构代码",
      details = "自动重构代码以提高可读性、可维护性，并遵循最佳实践，同时保持功能不变",
      prompt = "请按照最佳实践重构此代码，提高可读性和可维护性，同时保持功能不变。"
    },
    {
      name = "test",
      description = "生成单元测试",
      details = "创建全面的单元测试，涵盖边界情况、错误场景和各种输入条件",
      prompt = "请为此代码生成全面的单元测试，涵盖边界情况和错误场景。"
    },
    -- 添加更多自定义快捷方式...
  }
}
```

当您在输入中键入 `#refactor` 时，它将自动替换为相应的提示文本。

### 配置示例

以下是包含所有 Avante 源的完整 blink.cmp 配置示例：

```lua
      default = {
        ...
        "avante_commands",
        "avante_mentions",
        "avante_shortcuts",
        "avante_files",
      }
```

```lua
      providers = {
        avante_commands = {
          name = "avante_commands",
          module = "blink.compat.source",
          score_offset = 90, -- 显示优先级高于 lsp
          opts = {},
        },
        avante_files = {
          name = "avante_files",
          module = "blink.compat.source",
          score_offset = 100, -- 显示优先级高于 lsp
          opts = {},
        },
        avante_mentions = {
          name = "avante_mentions",
          module = "blink.compat.source",
          score_offset = 1000, -- 显示优先级高于 lsp
          opts = {},
        },
        avante_shortcuts = {
          name = "avante_shortcuts",
          module = "blink.compat.source",
          score_offset = 1000, -- 显示优先级高于 lsp
          opts = {},
        }
        ...
    }
```

</details>

## 用法

鉴于其早期阶段，`avante.nvim` 目前支持以下基本功能：

> [!IMPORTANT]
>
> 无需配置任何 API 密钥。avante 驱动的是 Claude Code CLI，认证由 CLI 自己完成——
> 在终端里执行一次 `claude auth login`，或在 Neovim 中执行 `:AvanteClaudeCodeAuth`
> 即可。完整的设置说明请参见[提供者](#提供者)一节，其中
> [工具模式 tools_mode](#工具模式-tools_mode) 决定一次改动是作为可审阅的 diff 出现在
> 侧边栏，还是直接落到磁盘上；`permission_mode` 则决定 Claude Code 自己的工具有多大
> 自由度。

1. 在 Neovim 中打开代码文件。
2. 使用 `:AvanteAsk` 命令查询 AI 关于代码的问题。
3. 查看 AI 的建议。
4. 通过简单的命令或按键绑定将推荐的更改直接应用到代码中。

**注意**：该插件仍在积极开发中，其功能和界面可能会发生重大变化。随着项目的发展，预计会有一些粗糙的边缘和不稳定性。

## 键绑定

以下键绑定可用于 `avante.nvim`：

| 键绑定                                    | 描述                          |
| ----------------------------------------- | ----------------------------- |
| <kbd>Leader</kbd><kbd>a</kbd><kbd>a</kbd> | 显示侧边栏                    |
| <kbd>Leader</kbd><kbd>a</kbd><kbd>t</kbd> | 切换侧边栏可见性              |
| <kbd>Leader</kbd><kbd>a</kbd><kbd>r</kbd> | 刷新侧边栏                    |
| <kbd>Leader</kbd><kbd>a</kbd><kbd>f</kbd> | 切换侧边栏焦点                |
| <kbd>Leader</kbd><kbd>a</kbd><kbd>?</kbd> | 选择模型                      |
| <kbd>Leader</kbd><kbd>a</kbd><kbd>e</kbd> | 编辑选定的块                  |
| <kbd>Leader</kbd><kbd>a</kbd><kbd>S</kbd> | 停止当前 AI 请求              |
| <kbd>c</kbd><kbd>o</kbd>                  | 选择我们的                    |
| <kbd>c</kbd><kbd>t</kbd>                  | 选择他们的                    |
| <kbd>c</kbd><kbd>a</kbd>                  | 选择所有他们的                |
| <kbd>c</kbd><kbd>0</kbd>                  | 选择无                        |
| <kbd>c</kbd><kbd>b</kbd>                  | 选择两者                      |
| <kbd>c</kbd><kbd>c</kbd>                  | 选择光标                      |
| <kbd>]</kbd><kbd>x</kbd>                  | 移动到上一个冲突              |
| <kbd>[</kbd><kbd>x</kbd>                  | 移动到下一个冲突              |
| <kbd>[</kbd><kbd>[</kbd>                  | 跳转到上一个代码块 (结果窗口) |
| <kbd>]</kbd><kbd>]</kbd>                  | 跳转到下一个代码块 (结果窗口) |

> [!NOTE]
>
> 如果您使用 `lazy.nvim`，那么此处的所有键映射都将安全设置，这意味着如果 `<leader>aa` 已经绑定，则 avante.nvim 不会绑定此映射。
> 在这种情况下，用户将负责设置自己的。有关更多详细信息，请参见 [关于键映射的说明](https://github.com/yetone/avante.nvim/wiki#keymaps-and-api-i-guess)。

### Neotree 快捷方式

在 neotree 侧边栏中，您还可以添加新的键盘快捷方式，以快速将 `file/folder` 添加到 `Avante Selected Files`。

<details>
<summary>Neotree 配置</summary>

```lua
return {
  {
    'nvim-neo-tree/neo-tree.nvim',
    config = function()
      require('neo-tree').setup({
        filesystem = {
          commands = {
            avante_add_files = function(state)
              local node = state.tree:get_node()
              local filepath = node:get_id()
              local relative_path = require('avante.utils').relative_path(filepath)

              local sidebar = require('avante').get()

              local open = sidebar:is_open()
              -- 确保 avante 侧边栏已打开
              if not open then
                require('avante.api').ask()
                sidebar = require('avante').get()
              end

              sidebar.file_selector:add_selected_file(relative_path)

              -- 删除 neo tree 缓冲区
              if not open then
                sidebar.file_selector:remove_selected_file('neo-tree filesystem [1]')
              end
            end,
          },
          window = {
            mappings = {
              ['oa'] = 'avante_add_files',
            },
          },
        },
      })
    end,
  },
}
```

</details>

## 命令

| 命令                               | 描述                                                                                     | 示例                                                |
| ---------------------------------- | ---------------------------------------------------------------------------------------- | --------------------------------------------------- |
| `:AvanteAsk [question] [position]` | 询问 AI 关于您的代码的问题。可选的 `position` 设置窗口位置和 `ask` 启用/禁用直接询问模式 | `:AvanteAsk position=right Refactor this code here` |
| `:AvanteBuild`                     | 构建项目的依赖项                                                                         |                                                     |
| `:AvanteChat`                      | 启动与 AI 的聊天会话，讨论您的代码库。默认情况下 `ask`=false                             |                                                     |
| `:AvanteClear`                     | 清除聊天记录                                                                             |                                                     |
| `:AvanteEdit`                      | 编辑选定的代码块                                                                         |                                                     |
| `:AvanteFocus`                     | 切换焦点到/从侧边栏                                                                      |                                                     |
| `:AvanteRefresh`                   | 刷新所有 Avante 窗口                                                                     |                                                     |
| `:AvanteStop`                      | 停止当前 AI 请求                                                                         |                                                     |
| `:AvanteSwitchProvider`            | 切换 AI 提供者——`claude_code`，或您自行配置的自定义/ACP 提供者                           | `:AvanteSwitchProvider claude_code`                 |
| `:AvanteShowRepoMap`               | 显示项目结构的 repo map                                                                  |                                                     |
| `:AvanteToggle`                    | 切换 Avante 侧边栏                                                                       |                                                     |
| `:AvanteModels`                    | 显示模型列表                                                                             |                                                     |
| `:AvanteClaudeCodeAuth`            | 在终端分屏中登录 Claude Code                                                             |                                                     |
| `:AvanteClaudeCodeStatus`          | 显示 Claude Code CLI 版本、认证状态、插件与原生命令                                      |                                                     |

## 高亮组

| 高亮组                      | 描述                       | 备注                                       |
| --------------------------- | -------------------------- | ------------------------------------------ |
| AvanteTitle                 | 标题                       |                                            |
| AvanteReversedTitle         | 用于圆角边框               |                                            |
| AvanteSubtitle              | 选定代码标题               |                                            |
| AvanteReversedSubtitle      | 用于圆角边框               |                                            |
| AvanteThirdTitle            | 提示标题                   |                                            |
| AvanteReversedThirdTitle    | 用于圆角边框               |                                            |
| AvanteConflictCurrent       | 当前冲突高亮               | 默认值为 `Config.highlights.diff.current`  |
| AvanteConflictIncoming      | 即将到来的冲突高亮         | 默认值为 `Config.highlights.diff.incoming` |
| AvanteConflictCurrentLabel  | 当前冲突标签高亮           | 默认值为 `AvanteConflictCurrent` 的阴影    |
| AvanteConflictIncomingLabel | 即将到来的冲突标签高亮     | 默认值为 `AvanteConflictIncoming` 的阴影   |
| AvantePopupHint             | 弹出菜单中的使用提示       |                                            |
| AvanteInlineHint            | 在可视模式下显示的行尾提示 |                                            |

有关更多信息，请参见 [highlights.lua](./lua/avante/highlights.lua)

## 自定义提供者

Avante 内置的提供者只有 `claude_code`，但您也可以创建自己的提供者：给它一个
`__inherited_from` 属性来继承已有的提供者，或者自己实现 `parse_curl_args`（HTTP 端点），
再或者像 `claude_code` 那样设置 `transport = "subprocess"` 并实现
`parse_subprocess_args`（本地进程）。

有关更多信息，请参见[自定义提供者](https://github.com/yetone/avante.nvim/wiki/Custom-providers)。

## ACP 支持

avante.nvim 支持 [Agent Client Protocol (ACP)](https://agentclientprotocol.com/overview/introduction)，
可以与遵循该协议的 AI 智能体协同工作。

`acp_providers` 默认为空。原生的 `claude_code` 提供者已经取代了旧的 `claude-code`
ACP 条目——后者依赖第三方 npm 封装 `claude-agent-acp`，而内置提供者直接和 `claude`
可执行文件对话，不再需要这层中转。

您仍然可以配置任意 ACP 智能体：

```lua
require("avante").setup({
  acp_providers = {
    ["gemini-cli"] = {
      command = "gemini",
      args = { "--experimental-acp" },
      env = {
        NODE_NO_WARNINGS = "1",
        GEMINI_API_KEY = os.getenv("GEMINI_API_KEY"),
      },
    },
  },
})
```

使用 `:AvanteSwitchProvider` 选择已配置的智能体。更多信息请参见 `:h avante-acp` 和
[自定义提供者](https://github.com/yetone/avante.nvim/wiki/Custom-providers)。

## RAG 服务

Avante 提供了一个 RAG 服务，这是一个用于获取 AI 生成代码所需上下文的工具。默认情况下，它未启用。您可以通过以下方式启用它：

```lua
  rag_service = { -- RAG 服务配置
    enabled = false, -- 启用 RAG 服务
    host_mount = os.getenv("HOME"), -- RAG 服务的主机挂载路径 (Docker 将挂载此路径)
    runner = "docker", -- RAG 服务的运行器 (可以使用 docker 或 nix)
    llm = { -- RAG 服务使用的语言模型 (LLM) 配置
      provider = "openai", -- LLM 提供者
      endpoint = "https://api.openai.com/v1", -- LLM API 端点
      api_key = "OPENAI_API_KEY", -- LLM API 密钥的环境变量名称
      model = "gpt-4o-mini", -- LLM 模型名称
      extra = nil, -- LLM 的额外配置选项
    },
    embed = { -- RAG 服务使用的嵌入模型配置
      provider = "openai", -- 嵌入提供者
      endpoint = "https://api.openai.com/v1", -- 嵌入 API 端点
      api_key = "OPENAI_API_KEY", -- 嵌入 API 密钥的环境变量名称
      model = "text-embedding-3-large", -- 嵌入模型名称
      extra = nil, -- 嵌入模型的额外配置选项
    },
    docker_extra_args = "", -- 传递给 docker 命令的额外参数
  },
```

RAG 服务可以单独设置llm模型和嵌入模型。在 `llm` 和 `embed` 配置块中，您可以设置以下字段：

- `provider`: 模型提供者（例如 "openai", "ollama", "dashscope"以及"openrouter"）
- `endpoint`: API 端点
- `api_key`: API 密钥的环境变量名称
- `model`: 模型名称
- `extra`: 额外的配置选项

有关不同模型提供商的详细配置，你可以在[这里](./py/rag-service/README.md)查看。

此外，RAG 服务还依赖于 Docker！（对于 macOS 用户，推荐使用 OrbStack 作为 Docker 的替代品）。

`host_mount` 是将挂载到容器的路径，默认是主目录。挂载是 RAG 服务访问主机机器中文件所必需的。用户可以决定是否要挂载整个 `/` 目录、仅项目目录或主目录。如果您计划使用 avante 和 RAG 事件处理存储在主目录之外的项目，您需要将 `host_mount` 设置为文件系统的根目录。

挂载将是只读的。

更改 rag_service 配置后，您需要手动删除 rag_service 容器以确保使用新配置：`docker rm -fv avante-rag-service`

## Web 搜索引擎

Avante 的工具包括一些 Web 搜索引擎，目前支持：

- [Tavily](https://tavily.com/)
- [SerpApi - Search API](https://serpapi.com/)
- Google's [Programmable Search Engine](https://developers.google.com/custom-search/v1/overview)
- [Kagi](https://help.kagi.com/kagi/api/search.html)
- [Brave Search](https://api-dashboard.search.brave.com/app/documentation/web-search/get-started)
- [SearXNG](https://searxng.github.io/searxng/)

默认是 Tavily，可以通过配置 `Config.web_search_engine.provider` 进行更改：

```lua
web_search_engine = {
  provider = "tavily", -- tavily, serpapi, google, kagi, brave 或 searxng
  proxy = nil, -- proxy support, e.g., http://127.0.0.1:7890
}
```

提供者所需的环境变量：

- Tavily: `TAVILY_API_KEY`
- SerpApi: `SERPAPI_API_KEY`
- Google:
  - `GOOGLE_SEARCH_API_KEY` 作为 [API 密钥](https://developers.google.com/custom-search/v1/overview)
  - `GOOGLE_SEARCH_ENGINE_ID` 作为 [搜索引擎](https://programmablesearchengine.google.com) ID
- Kagi: `KAGI_API_KEY` 作为 [API 令牌](https://kagi.com/settings?p=api)
- Brave Search: `BRAVE_API_KEY` 作为 [API 密钥](https://api-dashboard.search.brave.com/app/keys)
- SearXNG: `SEARXNG_API_URL` 作为 [API URL](https://docs.searxng.org/dev/search_api.html)

## 禁用工具

到底存在哪一套工具，是由[工具模式 tools_mode](#工具模式-tools_mode) 决定的。本节讲的是
另外两个开关：彻底关掉 avante 的工具机制，以及禁用单个工具。

`disable_tools` 是按提供者生效的，并且要和 `tools_mode` 保持一致。它决定 avante 是否为
一次请求构建工具列表，因此在默认的 `tools_mode = "avante"` 下必须保持 `false`——否则就
没有任何工具可以桥接给 Claude Code。当您改用 `tools_mode = "native"` 时，请把它设为
`true`，免得 avante 白白花费提示词 token 去描述永远不会被调用的工具：

```lua
providers = {
  claude_code = {
    tools_mode = "native", -- 由 Claude Code 自己的工具干活
    disable_tools = true,  -- 因此 avante 不必再提供自己的工具
  },
}
```

如果要限制 Claude Code 内置工具能做什么，请改用它的 `tools`、`allowed_tools` 和
`disallowed_tools` 配置项，参见[提供者](#提供者)一节。

同一个配置项也可以让自定义提供者彻底不使用工具：

```lua
providers = {
  my_provider = {
    -- ... 您自定义提供者的其余配置
    disable_tools = true, -- 禁用工具！
  },
}
```

如果您想在保留其余工具的前提下禁止某几个 avante 工具——对任何会使用它们的提供者都有效，
`claude_code` 也不例外——请在顶层的 `disabled_tools` 中列出它们（注意多了一个 `d`，这是
另一个配置项）：

```lua
{
  disabled_tools = { "python" },
}
```

工具列表

> rag_search, python, git_diff, git_commit, glob, search_keyword, read_file_toplevel_symbols,
> read_file, create_file, move_path, copy_path, delete_path, create_dir, bash, web_search, fetch

## 自定义工具

Avante 允许您定义自定义工具，AI 可以在代码生成和分析期间使用这些工具。这些工具可以执行 shell 命令、运行脚本或执行您需要的任何自定义逻辑。

### 示例：Go 测试运行器

<details>
<summary>以下是一个运行 Go 单元测试的自定义工具示例：</summary>

```lua
{
  custom_tools = {
    {
      name = "run_go_tests",  -- 工具的唯一名称
      description = "运行 Go 单元测试并返回结果",  -- 显示给 AI 的描述
      command = "go test -v ./...",  -- 要执行的 shell 命令
      param = {  -- 输入参数（可选）
        type = "table",
        fields = {
          {
            name = "target",
            description = "要测试的包或目录（例如 './pkg/...' 或 './internal/pkg'）",
            type = "string",
            optional = true,
          },
        },
      },
      returns = {  -- 预期返回值
        {
          name = "result",
          description = "获取的结果",
          type = "string",
        },
        {
          name = "error",
          description = "如果获取不成功的错误消息",
          type = "string",
          optional = true,
        },
      },
      func = function(params, on_log, on_complete)  -- 要执行的自定义函数
        local target = params.target or "./..."
        return vim.system({ "go", "test", "-v", target }, { text = true }):wait().stdout
      end,
    },
  },
}
```

</details>

## MCP

现在您可以通过 `mcphub.nvim` 为 Avante 集成 MCP 功能。有关详细文档，请参阅 [mcphub.nvim](https://ravitemer.github.io/mcphub.nvim/extensions/avante.html)

## 自定义提示

默认情况下，`avante.nvim` 提供三种不同的模式进行交互：`planning`、`editing` 和 `suggesting`，每种模式都有三种不同的提示。

- `planning`：与侧边栏上的 `require("avante").toggle()` 一起使用
- `editing`：与选定代码块上的 `require("avante").edit()` 一起使用
- `suggesting`：与 Tab 流上的 `require("avante").get_suggestion():suggest()` 一起使用。

用户可以通过 `Config.system_prompt` 或 `Config.override_prompt_dir` 自定义系统提示。

`Config.system_prompt` 允许您设置全局系统提示。我们建议根据您的需要在自定义 Autocmds 中调用此方法：

```lua
vim.api.nvim_create_autocmd("User", {
  pattern = "ToggleMyPrompt",
  callback = function() require("avante.config").override({system_prompt = "MY CUSTOM SYSTEM PROMPT"}) end,
})

vim.keymap.set("n", "<leader>am", function() vim.api.nvim_exec_autocmds("User", { pattern = "ToggleMyPrompt" }) end, { desc = "avante: toggle my prompt" })
```

`Config.override_prompt_dir` 允许您指定一个目录，其中包含您自己的自定义提示模板，这将覆盖内置模板。如果您想在 Neovim 配置之外维护一组自定义提示，这将非常有用。它可以是一个表示目录路径的字符串，也可以是一个返回表示目录路径的字符串的函数。

```lua
-- 示例：使用特定目录中的提示进行覆盖
require("avante").setup({
  override_prompt_dir = vim.fn.expand("~/.config/nvim/avante_prompts"),
})

-- 示例：使用函数（动态目录）中的提示进行覆盖
require("avante").setup({
  override_prompt_dir = function()
    -- 确定提示目录的逻辑
    return vim.fn.expand("~/.config/nvim/my_dynamic_prompts")
  end,
})
```

> [!WARNING]
>
> 如果您自定 `base.avanterules`，请一定要确保 `{% block custom_prompt %}{% endblock %}` 和 `{% block extra_prompt %}{% endblock %}` 存在，否则可能会导致整个插件无法使用。
> 如果您不清楚具体原因或者您不知道自己在干什么，请不要覆盖内置 prompt。内置 prompt 工作得非常好。

如果希望为每种模式自定义提示，`avante.nvim` 将根据给定缓冲区的项目根目录检查是否包含以下模式：`*.{mode}.avanterules`。

根目录层次结构的规则：

- lsp 工作区文件夹
- lsp root_dir
- 当前缓冲区的文件名的根模式
- cwd 的根模式

您还可以使用 `rules` 选项为您的 `avanterules` 文件配置自定义目录：

```lua
require('avante').setup({
  rules = {
    project_dir = '.avante/rules', -- 相对于项目根目录，也可以是绝对路径
    global_dir = '~/.config/avante/rules', -- 绝对路径
  },
})
```

加载优先级如下：

1.  `rules.project_dir`
2.  `rules.global_dir`
3.  项目根目录

<details>

  <summary>自定义提示的示例文件夹结构</summary>

如果您有以下结构：

```bash
.
├── .git/
├── typescript.planning.avanterules
├── snippets.editing.avanterules
├── suggesting.avanterules
└── src/

```

- `typescript.planning.avanterules` 将用于 `planning` 模式
- `snippets.editing.avanterules` 将用于 `editing` 模式
- `suggesting.avanterules` 将用于 `suggesting` 模式。

</details>

> [!important]
>
> `*.avanterules` 是一个 jinja 模板文件，将使用 [minijinja](https://github.com/mitsuhiko/minijinja) 渲染。有关如何扩展当前模板的示例，请参见 [templates](https://github.com/yetone/avante.nvim/blob/main/lua/avante/templates)。

## 集成

Avante.nvim 可以通过其扩展模块与其他插件协同工作。下面是一个将 Avante 与 nvim-tree 集成的示例，允许你直接从 NvimTree UI 中选择或取消选择文件：

```lua
{
    "ElliotLearnsThings/avante.nvim",
    event = "VeryLazy",
    keys = {
        {
            "<leader>a+",
            function()
                local tree_ext = require("avante.extensions.nvim_tree")
                tree_ext.add_file()
            end,
            desc = "Select file in NvimTree",
            ft = "NvimTree",
        },
        {
            "<leader>a-",
            function()
                local tree_ext = require("avante.extensions.nvim_tree")
                tree_ext.remove_file()
            end,
            desc = "Deselect file in NvimTree",
            ft = "NvimTree",
        },
    },
    opts = {
        --- 其他配置
        selector = {
            exclude_auto_select = { "NvimTree" },
        },
    },
}
```

## TODOs

- [x] 与当前文件聊天
- [x] 应用差异补丁
- [x] 与选定的块聊天
- [x] 斜杠命令
- [x] 编辑选定的块
- [x] 智能 Tab（Cursor 流）
- [x] 与项目聊天（您可以使用 `@codebase` 与整个项目聊天）
- [x] 与选定文件聊天
- [x] 工具使用
- [x] MCP
- [ ] 更好的代码库索引

## 路线图

- **增强的 AI 交互**：提高 AI 分析和建议的深度，以应对更复杂的编码场景。
- **LSP + Tree-sitter + LLM 集成**：与 LSP 和 Tree-sitter 以及 LLM 集成，以提供更准确和强大的代码建议和分析。

## 贡献

欢迎贡献代码。与 Claude Code 提供者、Python 适配器或 MCP 工具桥接相关的 issue 和 pull
request，请提交到[本分支](https://github.com/ElliotLearnsThings/avante.nvim)；其余的几乎
都属于上游，提交到 [yetone/avante.nvim](https://github.com/yetone/avante.nvim) 可以让所有
人受益。

如果您要修改 Claude Code 集成的工作方式，请先阅读 [DECISIONS.md](./DECISIONS.md)——里面
记录了哪些方案已经尝试过。

更多配方和技巧，请参见上游 [wiki](https://github.com/yetone/avante.nvim/wiki)。

## 致谢

### 上游项目：yetone/avante.nvim

本项目是 **[yetone/avante.nvim](https://github.com/yetone/avante.nvim)** 的一个分支，
并且是最直白意义上的衍生作品。侧边栏、diff 审阅、工具框架、历史与会话机制、模板系统、
Rust crates、与 Neovim 的整合——提供者层之下几乎每一行代码——都出自
[yetone](https://github.com/yetone) 以及 avante.nvim 的
[贡献者们](https://github.com/yetone/avante.nvim/graphs/contributors)之手。本分支改变的
只是「如何抵达模型」这一层；让这个插件值得使用的一切，在分叉之前就已经在那里了。

如果 avante.nvim 对您有帮助，请为[上游仓库](https://github.com/yetone/avante.nvim)点星、
赞助并贡献代码——插件是在那里维护的。凡是与 Claude Code 提供者无关的问题，几乎都属于上游，
最好也在那里提出。

### avante.nvim 自身参考过的项目

我们要向以下开源项目的贡献者表示衷心的感谢，他们的代码为 avante.nvim 的开发提供了宝贵的灵感和参考：

| Nvim 插件                                                             | 许可证            | 功能             | 位置                                                                                                                                   |
| --------------------------------------------------------------------- | ----------------- | ---------------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| [git-conflict.nvim](https://github.com/akinsho/git-conflict.nvim)     | 无许可证          | 差异比较功能     | [lua/avante/diff.lua](https://github.com/yetone/avante.nvim/blob/main/lua/avante/diff.lua)                                             |
| [ChatGPT.nvim](https://github.com/jackMort/ChatGPT.nvim)              | Apache 2.0 许可证 | 令牌计数的计算   | [lua/avante/utils/tokens.lua](https://github.com/yetone/avante.nvim/blob/main/lua/avante/utils/tokens.lua)                             |
| [img-clip.nvim](https://github.com/HakonHarnes/img-clip.nvim)         | MIT 许可证        | 剪贴板图像支持   | [lua/avante/clipboard.lua](https://github.com/yetone/avante.nvim/blob/main/lua/avante/clipboard.lua)                                   |
| [copilot.lua](https://github.com/zbirenbaum/copilot.lua)              | MIT 许可证        | Copilot 支持     | [lua/avante/providers/copilot.lua](https://github.com/yetone/avante.nvim/blob/main/lua/avante/providers/copilot.lua)                   |
| [jinja.vim](https://github.com/HiPhish/jinja.vim)                     | MIT 许可证        | 模板文件类型支持 | [syntax/jinja.vim](https://github.com/yetone/avante.nvim/blob/main/syntax/jinja.vim)                                                   |
| [codecompanion.nvim](https://github.com/olimorris/codecompanion.nvim) | MIT 许可证        | Secrets 逻辑支持 | [lua/avante/providers/init.lua](https://github.com/yetone/avante.nvim/blob/main/lua/avante/providers/init.lua)                         |
| [aider](https://github.com/paul-gauthier/aider)                       | Apache 2.0 许可证 | 规划模式用户提示 | [lua/avante/templates/planning.avanterules](https://github.com/yetone/avante.nvim/blob/main/lua/avante/templates/planning.avanterules) |

这些项目的源代码的高质量和独创性在我们的开发过程中提供了极大的帮助。我们向这些项目的作者和贡献者表示诚挚的感谢和敬意。正是开源社区的无私奉献推动了像 avante.nvim 这样的项目向前发展。

（上表原样保留自上游。其中指向的部分文件——例如 `lua/avante/providers/copilot.lua`——随着
本分支替换掉的提供者层一起被移除了；表中的链接指向上游仓库，那里依然存在，这份致谢也一样
成立。）

## 商业赞助商

以下公司赞助的是上游 avante.nvim：

<table>
  <tr>
    <td align="center">
      <a href="https://s.kiiro.ai/r/ylVbT6" target="_blank">
        <img height="80" src="https://github.com/user-attachments/assets/1abd8ede-bd98-4e6e-8ee0-5a661b40344a" alt="Meshy AI" /><br/>
        <strong>Meshy AI</strong>
        <div>&nbsp;</div>
        <div>为创作者提供的 #1 AI 3D 模型生成器</div>
      </a>
    </td>
    <td align="center">
      <a href="https://s.kiiro.ai/r/mGPJOd" target="_blank">
        <img height="80" src="https://github.com/user-attachments/assets/7b7bd75e-1fd2-48cc-a71a-cff206e4fbd7" alt="BabelTower API" /><br/>
        <strong>BabelTower API</strong>
        <div>&nbsp;</div>
        <div>无需帐户，立即使用任何模型</div>
      </a>
    </td>
  </tr>
</table>

## 许可证

avante.nvim 采用 Apache 2.0 许可证授权，本分支同样以该许可证分发，并完整保留上游的版权
与声明文件。有关更多详细信息，请参阅 [LICENSE](./LICENSE) 文件。

# Star 历史（上游 avante.nvim）

<p align="center">
  <a target="_blank" href="https://star-history.dera.page/#yetone/avante.nvim&Date">
    <picture>
      <source media="(prefers-color-scheme: dark)" srcset="https://star-history.dera.page/svg?repos=yetone/avante.nvim&type=Date&theme=dark">
      <img alt="NebulaGraph Data Intelligence Suite(ngdi)" src="https://star-history.dera.page/svg?repos=yetone/avante.nvim&type=Date">
    </picture>
  </a>
</p>

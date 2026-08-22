<div align="center">
  <img alt="logo" width="120" src="https://github.com/user-attachments/assets/2e2f2a58-2b28-4d11-afd1-87b65612b2de" />
  <h1>avante.nvim</h1>
</div>

<p align="center">
  <a href="https://neovim.io/" target="_blank"><img src="https://img.shields.io/static/v1?style=flat-square&label=Neovim&message=v0.10%2b&logo=neovim&labelColor=282828&logoColor=8faa80&color=414b32" alt="Neovim: v0.10+" /></a>
  <a href="https://github.com/yetone/avante.nvim/actions/workflows/tests.yaml" target="_blank"><img src="https://img.shields.io/github/actions/workflow/status/yetone/avante.nvim/tests.yaml?style=flat-square&logo=lua&logoColor=c7c7c7&label=Lua+CI&labelColor=1E40AF&color=347D39&event=push" alt="Lua CI status" /></a>
  <a href="https://github.com/yetone/avante.nvim/actions/workflows/rust.yaml" target="_blank"><img src="https://img.shields.io/github/actions/workflow/status/yetone/avante.nvim/rust.yaml?style=flat-square&logo=rust&logoColor=ffffff&label=Rust+CI&labelColor=BC826A&color=347D39&event=push" alt="Rust CI status" /></a>
  <a href="https://github.com/yetone/avante.nvim/actions/workflows/pre-commit.yaml" target="_blank"><img src="https://img.shields.io/github/actions/workflow/status/yetone/avante.nvim/pre-commit.yaml?style=flat-square&logo=pre-commit&logoColor=ffffff&label=pre-commit&labelColor=FAAF3F&color=347D39&event=push" alt="pre-commit status" /></a>
  <a href="https://discord.gg/QfnEFEdSjz" target="_blank"><img src="https://img.shields.io/discord/1302530866362323016?style=flat-square&logo=discord&label=Discord&logoColor=ffffff&labelColor=7376CF&color=268165" alt="Discord" /></a>
  <a href="https://dotfyle.com/plugins/yetone/avante.nvim"><img src="https://dotfyle.com/plugins/yetone/avante.nvim/shield?style=flat-square" /></a>
</p>

**avante.nvim** 是一个 Neovim 插件，旨在模拟 [Cursor](https://www.cursor.com) AI IDE 的行为。它为用户提供 AI 驱动的代码建议，并能够轻松地将这些建议直接应用到源文件中。

[View in English](README.md)

> [!NOTE]
>
> 🥰 该项目正在快速迭代中，许多令人兴奋的功能将陆续添加。敬请期待！

<https://github.com/user-attachments/assets/510e6270-b6cf-459d-9a2f-15b397d1fe53>

<https://github.com/user-attachments/assets/86140bfd-08b4-483d-a887-1b701d9e37dd>

## 赞助 ❤️

如果您喜欢这个项目，请考虑在 Patreon 上支持我，因为这有助于我继续维护和改进它：

[赞助我](https://patreon.com/yetone)

## 功能

- **AI 驱动的代码辅助**：与 AI 互动，询问有关当前代码文件的问题，并接收智能建议以进行改进或修改。
- **一键应用**：通过单个命令快速将 AI 的建议更改应用到源代码中，简化编辑过程并节省时间。

## 安装

如果您希望从源代码构建二进制文件，则需要 `cargo`。否则，将使用 `curl` 和 `tar` 从 GitHub 获取预构建的二进制文件。

> [!IMPORTANT]
>
> avante 直接驱动原生的 [Claude Code CLI](#提供者)。请从
> <https://claude.com/claude-code> 安装它，执行一次 `claude auth` 登录，并确保
> `$PATH` 中有 Python 3.9 或更高版本。无需配置任何 API 密钥。

<details open>

  <summary><a href="https://github.com/folke/lazy.nvim">lazy.nvim</a> (推荐)</summary>

```lua
{
  "yetone/avante.nvim",
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

" 依赖项
Plug 'nvim-lua/plenary.nvim'
Plug 'MunifTanjim/nui.nvim'
Plug 'MeanderingProgrammer/render-markdown.nvim'

" 可选依赖项
Plug 'hrsh7th/nvim-cmp'
Plug 'nvim-tree/nvim-web-devicons' "或 Plug 'echasnovski/mini.icons'
Plug 'HakonHarnes/img-clip.nvim'

" Yay，如果您想从源代码构建，请传递 source=true
Plug 'yetone/avante.nvim', { 'branch': 'main', 'do': 'make' }
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
  source = 'yetone/avante.nvim',
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
    'yetone/avante.nvim',
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
    --- 原生 Claude Code CLI，通过 `py/claude-code-adapter` 中的 Python 适配器驱动。
    --- 详见下文的“提供者”一节。
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
      disable_tools = true, -- Claude Code 自带工具，Avante 的工具会重复执行
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
适配器会运行 `claude --print --output-format stream-json`，把 CLI 的整个 agent 循环
合并成一条助手消息，再以 Anthropic Messages API 事件的形式发出，因此侧边栏、聊天
历史和 token 统计的行为都和以前完全一致。

### 设置

1. **安装 Claude Code CLI**：从 <https://claude.com/claude-code> 安装，然后执行一次
   `claude auth` 登录。认证完全由 CLI 负责：avante 既不会读取也不会提示输入 API
   密钥，也不需要导出 `ANTHROPIC_API_KEY`。您在终端里 `claude` 能用什么，avante 就
   用什么。如果该可执行文件不在 `$PATH` 中，请用 `cli_path` 指定它。
2. **确保 `$PATH` 中有 Python 3.9 或更高版本**：自带的适配器只使用标准库编写——不需要
   `pip install`，也不需要创建虚拟环境。如果您的解释器不叫 `python3` 或 `python`，
   请设置 `python_path`。

设置到此为止。即使 `require("avante").setup({})` 不带任何选项，也已经可以和
Claude Code 对话了：

```lua
require("avante").setup({
  provider = "claude_code",
  providers = {
    claude_code = {
      model = "sonnet",
      permission_mode = "acceptEdits",
    },
  },
})
```

### Claude Code 运行自己的工具

这是最需要理解的一处行为差异。Claude Code 拥有完整的 agent 循环：它会自己读取文件、
搜索、执行命令，并且**直接把改动写入磁盘**，只有在整轮任务结束后才把结果返回给
avante。由此带来两个结果：

- 对该提供者，avante 自己的工具执行器是关闭的（默认 `disable_tools = true`），因此
  同一个工具不会被执行两次。Claude Code 的工具调用会作为活动记录直接渲染在侧边栏中，
  而不会再交给 avante 的工具执行器。
- avante 的 diff 审阅流程不会拦在 Claude Code 的改动之前——响应到达时，文件其实已经
  被修改了。请把 `git`（以及 `permission_mode`）当作您的安全网。

### 权限模式

因此 `permission_mode` 才是真正起作用的安全开关。它会被原样传给
`claude --permission-mode`，所以以 CLI 自身的文档为准，简单来说：

| 取值                | 行为                                                                       |
| ------------------- | -------------------------------------------------------------------------- |
| `acceptEdits`       | **默认值。** 文件改动直接应用，不再询问。                                  |
| `plan`              | 仅规划：Claude Code 只做调研并提出方案，不做任何修改。                     |
| `bypassPermissions` | 跳过所有权限检查。最快，也最危险——只建议在可丢弃或沙箱化的目录中使用。     |
| `manual`            | 不预先批准任何操作，每个动作都需要显式授权。                               |
| `dontAsk`           | Claude Code 不再弹出权限询问，直接继续执行。                               |
| `auto`              | 由 Claude Code 在执行过程中自行决定需要多少授权。                          |

avante 以非交互方式驱动 CLI，因此那些本来会停下来询问的模式无法从侧边栏得到回答——
Claude Code 会直接拒绝该操作，而不是一直等待。这正是默认使用 `acceptEdits` 的原因。
如果您希望先看清一个请求会做什么，再决定是否落地，请从 `plan` 开始。

### 配置项

以下配置项都位于 `providers.claude_code` 下：

| 配置项               | 类型                   | 说明                                                                             |
| -------------------- | ---------------------- | -------------------------------------------------------------------------------- |
| `model`              | `string`               | 模型别名（`"opus"`、`"sonnet"`、`"haiku"`）或完整模型名称。默认 `"sonnet"`。      |
| `cli_path`           | `string`               | `claude` 可执行文件。裸名称会在 `$PATH` 中查找，绝对路径则直接使用。             |
| `python_path`        | `string?`              | 运行适配器的解释器。未设置时会自动从 `python3`/`python` 探测。                    |
| `permission_mode`    | `string`               | Claude Code 的行为尺度，见上表。默认 `"acceptEdits"`。                           |
| `tools`              | `string[]?`            | Claude Code 可以使用的内置工具。`nil` 表示使用其默认工具集，`{}` 表示全部禁用。   |
| `allowed_tools`      | `string[]?`            | 显式允许的工具，例如只读会话可用 `{ "Read", "Grep", "Glob" }`。                   |
| `disallowed_tools`   | `string[]?`            | 显式禁止的工具，例如 `{ "Bash" }`。                                              |
| `add_dirs`           | `string[]`             | 除 `cwd` 之外，允许 Claude Code 访问的额外目录。                                 |
| `mcp_config`         | `string[]`             | MCP 服务器配置文件路径或 JSON 字符串，每一项对应一个 `--mcp-config`。            |
| `strict_mcp_config`  | `boolean`              | 忽略所有未在 `mcp_config` 中列出的 MCP 服务器。默认 `false`。                    |
| `plugin_dirs`        | `string[]`             | Claude Code 插件目录或 `.zip` 文件，仅在本次会话中加载。                         |
| `plugin_urls`        | `string[]`             | Claude Code 插件 `.zip` 文件的 URL，仅在本次会话中加载。                         |
| `disable_slash_commands` | `boolean`          | 只提供 avante 自己的斜杠命令，不提供 Claude Code 的。默认 `false`。              |
| `settings`           | `string?`              | Claude Code 的设置文件路径或 JSON 字符串。                                       |
| `setting_sources`    | `string?`              | CLI 需要加载的设置来源。                                                         |
| `agents`             | `string?`              | 自定义 agent 定义，JSON 字符串。                                                 |
| `effort`             | `string?`              | 推理强度：`"low"`、`"medium"`、`"high"`、`"xhigh"` 或 `"max"`。                  |
| `fallback_model`     | `string?`              | 主模型过载时回退使用的模型。                                                     |
| `max_budget_usd`     | `number?`              | 单轮对话的花费上限（美元）。                                                     |
| `cwd`                | `string?`              | Claude Code 的工作目录，它的工具都被限制在该目录内。默认为项目根目录。           |
| `stateful`           | `boolean`              | 在多轮之间恢复 Claude Code 会话，而不是重放整个对话记录。默认 `true`。           |
| `emit_tool_activity` | `boolean`              | 在侧边栏中显示 Claude Code 自己的工具调用与结果。默认 `true`。                   |
| `extra_args`         | `string[]`             | 原样追加到 CLI 调用后面的参数——用于承载这里没有建模的一切能力。                  |
| `env`                | `table<string,string>` | 传给 CLI 进程的额外环境变量。                                                    |
| `timeout`            | `number`               | 超过该毫秒数后中止本轮对话。默认 `0`，表示不限制。                                 |

例如，一份只读的配置可以这样写：

```lua
providers = {
  claude_code = {
    model = "opus",
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

`:AvanteClaudeCodeAuth` 会在一个终端分屏中打开交互式登录流程。
`:AvanteClaudeCodeStatus` 会报告 CLI 版本、您的登录方式、已安装的插件，以及有多少原生
命令可用；`:checkhealth avante` 给出的信息也是一样的。

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
> 在终端里执行一次 `claude auth` 即可。完整的设置说明，以及决定 Claude Code
> 修改文件自由度的 `permission_mode` 选项，请参见[提供者](#提供者)一节。

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
`__inherited_from` 属性来继承已有的提供者，或者自己实现 `parse_curl_args`。

有关更多信息，请参见 [自定义提供者](https://github.com/yetone/avante.nvim/wiki/Custom-providers)。

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

对 `claude_code` 而言，avante 自己的工具执行器**默认就是关闭的**：CLI 自带 Read、
Edit、Bash、Grep 等工具，两套工具同时启用会让每个操作执行两次。这就是默认提供者配置
中 `disable_tools = true` 的含义。如果要限制 Claude Code 本身能做什么，请使用它的
`tools`、`allowed_tools` 和 `disallowed_tools` 配置项，参见[提供者](#提供者)一节。

`disable_tools` 是按提供者生效的，因此无法处理工具的自定义提供者也可以用同样的方式
关闭它：

```lua
providers = {
  my_provider = {
    -- ... 您自定义提供者的其余配置
    disable_tools = true, -- 禁用工具！
  },
}
```

如果您想为那些确实会使用 avante 工具的提供者禁止某些工具，可以仅禁用特定工具

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
    "yetone/avante.nvim",
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

欢迎为 avante.nvim 做出贡献！如果您有兴趣提供帮助，请随时提交拉取请求或打开问题。在贡献之前，请确保您的代码已经过彻底测试。

有关更多配方和技巧，请参见 [wiki](https://github.com/yetone/avante.nvim/wiki)。

## 致谢

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

## 商业赞助商

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

avante.nvim 根据 Apache 2.0 许可证授权。有关更多详细信息，请参阅 [LICENSE](./LICENSE) 文件。

# Star 历史

<p align="center">
  <a target="_blank" href="https://star-history.dera.page/#yetone/avante.nvim&Date">
    <picture>
      <source media="(prefers-color-scheme: dark)" srcset="https://star-history.dera.page/svg?repos=yetone/avante.nvim&type=Date&theme=dark">
      <img alt="NebulaGraph Data Intelligence Suite(ngdi)" src="https://star-history.dera.page/svg?repos=yetone/avante.nvim&type=Date">
    </picture>
  </a>
</p>

# KeyPocket

![KeyPocket 产品示意：在 Developer 视图保存 API 配置，通过 CLI 与 MCP 提供给 Agent](docs/assets/readme-hero.jpg)

**一个小窗口，管理 API URL、API Key 和环境变量，让桌面 AI Agent 按需读取。**

[English](README.md) · [MIT License](LICENSE) · macOS 14+ · Apple Silicon

KeyPocket 是原生 macOS 本地配置管理工具：用表单或 `.env` 文本编辑配置，保存到系统钥匙串，再通过命令行或本地 MCP 提供给 Agent。无需账号、订阅或后台 HTTP 服务。当前版本为 **0.3.0**，界面语言为中文。

## 功能

- **成组管理**：名称、用途、API URL、API Key 和额外变量保存在一起。
- **Developer 视图**：直接输入 `KEY=VALUE`，自动解析和保存；支持 `.env` 导入。
- **本地存储**：使用 macOS Keychain，无明文配置数据库。
- **Agent 接入**：CLI 与只读 stdio MCP，管理窗口关闭后仍可读取。
- **按需注入**：为单次程序运行加载所选配置，不修改全局环境。
- **紧凑原生 UI**：SwiftUI + AppKit，默认窗口 720 × 500。

## 从源码安装

当前提供源码构建，不提供已公证的安装包。要求 **Apple Silicon Mac、macOS 14 或更新版本**，以及 Xcode Command Line Tools（含 Swift 编译器与 macOS SDK）。当前构建脚本仅生成 arm64 应用。

```sh
# 未安装开发工具时先执行，并完成系统安装窗口
xcode-select --install

# 获取源码并构建
git clone https://github.com/Jamailar/KeyPocket.git
cd KeyPocket
bash build.sh

# 首次安装；如果已有同名应用，请先退出旧版再替换
mkdir -p "$HOME/Applications"
ditto .build/KeyPocket.app "$HOME/Applications/KeyPocket.app"
open "$HOME/Applications/KeyPocket.app"
```

构建产物为 `.build/KeyPocket.app`。重新构建或升级后，macOS 可能再次要求钥匙串访问授权。

可选：安装命令行入口。以下命令在已有同名文件或链接时会拒绝覆盖，请先检查已有入口。

```sh
mkdir -p "$HOME/.local/bin"
ln -s "$HOME/Applications/KeyPocket.app/Contents/MacOS/KeyPocket" "$HOME/.local/bin/keypocket"
# 当前终端生效；需要长期使用时，将这行加入你的 shell 配置
export PATH="$HOME/.local/bin:$PATH"
keypocket --help
```

## 日常管理

1. 打开 `~/Applications/KeyPocket.app`，点击“添加服务”。
2. 填写服务名称、API URL、API Key 和用途。例如“阿里云语音”，备注“中文语音合成”。
3. 默认环境变量为 `URL` 和 `API_KEY`；已有脚本使用其他名称时，在“环境变量名称”中修改。
4. 可导入同一服务的 `.env`，保留额外变量。预览默认跳过同名项，勾选后覆盖。空白 URL / Key 会与导入文件中唯一匹配的变量绑定。源文件保留。
5. 保存后的值供 Agent 下次读取立即使用，管理窗口可以关闭。

旧版项目和变量原样保留。旧数据中如果只有一个 API URL 和一个 API Key，可自动识别；有多个候选时不猜测。可以继续通过 `environment` 读取全部变量，或按服务重新整理。

## Developer 视图

创建和编辑服务时可以切换“表单 / Developer”，直接粘贴环境变量文本：

```dotenv
URL=https://api.example.com/v1
API_KEY=your-key
MODEL=example-model
```

创建窗口点击保存后解析整份文档。主窗口切到 Developer 后，停止输入约 850 毫秒自动保存；切走时也会尝试保存有效内容。无效名称、重复变量和未闭合引号会显示行号，并保留上次有效配置。未保存草稿只在当前应用会话内保留。

文档编辑是完整替换：删除一行会删除对应变量，新增一行会创建变量；同名变量保留内部 ID 与备注。注释、原始换行和变量顺序随文档存入钥匙串。表单修改值后，文本视图会重新生成与最新值一致的内容。

`URL`、`API_URL`、`API_BASE_URL` 及常见带服务前缀的变量名会自动识别；`API_KEY`、`KEY`、`TOKEN` 同样支持。存在多个候选时不猜测。Developer 输入不执行 shell 命令，不展开变量引用，也不会把明文文档写到磁盘。

默认窗口为 720 × 500，最小可缩至 640 × 420；侧栏和表单已压缩。Developer 视图直接显示真实值，适合在需要文档式操作时使用。

## Agent 读取

### 本机命令

完成上方可选 CLI 安装后，可以直接使用 `keypocket list`、`keypocket get` 和 `keypocket run`。完整路径调用不依赖 PATH，适合桌面 Agent。

```sh
# 列出服务名称、用途、URL 和变量名称，不含 Key
"$HOME/Applications/KeyPocket.app/Contents/MacOS/KeyPocket" list

# 指定 ID（推荐）或名称，返回完整 JSON，包含真实密钥
"$HOME/Applications/KeyPocket.app/Contents/MacOS/KeyPocket" get '服务名称'

# 不打印密钥，直接注入变量启动程序
"$HOME/Applications/KeyPocket.app/Contents/MacOS/KeyPocket" run '服务名称' -- python3 script.py
```

`get` 返回 `id`、`name`、`description`、`api_url`、`api_key` 和 `environment`。`environment` 保存原始变量名和值。`list` 的 URL 去掉用户名、密码、查询参数和片段，其他变量值不返回。`get` 保留完整原值。

`run` 保留父进程环境，再用选定服务的变量覆盖同名项；通过 `execvp` 启动目标程序，保留标准输入输出、信号和退出码。它不会修改当前终端或全局环境。需要管道时显式使用 `sh -c`。

应用中的“接入 Agent → 本机命令”可以复制一段使用说明，交给其他有终端能力的 Agent。

### MCP 桌面工具

使用本地 stdio MCP，由 Agent 启动子进程；不监听网络端口，也不要求管理窗口保持运行。

```json
{
  "mcpServers": {
    "keypocket": {
      "command": "/Users/YOUR_USERNAME/Applications/KeyPocket.app/Contents/MacOS/KeyPocket",
      "args": ["mcp"]
    }
  }
}
```

- `list_connections`：发现服务，只返回元数据。
- `get_connection`：传入 `connection`（配置 ID 或名称），返回该服务的 URL、真实 Key 和全部变量。

每次工具调用重新读取钥匙串。仅提供读取工具，不提供执行命令、修改数据或网络代理工具。支持 MCP 2025-06-18 及其 2024-11-05 / 2025-03-26 初始化协商；stdio 使用逐行 JSON-RPC。

上面的 `YOUR_USERNAME` 必须替换为实际用户名；JSON 的 `command` 不会展开 `~` 或 `$HOME`。也可以在“接入 Agent → MCP”复制当前安装路径对应的配置，或运行 `keypocket mcp-config` 生成 JSON。只支持远程 HTTP MCP 的客户端无法直接使用这个本地服务。

Codex 和 Claude Code 可分别通过以下命令注册用户级 MCP 服务（需要先安装对应客户端）：

```sh
codex mcp add keypocket -- "$HOME/Applications/KeyPocket.app/Contents/MacOS/KeyPocket" mcp
claude mcp add --scope user --transport stdio keypocket -- "$HOME/Applications/KeyPocket.app/Contents/MacOS/KeyPocket" mcp
```

已运行的 Agent 需要重新加载 MCP 或重启后使用。Claude Desktop 等客户端使用上面的 JSON 配置。

参考：[Codex MCP 官方说明](https://developers.openai.com/codex/mcp)、[MCP stdio 规范](https://modelcontextprotocol.io/specification/2025-06-18/basic/transports)。

## 数据与访问边界

- 全部配置以 JSON 编码保存到系统 Generic Password 钥匙串项，service 为 `local.jam.keypocket.vault.v1`，account 为 `vault`；数据格式版本为 2，兼容读取版本 1。没有明文配置数据库。
- 同一登录用户的 KeyPocket 程序通过 macOS 钥匙串权限读取。首次读取或重新构建应用后可能出现系统授权提示。
- 接入 MCP 的 Agent 可以读取库里的配置；本版没有每个 Agent / 每条配置的独立访问控制。`get` / `get_connection` 的真实密钥会进入调用客户端的工具上下文，应只按任务需要读取，避免复述到回复、日志或源码。
- 概览默认隐藏变量值，主动显示后 30 秒自动隐藏；Developer 视图和编辑表单会显示明文。复制的密钥 30 秒后或正常退出时清除，前提是剪贴板没有被其他内容替换。无法撤回第三方剪贴板历史记录。
- 不构成同一用户下恶意进程的隔离边界。名称、备注和 URL 路径会作为元数据返回，请勿放入密钥。当前没有跨进程写入协调，请避免同时在多个实例中编辑。
- 本版没有云同步、独立主密码、备份导出、恢复或撤销。迁移验证前保留原始凭据来源。不会自动扫描或迁入现有密钥。
- 应用是本地 ad-hoc 签名构建，未经过 Apple 公证；项目处于早期版本，尚未经过独立安全审计。升级后旧版程序不能写入格式版本 2 的数据，避免丢失新增字段。

## dotenv 支持

支持空行、注释、`export NAME=value`、普通值、单引号／双引号值和空值。双引号支持转义换行、回车、制表符、引号和反斜杠。未加引号的值在空白后的 `#` 处截断注释。

不执行命令、不展开 `$VAR` / `${VAR}`，不支持跨物理行的引号。重复变量名、无效名称和未闭合引号会拒绝整个导入。单行编辑框不适合编辑多行私钥。

## 开发与验证

不需要第三方依赖、包管理器或 Xcode 工程文件。构建脚本直接使用 Swift 编译器、macOS SDK 和系统框架。

```sh
bash build.sh
.build/KeyPocket.app/Contents/MacOS/KeyPocket --self-test
open .build/KeyPocket.app
```

自检使用独立测试钥匙串项并清理：覆盖旧数据兼容、URL / Key 绑定、编辑保留额外变量、目录不泄露密钥、MCP 生命周期和参数验证、实时读取、实际 stdio 子进程、dotenv 解析、钥匙串读写删除、环境注入和退出码。

```sh
open -n .build/KeyPocket.app --args --preview
```

预览模式仅在内存中使用虚拟值，不读写真实钥匙串。界面验收覆盖成组编辑、中文用途说明、URL 显示、Key 隐藏，以及命令行 / MCP 接入页。

## 源码结构

| 文件 | 职责 |
| --- | --- |
| `Sources/Store.swift` | 钥匙串存储、配置模型、dotenv 解析 |
| `Sources/App.swift` | 应用状态、主窗口、导入与变量管理 |
| `Sources/ConnectionViews.swift` | 服务表单与 Agent 接入说明 |
| `Sources/DeveloperView.swift` | 纯文本编辑、自动保存、紧凑窗口 |
| `Sources/AgentAPI.swift` | JSON 输出与只读 stdio MCP |
| `Sources/Main.swift` | GUI / CLI 入口、环境注入、自检 |
| `Sources/AgentTests.swift` | 数据兼容与 Agent 接口测试 |
| `build.sh` / `icon.swift` | 构建、图标生成、ad-hoc 签名 |

系统框架负责 UI、加密存储和进程运行；自研部分仅包含配置模型、dotenv 子集解析与两个 MCP 工具。当前没有自动更新服务或远程后台。

## 常见问题

**可以替代完整的密码管理器吗？** 目前聚焦本机 API 配置与 Agent 读取，没有团队共享、细粒度授权或恢复流程。

**Agent 能看到真实 Key 吗？** `get` 和 `get_connection` 会返回真实值。只想启动脚本时，用 `run` 注入环境变量，避免把 Key 打印到工具输出。

**为什么 Agent 没有发现服务？** 检查客户端是否支持本地 stdio MCP、`command` 是否为正确绝对路径，再重新加载 MCP 或重启客户端；CLI 用 `list` 验证配置可读性。CLI/MCP 报钥匙串权限错误时，先手动打开 GUI 处理系统提示。

**删除应用会删除配置吗？** 不会自动删除钥匙串项。需要删除配置时先在 GUI 内删除；删除和编辑没有撤销。保留原始凭据来源，以便恢复或迁移。

## 贡献与安全反馈

欢迎通过 [Issues](https://github.com/Jamailar/KeyPocket/issues) 提交功能建议与可复现问题，通过 Pull Request 贡献代码。请先阅读 [贡献指南](CONTRIBUTING.md)。不要在 Issue、PR、截图或测试样例中提交真实凭据。

安全问题请按照 [安全政策](SECURITY.md) 私下报告。

## 许可证

[MIT](LICENSE) © 2026 Jamailar。允许使用、修改和分发，包括商业用途；软件按原样提供，不附带保证。

# Reol — 工具链与 MCP 配置

> 目标：让 AI 能**看到** Godot、**运行**项目、**读到**错误、**验证**改动。
> 更新：2026-11-02，开发客户端已从 OpenCode 迁移到 Codex。
> 最新只读复核见[开发工具审计](DEVELOPMENT-TOOLS-AUDIT.md)；更多免费资源/插件候选见[搜集工作包](plans/resource_tooling_scout.md)。下文迁移记录是历史证据，不代表本轮又改配置或安装工具。

---

## 0. 当前环境快照

搭建时实际检测到的：

| 工具 | 状态 |
|---|---|
| Godot 4.7.2 | **已安装并验证**：`D:\Tools\Godot\Godot_v4.7.2-stable_win64.exe`（4.7.2.stable.official） |
| Node.js | v25.2.1 |
| npm / npx | 11.14.1 |
| Python | 3.14.3 |
| uv | 0.11.28 |
| Git | 2.53.0 (Windows) |
| 项目 | `D:\users\sunyu\Documents\reol`，Godot 4.7 工程 |

> 当前游戏构建与测试以 [BASELINE](BASELINE.md) 为准。工具迁移时 Codex 已发现37个项目技能，三个 MCP 均经过协议握手与实际调用验证；下文有日期的验收表保留当时记录。
> 换机器/重装时，按下面步骤安装，并确保 `python tools/godot.py doctor` 能找到它。

---

## 0.1 Codex 项目配置（从这里开始）

Codex 自动读取根目录 `AGENTS.md`，按需发现 `.agents/skills/*/SKILL.md`。
OpenCode 的 `opencode.json`、`~/.config/opencode/` 和 `.opencode/skills/` 不会自动迁移。
本项目原有 37 个技能及 87 个文件已迁到 `.agents/skills/`，没有升级第三方技能，也没有额外的自定义 agent 或 OpenCode 插件需要转换。

```powershell
python tools/setup_codex.py          # 生成本机项目级 MCP 配置
python tools/setup_codex.py --check  # 只检查，不写入
codex mcp list                      # 检查实际加载的服务器配置
```

- 生成的 `.codex/config.toml` 只设置 `godot` 和 `context7`；脚本用当前 Python 和检出目录生成绝对路径，不安装依赖、不修改全局模型或权限。
- 本机配置和备份已被 `.codex/.gitignore` 排除。已有无关配置会保留；同名服务器冲突时退出并提示，不覆盖。
- 项目级配置要求项目已受信任。本机 Reol 已是 trusted；新机器应通过 Codex 的项目信任流程加载。
- Godot AI 使用 dock → **Configure → Codex**，由插件生成 `~/.codex/config.toml` 中的 `mcp_servers.godot-ai`。不要把 OpenCode JSON 整段粘进 TOML。
- 配置或技能未在当前聊天出现时，重新打开项目或重启 Codex；用实际工具列表确认。`codex mcp list` 显示 enabled 只证明配置已加载，不能代替连接和调用验证。

配置脚本的自动化验证：`python -X utf8 -m unittest discover -s tests -p test_codex_setup.py -v`。
技能验证器在 Windows 下应使用 `python -X utf8`，避免中文 UTF-8 文件被按 GBK 解码。

官方说明：[MCP 配置](https://developers.openai.com/codex/mcp)、[技能发现](https://developers.openai.com/codex/skills)。

### 2026-11-02 迁移验收

| 验证 | 实际结果 |
|---|---|
| Codex app-server `skills/list`，强制重新扫描本项目 | 37 个项目技能，0 个解析错误 |
| 技能资源迁移前后 SHA-256 比较 | 87 个文件全部保留，仅项目入口 `reol-project/SKILL.md` 更新 |
| `godot` 初始化 + `get_godot_version` + `get_project_info` | 14 个工具，返回 Reol / Godot 4.7.2 |
| `godot-ai` 会话/编辑器/运行/场景/日志/截图 | 插件与后端 4.3.1；游戏 `live`、helper live；游戏/编辑器日志无错误或警告；1280×720 截图成功 |
| `context7` 搜索 + 查询 4.7 分支 API | 2 个工具，返回官方 4.7 TileMapLayer 方法文档 |
| `python tools/godot.py doctor` / `check` | Godot 4.7.2；28 passed / 0 failed；CHECK PASSED |
| 配置脚本自动化测试 | 4 passed：保留已有设置、备份、重复运行、冲突保护及只读检查 |

截图：`artifacts/qa/codex-mcp-game.png`；运行证据：`logs/codex-migration-mcp-runtime.json`；
Godot 回归日志：`logs/check-test-20261102-154904.log`。这些临时证据已被 Git 排除。
验证用的临时编辑器已正常关闭；日常使用 Godot AI 时需重新打开 Reol 编辑器。

Windows 备用 MCP 隐藏启动初次复测出现 `Request 'initialize' timed out`；
已修复 `godot_mcp.py` 的标准流传递：`CREATE_NO_WINDOW` 配合显式 `stdin/stdout/stderr`。
修复后同样的握手、版本与项目查询全部成功。没有升级或新引入依赖。

---

## 1. 安装 Godot 4.7.2（必须先做）

### 1.1 下载

官方下载页：https://godotengine.org/download/windows/

或直接下载标准版（**不要 .NET 版**，本项目用 GDScript）：

```
https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_win64.exe.zip
```

### 1.2 放置

建议放在一个没有中文/空格的路径，例如：

```
D:\Tools\Godot\Godot_v4.7.2-stable_win64.exe
```

解压即可，不需要安装。

### 1.3 设置 `GODOT_BIN`

**PowerShell（当前用户，永久）：**

```powershell
[Environment]::SetEnvironmentVariable(
  "GODOT_BIN",
  "D:\Tools\Godot\Godot_v4.7.2-stable_win64.exe",
  "User"
)
```

设置完**重开终端和 Codex**，否则当前进程读不到。

**Git Bash（当前会话临时）：**

```bash
export GODOT_BIN="D:/Tools/Godot/Godot_v4.7.2-stable_win64.exe"
```

### 1.4 验证

```bash
python tools/godot.py doctor
python tools/godot.py version
```

期望看到类似：

```
Godot: 4.7.2
Path:  D:\Tools\Godot\Godot_v4.7.2-stable_win64.exe
```

### 1.5 导出模板（打包时需要）

编辑器菜单：**Editor → Manage Export Templates → Download and Install**。
或下载 `Godot_v4.7.2-stable_export_templates.tpz` 后手动安装。

v0.1 只需要 Windows 导出模板。

---

## 2. 项目内的验证命令

`tools/godot.py` 是跨平台包装，AI 和人都用同一套命令：

```bash
python tools/godot.py doctor        # 环境诊断
python tools/godot.py which         # 只打印 Godot 路径
python tools/godot.py version       # 版本
python tools/godot.py import        # 无头导入资源（新资源/新 class_name 后必跑）
python tools/godot.py test          # 无头跑 tests/run_tests.gd
python tools/godot.py check         # import + test
python tools/godot.py check --test-timeout 1800  # 显式延长本次完整测试的上限
python tools/godot.py editor        # 打开编辑器
python tools/godot.py run           # 运行项目
python tools/godot.py run --headless --quit-after 120
python tools/godot.py export --preset "Windows Desktop" --output build/windows/reol.exe
```

退出码：
- `0` = 成功
- 非 `0` = 失败；日志在 `logs/`（进程结束或超时后写入捕获的输出；运行中可用进程/会话句柄确认状态）

`test`与`check`均支持`--test-timeout`正整数秒，默认仍为900秒；只调整本次无头测试进程上限，结构检查与导入上限不变。完整历史fixture回归持续增长，本机同时运行编辑器/游戏等进程时可显式使用1800秒，例如`python tools/godot.py test --test-timeout 1800`。这不会改变游戏时间、跳过测试或削减回归。超时保留已经输出的日志并按失败退出；`test`超时码为124，`check`会报告失败，超时不等于通过。

### 2.1 测试脚本做什么

`tests/run_tests.gd`：
- 检查 `project.godot` 的 Godot 版本特性。
- 检查主场景存在且能实例化。
- 递归 `load()` 所有 `scripts/`、`tests/` 下的 `.gd`，捕获解析错误。
- 运行所有 `test_*` 方法，汇总 passed/failed，失败退出码 1。

这是最小可用的无头测试框架；后续复杂了再换 GUT。

### 2.2 GitHub持续集成（2026-11-04）

公共仓库：[fewnfds/reol](https://github.com/fewnfds/reol)，运行入口：[Actions](https://github.com/fewnfds/reol/actions)。用户已授权自主阶段性提交和推送；完整无头验证优先交CI，画面/手感等仍在本地运行。项目本身许可证仍待用户选择，仓库公开不自动授予第三方开源使用权；第三方许可继续随原组件保留。

工作流`.github/workflows/ci.yml`在代码/资源/测试/工具或CI变更推送及PR时运行，也支持手动触发。纯文档、设计、技能和素材收件说明不触发昂贵的游戏回归，仍须本地结构/链接检查。Ubuntu24.04、Python3.14、Godot4.7.2正式Linux无头程序；引擎从官方godot-builds release下载到runner临时目录并核SHA256，不提交二进制或`.godot`缓存。Actions固定commit，不依赖本机MCP服务或登录状态。

CI先执行Python工具测试，再跑`python -u tools/godot.py check --test-timeout 1800`（结构、导入、全部GDScript测试），作业总上限50分钟。通过/失败均上传`godot-logs`保留14天；失败先读第一条真实错误。推送后以具体commit SHA对应run的完成状态为准，不把排队/执行中/旧提交绿色当通过。可用`gh run list`、`gh run view <run-id>`、`gh run view <run-id> --log-failed`读进度；无需持续阻塞长等待。首次配置的远端运行证据待实际完成后更新至BASELINE。

### 2.3 格式化与 Lint（建议）

```bash
uv tool install gdtoolkit
gdlint --version
gdformat --version
```

CI 可加：

```bash
gdlint scripts tests
gdformat --check scripts tests
```

> gdtoolkit 对 Godot 4.7 语法的支持以其 release notes 为准；升级前先跑一遍全项目。

---

## 3. MCP 总览

MCP 让 AI 通过工具调用操作 Godot，而不是只“猜代码”。

| 服务器 | 类型 | 用途 | 本项目状态 |
|---|---|---|---|
| **godot-ai** | 编辑器插件 + 本地 bridge | 看场景树、改节点、跑游戏、读日志、截图、输入模拟 | Codex 连接实测：47 个工具，Reol 编辑器 ready，插件/后端均为 4.3.1 |
| **godot**（Coding-Solo） | 本地 stdio（npx） | 无头启动、运行项目、抓调试输出、建场景 | Codex 配置实测：14 个工具，版本/项目信息返回 Godot 4.7.2 |
| **context7** | 远程 | 查 Godot / 第三方库最新文档 | Codex 项目级 HTTP；2 个工具，已检索并读取 Godot 4.7 TileMapLayer 文档 |

> 不要同时让两个 MCP 抢同一个编辑器/端口。日常优先 `godot-ai`；CI/无头用 `godot` 或 `tools/godot.py`。

---

## 4. Godot AI（首选，实时编辑器）

### 4.1 它是什么

- 当前 v4.3.1 实测 47 个 MCP 工具，连接**正在运行的 Godot 编辑器**。
- 能：读场景树、创建/改节点、写脚本并校验、跑项目、读编辑器/游戏日志、截图、模拟输入、跑测试、改 TileMap/导航/材质/动画/UI。
- 对本项目最有用：**AI 能看见自己改了什么**，而不是盲写 `.tscn`。

### 4.2 安装状态

本仓库已经包含：

```
addons/godot_ai/           # v4.3.1，MIT
```

`project.godot` 已加入：

```
[editor_plugins]
enabled=PackedStringArray("res://addons/godot_ai/plugin.cfg")
```

### 4.3 启用

1. 用 Godot 4.7.2 打开项目。
2. 菜单 **Project → Project Settings → Plugins**。
3. 确认 **Godot AI** 是 **Enabled**。
4. 编辑器右侧/底部会出现 **Godot AI** dock。

如果插件报错：
- 确认 Godot 是 4.7+。
- 看 **Output** 面板第一条红色错误。
- 不要用旧版覆盖；用 dock 的 **Update**。

### 4.4 配置 Codex

1. 保持 Reol 的 Godot 4.7.2 编辑器打开，确认插件已启用。
2. 在 Godot AI dock 里为 **Codex** 点 **Configure**。
3. 插件写入 `~/.codex/config.toml` 的 `[mcp_servers.godot-ai]`，Windows 使用隐藏控制台的 `pythonw` 启动桥接。
4. 重新打开 Codex 项目或重启 Codex，再检查 `codex mcp list` 和当前聊天的实际工具列表。
5. 调用 `session_manage(op="list")` 和 `editor_state`，核对项目路径、Godot 版本和 readiness；多项目时先 `session_activate` 选 Reol。

2026-11-02 已通过插件的 `client_manage(op="configure", params={"client":"codex"})` 完成同一配置；配置前备份全局 TOML，配置后确认其他全局设置语义不变。

> **不要手写 `godot-ai` 的端口/命令。** v4 使用带认证的 `godot-ai attach`，
> dock 会写入匹配版本、端口、工具域的命令。手写一个裸 HTTP URL 连不上。

如果自动配置失败：
- dock 里点 **Run this manually**，复制完整命令。
- 按它给的 Codex 格式添加到 TOML 的 `[mcp_servers.godot-ai]`，保留完整的版本固定和 attach 参数。
- 仍失败就看 dock 的日志和 `docs/TOOLCHAIN.md` 的 Troubleshooting。

### 4.5 安全

- 只监听 loopback；不要暴露到局域网。
- 更新走 dock 的签名校验；不要手动解压覆盖。
- 插件运行在编辑器权限下；只安装可信来源。

---

## 5. Coding-Solo Godot MCP（无头/启动/调试）

### 5.1 它是什么

- npm 包：`@coding-solo/godot-mcp`（0.1.1）。
- 工具：`launch_editor`、`run_project`、`get_debug_output`、`stop_project`、
  `get_godot_version`、`list_projects`、`get_project_info`、`create_scene`、
  `add_node`、`load_sprite`、`save_scene`、`get_uid`、`update_project_uids`。
- 不依赖编辑器插件；需要 `GODOT_PATH`。

### 5.2 本项目配置

运行 `python tools/setup_codex.py` 后，`.codex/config.toml` 包含以下条目（实际文件使用本机绝对路径）：

```toml
[mcp_servers.godot]
command = "<本机 Python 可执行文件>"
args = ["<检出目录>/tools/mcp/godot_mcp.py"]
cwd = "<检出目录>"
enabled = true
startup_timeout_sec = 65
tool_timeout_sec = 65
```

旧 `opencode.json` 保留给 OpenCode；Codex 不读取该文件。

`tools/mcp/godot_mcp.py` 会：
1. 用 `tools/godot.py` 的查找逻辑定位 Godot。
2. 找到就设置 `GODOT_PATH`。
3. 启动 `npx -y @coding-solo/godot-mcp@0.1.1`。

手动测试：

```bash
python tools/mcp/godot_mcp.py
```

它会占住 stdio；看到 `[godot-mcp] GODOT_PATH=...` 就说明找到了。`Ctrl+C` 退出。

### 5.3 如果不想用

在本机 `.codex/config.toml` 的 `[mcp_servers.godot]` 中设置 `enabled = false`。

---

## 6. context7（文档）

`tools/setup_codex.py` 会生成以下项目级配置，无需安装新的 npm 包：

```toml
[mcp_servers.context7]
url = "https://mcp.context7.com/mcp"
enabled = true
startup_timeout_sec = 30
tool_timeout_sec = 60
```

迁移时匿名连接实测成功，无需登录；`codex mcp list` 的 `not_logged_in` 本身不是连接失败。
如服务以后返回认证/限流错误，以实际响应为准，再按服务说明配置凭据。
用法：先 `resolve-library-id`，再用返回的库和版本调用 `query-docs`。
已验证 `/godotengine/godot-docs/__branch__4.7` 能返回 4.7 分支的 `TileMapLayer.get_used_rect()` 文档。
**API 不确定时先查，不要凭记忆写。**

---

## 7. 其他 Godot MCP（按需了解，不要全装）

截至 2026-11-01 的 GitHub 星数/定位：

| 项目 | 星 | 定位 | 备注 |
|---|---:|---|---|
| Coding-Solo/godot-mcp | 6.4k | 启动/运行/调试输出 | 轻量，适合无头；本项目备用 |
| hi-godot/godot-ai | 3.3k | 实时编辑器，46 工具 | 功能最全；本项目首选 |
| yurineko73/Godot-MCP-Native | 865 | Godot 原生插件，无依赖 | 中文文档，开箱即用；可做轻量替代 |
| youichi-uda/godot-mcp-pro | 641 | 162 工具，付费 $15 | 功能多；先不需要 |
| ee0pdt/Godot-MCP | 621 | 编辑器插件，场景编辑 | 备选 |
| DaxianLee/godot-mcp | 550 | 原生插件，一键配置 | 备选 |
| tugcantopaloglu/godot-mcp | 507 | 157 工具，宣称 4.7 | 备选 |
| IvanMurzak/Godot-MCP | 319 | C# / 云端 | 本项目不用 C# |

选择原则：
- **能实时看编辑器** > 只能启动/抓日志。
- 工具多不等于好；上下文开销和权限风险要考虑。
- 只装一个主 MCP，避免端口/编辑器抢占。

---

## 8. 常见故障排查

### 8.1 `doctor` 找不到 Godot

- 确认 `GODOT_BIN` 指向 `.exe` 文件，不是目录。
- 路径有空格时用引号。
- 设置环境变量后**重开终端/Codex**。
- 直接运行：

  ```bash
  "D:/Tools/Godot/Godot_v4.7.2-stable_win64.exe" --version
  ```

- 如果输出 `4.7.2.stable.official...`，说明程序没问题，是环境变量没读到。

### 8.2 `Identifier "X" not declared`

- 新加 `class_name` 后没导入：`python tools/godot.py import`。
- 循环 `preload`：拆成运行时 `load()` 或提取公共类。
- `.godot/` 缓存损坏：先备份，再删除 `.godot/` 重新导入（会重新生成，不要提交）。

### 8.3 MCP 连不上

- `godot`（Coding-Solo）：
  - `node --version` ≥ 18。
  - `npx -y @coding-solo/godot-mcp@0.1.1` 能跑。
  - `python tools/mcp/godot_mcp.py` 能看到 `GODOT_PATH`。
  - `python tools/setup_codex.py --check` 和 `codex mcp list` 查看配置；重新打开 Codex 后实际调用版本工具。
- `godot-ai`：
  - Godot 编辑器必须开着，插件 enabled。
  - dock 里显示 Connected，`session_manage` 返回 Reol，`editor_state.readiness` 为 ready。
  - 重新 Configure；不要手写端口。
  - 看 Godot Output 面板和 `%LOCALAPPDATA%\godot-ai\` 日志。

### 8.4 端口被占用

- Godot AI 默认 HTTP 8000 / WebSocket 9500；dock 会自动选可用端口。
- 不要同时开两个 Godot 编辑器实例连同一个 dock。
- 用 `netstat -ano | findstr :8000` 查占用。

### 8.5 导入很慢/卡住

- 首次导入正常，可能 10–60 秒。
- 大资源用 `ResourceLoader.load_threaded_request`，不要启动时全加载。
- 不要提交 `.godot/`；CI 每次重新导入。

### 8.6 导出失败

- 没装导出模板：Editor → Manage Export Templates。
- 路径/预设名不对：`python tools/godot.py export --preset "Windows Desktop" --output build/windows/reol.exe`。
- 导出后 `res://` 只读；存档必须写 `user://`。

### 8.7 Godot AI 插件报版本不匹配

- 插件 v4.3.1 需要 Godot 4.7+。
- 不要用旧版 `addons/godot_ai` 覆盖新版；用 dock 的 Update。
- 如果是从 v3 升级，按官方迁移指南操作。

---

## 9. 更新策略

| 组件 | 策略 |
|---|---|
| Godot | 固定 4.7.2；升级前跑全量测试 + 截图对比 |
| Godot AI | 用 dock 的 Update；不要手动覆盖；pin 大版本 |
| Coding-Solo MCP | 固定 `@0.1.1`；升级前跑 `doctor` + 手动启动 |
| 技能库 | 固定 upstream commit（见 `THIRD_PARTY_NOTICES.md`）；升级时 diff |
| gdtoolkit | 固定版本；升级后全项目 lint |
| 项目 addon | 每个都记录版本/许可证/来源 |

---

## 10. 一键检查清单

```bash
# 1. Godot 可执行
python tools/godot.py doctor

# 2. 导入 + 测试
python tools/godot.py check

# 3. 运行 boot 场景
python tools/godot.py run --headless --quit-after 60

# 4. Codex 配置和 MCP 条目
python tools/setup_codex.py --check
codex mcp list

# 5. 配置脚本测试
python -X utf8 -m unittest discover -s tests -p test_codex_setup.py -v

# 6. 编辑器（手动）
python tools/godot.py editor
```

MCP 还需在重新加载的 Codex 聊天里实际调用；运行/画面验收仍按 `godot-verify` 执行。

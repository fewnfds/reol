# Reol — 工具链与 MCP 配置

> 目标：让 AI 能**看到** Godot、**运行**项目、**读到**错误、**验证**改动。
> 日期：2026-11-01

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

> 本次搭建已跑通 `doctor`、`check`（6 passed）、`run --headless`。
> 换机器/重装时，按下面步骤安装，并确保 `python tools/godot.py doctor` 能找到它。

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

设置完**重开终端**（以及 OpenCode），否则当前进程读不到。

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
python tools/godot.py editor        # 打开编辑器
python tools/godot.py run           # 运行项目
python tools/godot.py run --headless --quit-after 120
python tools/godot.py export --preset "Windows Desktop" --output build/windows/reol.exe
```

退出码：
- `0` = 成功
- 非 `0` = 失败；日志在 `logs/`（脚本会把输出 tee 到文件）

### 2.1 测试脚本做什么

`tests/run_tests.gd`：
- 检查 `project.godot` 的 Godot 版本特性。
- 检查主场景存在且能实例化。
- 递归 `load()` 所有 `scripts/`、`tests/` 下的 `.gd`，捕获解析错误。
- 运行所有 `test_*` 方法，汇总 passed/failed，失败退出码 1。

这是最小可用的无头测试框架；后续复杂了再换 GUT。

### 2.2 格式化与 Lint（建议）

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
| **godot-ai** | 编辑器插件 + 本地 bridge | 看场景树、改节点、跑游戏、读日志、截图、输入模拟 | 插件已内置，待启用/Configure |
| **godot**（Coding-Solo） | 本地 stdio（npx） | 无头启动、运行项目、抓调试输出、建场景 | 已连接并验证：`get_godot_version` → 4.7.2 |
| **context7** | 远程 | 查 Godot / 第三方库最新文档 | 已可用（全局配置） |

> 不要同时让两个 MCP 抢同一个编辑器/端口。日常优先 `godot-ai`；CI/无头用 `godot` 或 `tools/godot.py`。

---

## 4. Godot AI（首选，实时编辑器）

### 4.1 它是什么

- 46 个 MCP 工具，连接**正在运行的 Godot 编辑器**。
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

### 4.4 配置 OpenCode

1. 在 Godot AI dock 里点 **Configure**（或 **Configure all**）。
2. 选择 **OpenCode**。
3. 插件默认写全局配置 `~/.config/opencode/opencode.json` 的 `mcp.godot-ai`
   （当前 OpenCode 的 MCP 结构是 `mcp.<name>`，不是 `mcp.servers`）。
4. 如果你想只在本项目启用：把生成的 `godot-ai` 条目复制到项目 `opencode.json`
   的 `mcp.godot-ai`，再从全局配置删除。
5. 用 `/mcps` 查看，确认 `godot-ai` 是 connected。

> **不要手写 `godot-ai` 的端口/命令。** v4 使用带认证的 `godot-ai attach`，
> dock 会写入匹配版本、端口、工具域的命令。手写一个裸 HTTP URL 连不上。

如果自动配置失败：
- dock 里点 **Run this manually**，复制完整命令。
- 按它给的格式加到 `opencode.json` 的 `mcp.godot-ai`（注意是 `mcp` 下直接放名字）。
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

`opencode.json` 已经配置：

```json
{
  "mcp": {
    "godot": {
      "type": "local",
      "command": ["python", "tools/mcp/godot_mcp.py"],
      "enabled": true,
      "timeout": 60000
    }
  }
}
```

> 当前 OpenCode 使用 `mcp.<name>`；`timeout` 是毫秒数字，不是对象。

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

从 `opencode.json` 删除 `godot` 条目即可；或加 `"disabled": true`。

---

## 6. context7（文档）

已在本会话可用。若你的全局配置没有：

```bash
opencode mcp add context7 --url https://mcp.context7.com/mcp
```

用法：让 AI 查 “Godot 4.7 TileMapLayer API”“LimboAI behavior tree” 等。
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
- 设置环境变量后**重开终端/OpenCode**。
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
  - OpenCode 里 `/mcps` 查看状态。
- `godot-ai`：
  - Godot 编辑器必须开着，插件 enabled。
  - dock 里显示 Connected。
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

# 4. MCP 状态
opencode mcp list

# 5. 编辑器（手动）
python tools/godot.py editor
```

全部通过后，M0 完成。

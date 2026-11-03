# 历史存档：BASELINE（2026-11-02 目录整理前）

> 历史材料，不作为当前进度或开发指令。当前入口：[项目文档](../../README.md)。

# 基座状态（M0 → M1 已完成）

> **最新双聚落验证（2026-11-02）**：区域调度、远区批算、运粮/封路/消息、入场接续与联合存读已接入。当前 `check` **37 组 / 1,082 断言 / 0 失败**；见[实现记录](../WORLD-CONTINUITY-IMPLEMENTATION.md)。下文较早测试数和待做 C+ 的记录为历史。

> 日期：2026-11-01
> 目的：记录“现在已经有什么、验证到什么程度、下一步讨论什么”。
> 这不是完成品；是可安全开始开发的基座。
> **2026-11-01 更新**：方向 v0.2 已定稿（2D 正交俯视 + 正方形格 + 高度层、单机模拟、可暂停战斗）；M0 验证记录仍然有效。
> **2026-11-01 追加**：M1 基础系统已完成（网格/相机/玩家/区块流式/高度层/迷雾/时间/碰撞打磨），`check` 16 passed；下一步 M2。见 `docs/GAME-BRIEF.md`、`docs/DIRECTION-V0.2.md`、ADR-0013～0019。
> **2026-11-02 追加**：社会系统设计草案（`design/systems/social_system.md`、ADR-0020/0021）；继任算法原型 `SuccessionResolver` + 10 条测试；`check` 28 passed。
> **2026-11-02 工具迁移**：Codex 已发现 37 个项目技能；Godot / Godot AI / Context7 均完成实际连接与调用。入口改为 `.agents/skills/` + `tools/setup_codex.py`，详见 `docs/TOOLCHAIN.md`。
> **2026-11-02 最新实现**：世界模拟首个运行骨架已接入主场景；固定推进、NPC 日常/供给、请求/承诺、知情隔离、机构账目和快照已实现。`check` **34 组通过 / 0 失败，753 条断言**，Python **7 条通过**；已实际运行、交互、存读并检查 1280×720 界面。详情与边界见 [实现记录](../LIVING-WORLD-IMPLEMENTATION.md)。下文未同步的 M0/M1 记录是历史证据，不作为当前下一步。

---

## 1. 已完成

### 引擎与运行
- Godot **4.7.2 stable** 已安装并验证：
  `D:\Tools\Godot\Godot_v4.7.2-stable_win64.exe`
- 用户环境变量 `GODOT_BIN` 已设置（新终端生效）。
- 项目主场景：`res://scenes/main.tscn`；旧 `boot.tscn` 保留作基座测试。
- 窗口基准：1280×720；2D 物理层命名已建立。

### 验证
| 检查 | 结果 |
|---|---|
| `python tools/godot.py doctor` | Godot 4.7.2，全部关键文件存在 |
| `python tools/godot.py check` | **34 passed / 0 failed，753 assertions**，`CHECK PASSED` |
| `python tools/godot.py run --headless --quit-after 30` | `Reol boot OK - Godot 4.7.2-stable` |
| `gdlint scripts tests` | 无问题 |
| `gdformat --check scripts tests` | 无需重排 |
| `godot` MCP `get_godot_version` | `4.7.2.stable.official.ed1daf0bf` |
| `godot` MCP `get_project_info` | `name: reol`，路径正确 |
| `godot` MCP `run_project` / `stop_project` | 可启动/停止 |

### M2 宗门生活（进行中）
- `data/definitions/ranks.json`、`data/definitions/origins.json`、`data/definitions/pawns.json`：出身/职位/角色数据包。
- `ReolContentDB`：加载 + 引用校验（未知 rank/origin、重复 id、非法数值都会记录错误）。
- `PawnState`：身体与成员层级的表现视图；精力替代含义模糊的旧疲劳字段，贡献/总声望已移除，晋升资格读取机构账目。
- 世界内玩家 + 5 个具名 NPC（陈守拙、阿禾、石头、苏芷、老周）。
- 左键选中 NPC，右侧面板显示出身/境界/职位/需求数值；Esc 回到玩家。
- `scripts/sim/`：日常执行、库存预约、交互/记忆、机构账目、配置/快照校验与存读；行为边界和验证见实现记录。
- 社会系统设计草案：Claim/账本/机构/职位/继任算法；见 `design/systems/social_system.md`。
- `SuccessionResolver`：纯函数，两阶段（候选人合法性 + 逐笔旧账效用），10 条无头测试覆盖冻结/全认/谈判/拒付/折价/争议继位/空位期/法器门槛/折价率/政策覆盖。

### AI 工具链
- **Codex** 项目配置：`tools/setup_codex.py` → 本机 `.codex/config.toml`；配置不入 Git，脚本不覆盖已有无关设置。
- `godot` MCP 已做协议握手与版本/项目信息调用验证，14 个工具；固定 Coding-Solo godot-mcp 0.1.1。
- **Godot AI 4.3.1** 编辑器插件已安装到 `addons/godot_ai/`，并在 `project.godot` 中启用。
  - headless 导入日志确认插件被识别（`MCP | plugin disabled in headless mode`）。
  - **已迁移**：插件已为 Codex 生成全局 `godot-ai` 配置；47 个工具，已读取 Reol 编辑器状态、启动游戏、检查日志并截图，插件/后端版本均 4.3.1。
- `context7` 项目级 HTTP 连接已验证，2 个工具，已检索并读取 Godot 4.7 API 文档。
- `AGENTS.md` 由 Codex 自动读取；没有额外的自定义 agent 或 OpenCode 插件待迁移。旧 `opencode.json` 为 OpenCode 保留。
- 无头测试脚本：`tests/run_tests.gd` + `tools/godot.py`。
- Codex 配置脚本测试：`tests/test_codex_setup.py`，4 条通过；与游戏的 28 条无头测试分开统计。

### 资料库
- `AGENTS.md`：AI 每会话硬规则、目录、DoD、技能路由。
- 37 个技能（`.agents/skills/`；已从 OpenCode 目录迁移，Codex 实际发现 37 个，无解析错误）：
  - 31 个来自 `awesome-gamedev-agent-skills`（Apache-2.0，固定 commit）。
  - 6 个项目专属：`reol-project`、`godot-sim-architecture`、`colony-sim-systems`、
    `open-world-2d`、`godot-verify`、`spec-driven-game-dev`。
- 文档：
  - `docs/GAME-BRIEF.md`（愿景/范围/已拍板方向）
  - `docs/DIRECTION-V0.2.md`（方向分析与最终选择）
  - `docs/ARCHITECTURE.md`（tick/实体/数据/区块/存档/性能）
  - `docs/ROADMAP.md`（M0–M5 + 第一冲刺）
  - `docs/GODOT-FOR-UNITY-DEVS.md`
  - `docs/TOOLCHAIN.md`（安装/MCP/排错）
  - `docs/AI-WORKFLOW.md`
  - `docs/REFERENCES.md`（示例项目/插件/素材/许可证）
  - `docs/DECISIONS.md`（21 条 ADR）
- `design/` 系统设计模板；`data/`、`assets/` 约定。
- `THIRD_PARTY_NOTICES.md` + 许可证原文。
- Git 仓库已初始化，根提交 `40f307c`。
- GitHub Actions CI 模板（Godot 4.7.2 下载 + `check`）。

---

## 2. 尚未完成 / 需要你参与

| 事项 | 为什么还没做 |
|---|---|
| Codex 重新加载 | MCP 配置已写入并单独调用验证；已有聊天应重新打开项目或重启 Codex 后确认实际工具列表 |
| Boot 场景截图 | 需要真实窗口渲染；headless 无画面 |
| 导出模板 | 打包时才需要；Editor → Manage Export Templates |
| M1 实现 | 已完成：俯视网格/相机/玩家/区块/高度层/战争迷雾/时间/碰撞打磨（16 条测试） |
| M2 进展 | 日常/供给、NPC 请求、信息关系、机构账目与最小快照已接入；正式日程、对话、兑换/通行操作和完整世界存档继续推进 |
| 美术细节 | tile 尺寸（64×64 vs 32×32）/色盘，M1 实测后定 |
| 境界名/数值 | M2 前写设计文档 |
| 项目许可证 | 你还没选（MIT / Apache-2.0 / 专有） |
| CI 首次运行 | 需要 GitHub remote |
| GUT | 暂用自带 headless runner；复杂后替换 |

---

## 3. 下一个会话怎么开始

```text
读 AGENTS.md、docs/BASELINE.md、docs/DIRECTION-V0.2.md。
M0、M1 已完成；M2 已有世界模拟运行骨架。
先读 docs/LIVING-WORLD-IMPLEMENTATION.md，避免重做已有供给、交互与存读。
```

M2 双聚落连续性首版已验证，见[实现记录](../WORLD-CONTINUITY-IMPLEMENTATION.md)。后续根据试玩反馈补访客服务、互动和组织办事，再扩展局势；保留绿色测试。

---

## 4. 已拍板的方向（2026-11-01）

1. **视角/美术**：2D 正交俯视 + 正方形格 + 高度层；固定俯视、平移/缩放、不旋转；像素俯视 + 国风色盘（ADR-0013）。
2. **世界**：512×512 首区；64×64 区块；5×5 加载；远区抽象模拟（ADR-0014 / 0015）。
3. **玩家/身份**：杂役起步；数据驱动多出身；阵营/声望/职位（ADR-0016）。
4. **战斗**：实时 + 暂停；局部慢放后期解锁；WC3 式高度表现（ADR-0017）。
5. **AI**：脚本/效用 AI 优先；LLM 后期只做对话（ADR-0018）。
6. **内容生产**：数据包 + schema + 世界生成管线（ADR-0019）。

**不再讨论**：3D、联机、体素、LLM 核心模拟。

---

## 5. 已知风险

- 范围过大：开放世界 + 殖民 + RPG + 建造，任何一个都能吞掉数月。
- 模拟性能：Pawn 数量/工作评估/寻路是主要热点。
- 存档腐烂：字段会频繁变；必须从第一天做版本化。
- AI 幻觉 API：所有 Godot 4.7 API 都要用文档/context7/最小示例验证。
- 第三方插件：Godot AI 有编辑器权限；pin 版本，走官方更新。

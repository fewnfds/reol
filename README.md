# Reol

Godot **4.7.2** / GDScript / 2D正交俯视的修仙开放世界沙盒。玩家是持续世界中的一员，可以选择生活、修行、创造、交往、冒险或组织他人。reol = reroll，源自 Dota Allstars 的 `/reroll`。

当前是 **M2系统原型**：双聚落持续生活、真实物资与办事、有限认知、几种生命短循环和宗门工地施工已接通；完整45–60分钟切片与完整游戏仍待完成。用户已再次恢复完整游戏Goal active；本轮的[自然地块与办事场所](docs/plans/natural_world_and_workplaces.md)已接地表/植被覆盖、普通山雀和固定构件值事房。长期方向仍为[超凡者优先](docs/plans/transcendent_focus.md)：普通生产先维持世界循环，优先战斗、装备/法器、功法/学习、冒险、组织与事件化远区。人身C提有限请求/商量劳动安排，也能向真实3×3山兽比划递食；M试验/传授温养办法及实际刻牍/阅读/携带交接，N画蓝图并实际施工/拆改。玩家离场后，NPC继续生活、劳动或阅读，山兽按同一完整占地活动。新局石头还会为自己的随身口粮找人问路、实际接活领薪和买饭；无预算时回原日常。

## 先读这三份

U页现可回顾本人的学习/实践来源；亲学护障并完成真实行步练气后，原护障施法时可有限缓步。不是经验购点，资源和学习仍来自原世界。当前验收与限制见[U2-a](docs/qa/20261104_capability_network.md)及构建状态。

野外取得的环已接本人用法研究和短距引取松置木剑；实际条件与末版验证见[引物环QA](docs/qa/20261104_drawing_ring.md)，本包最终验收仍待完成。

- [游戏愿景与已拍板方向](docs/GAME-BRIEF.md)：游戏是什么、理念与边界。
- [当前功能清单](docs/FEATURES.md)：现在能做什么、如何操作、哪些只是局部样本。
- [当前构建状态](docs/BASELINE.md)：最新验证、存档兼容与未完成项。

最新[身体后果/实际救护](docs/qa/20261103_health_and_recovery.md)已接原温石反噬、C当面诊断/原鲜药处理与逐步休养，真实进行中完整重启已验；不是完整医疗或死亡系统。

[历法/局地冷热首步](docs/qa/20261103_calendar_temperature.md)沿同一时间显示日期和四季，地区室外温度、实际衣着/湿润影响原精力；NPC可御寒加衣、晴热脱外层，真实穿衣中途完整重启保持同一未来。八向代码像素待机/行走/抬手已接，完整气候/室内热交换、五行/风水和全部动作动画仍待做。

全部入口见[文档目录](docs/README.md)。本轮环境/五行/风水/建筑/组织/策略与AI交互的讨论整理见[世界与交互原则](design/systems/world_interaction_principles.md)。

## 运行与验证

安装Godot 4.7.2并配置 `GODOT_BIN`，然后执行：

```bash
python tools/godot.py doctor
python tools/godot.py editor
python tools/godot.py run
python tools/godot.py check
python tools/check_structure.py
python -m unittest discover -s tests -p 'test_*.py'
```

新开局选杂役、雀妖或戒中残识之一；不同身体有不同操作入口，详见[功能清单](docs/FEATURES.md)。

Codex项目工具：`python tools/setup_codex.py`生成本机项目配置；Godot AI连接由编辑器dock的Configure → Codex生成。配置归属与MCP排错见[TOOLCHAIN](docs/TOOLCHAIN.md)，不要覆盖用户全局模型/权限配置。

## 开发入口与目录

[AGENTS](AGENTS.md)是开发规则，[ROADMAP](docs/ROADMAP.md)管理顺序，[ARCHITECTURE](docs/ARCHITECTURE.md)说明现有模块，[PROJECT-STRUCTURE](docs/PROJECT-STRUCTURE.md)规定文件职责。[长期方案](docs/plans/full_game_program.md)与[未来验收](docs/plans/full_game_acceptance.md)是目标，不代表功能已实现。

```text
scripts/   sim/规则、runtime/适配、persistence/文件、world/entities/ui
scenes/    场景装配
data/      definitions/内容规则、scenarios/开局装配
assets/    美术、音频、字体与来源
design/    systems/规则、research/研究
docs/      状态、plans/工作包、qa/证据、archive/历史
tests/     规则/整合/工具测试与真实旧档
tools/     Godot脚本、MCP包装与本机配置
addons/    第三方插件，不手改
```

项目技能位于 `.agents/skills/`，Codex按任务加载；来源与许可见[第三方说明](THIRD_PARTY_NOTICES.md)。项目自身代码许可证尚未选择；资源候选不等于已获授权安装或使用。

# 当前接续

2026-11-07：当前包是中/英术语与代码入口整改。实现、import、定向10组和真实HUD核对已完成，准备提交及一次Sol/custom静态审查。没有运行中的Goal或测试；不恢复旧Goal或自动推进玩法。

## 当前工作

- 分支`codex/sparse-world-execution`，本包起点`d27337d67c0148132dfaef2d802d72a860b62d38`，包含上轮待提交的术语规则。未切分支或自动合并main。
- 唯一术语入口是[术语与代码映射](../engineering/terminology.md)；现行设计、工程、计划与状态使用真实名称。历史QA/archive、fixture、第三方及历史ADR原文保留。
- 当前运行成员和调度domain是`RegionalSimulation.environment_fields`；存档schema43/根52仍使用JSON键`local_heat`，由`SNAPSHOT_KEYS`显式映射。无运行时兼容getter/第二环境owner。`ReolContentDB.local_heat`仍是热设备定义参数。
- 本包Godot4.7.2 import、定向10组1203断言与RTX3060真实HUD核对通过。Godot AI当前无session，截图经同版CLI生成；没有改桥或依赖。日志及具体边界见[本包QA](../qa/20261107_terminology.md)。
- 在真实提交检查点一次查得[CI42356120868](https://github.com/fewnfds/reol/actions/runs/42356120868)仍in_progress，完整headSha是起点d27337d。留待下次真实提交点，不轮询、不等待；本包完整CI尚无准确SHA通过证据。

## 游戏接入状态

Git main/origin/main仍`eff27a7dcf77031a4084258cc688bbb3616b64e4`，游戏代码与已验`6137481a07ec98b372e32ca857e546f1e1b07ee1`相同。开发分支的通用参与索引及环境/健康稀疏执行普通Main已用，尚未合入main；旧`ee3504d`本机完整check和一次Sol/custom审查通过，但`2f305de`的CI42345202281在1800秒超时，不能算远端通过。计时工具已经落地，后续按真实CI计时定位，不恢复旧session或重扫日志。

技术接入/缺口查[总表](technical-status.md)，准确证据查[BASELINE](baseline.md)，操作查[FEATURES](features.md)，分支和保护草稿查[分支页](branches.md)。命名包不新增游戏机制；下一实现包须重新明确单一范围，顺序以用户授权及[基础优先级](../plans/foundation-priorities.md)为准。

## 保护工作

四份原环境WIP仍在命名stash`424f956d280fb390d17e1f6dd879f3614b51a430`，不自动应用；逐字备份与清单在`logs/world_engine_finish/protected-wip/`。95份原验收证据在`logs/world_engine_finish/validation-artifacts/`。来源与安全边界已记录于[分支页](branches.md)及[收尾QA](../qa/20261107_world_engine_finish.md)，不要重复搬回活跃计划。

# 当前接续

2026-11-07：当前包是参考工作流与测试成本调查。实现及定向验证已完成，准备阶段提交和一次只读原生审查；**没有运行中的Goal或测试。** 不恢复旧Goal或自动推进游戏玩法。

## 当前代码与已验范围

- 根工作树在`codex/sparse-world-execution`；本轮起点本地/远端`d4e5f716aa1cd9fb84b47727160506c2b63addc9`。本包改工程工作流、测试运行器/工具和CI计时artifact；未切分支、改生产游戏代码或自动合并。
- Git main/origin/main均`eff27a7dcf77031a4084258cc688bbb3616b64e4`。其游戏代码与已验`6137481a07ec98b372e32ca857e546f1e1b07ee1`相同。
- 开发分支的通用参与索引及环境/健康稀疏执行，受检代码`ee3504d3c313aa07ac4e87caec3bd39488c725e3`，本机完整check及一次Sol/custom审查已终态通过；普通Main已经使用，但**尚未合入Git main**。旧session96715/66478均已结束，不接续或重跑。
- 相关`2f305de`的CI42345202281已知终态failure，完整SHA一致；Godot test在1800秒上限退出124。本轮复用已存终态与日志，没有重查。末条RUN地形编辑不等于根因；当前五组有界计时不能解释全部超时。
- 本包Python60项、Godot五组54894断言及列举/去重/非法参数/报告失败smoke已通过。默认仍248组，完整CI待后续准确SHA结果；有逐组计时后在下一真实提交检查点集中诊断，不轮询。数据及日志见[调查QA](../qa/20261107_test_cost_audit.md)。
- 技术接入/缺口统一查[总表](technical-status.md)，数字与CI查[BASELINE](baseline.md)，操作查[FEATURES](features.md)，分支与保护草稿查[分支页](branches.md)。后续顺序仍只由用户授权和[基础优先级](../plans/foundation-priorities.md)决定。

## 当前包边界

参考项目按职责借鉴，不整体搬迁目录；稳定契约仍进Git，阶段研究/历史不默认作为当前依据。已补代码包收尾的文档更新闭环、永久测试准入、最小fixture及CPU/GPU验证边界，现行方法见[测试策略](../engineering/workflow/testing.md)。原有测试组/断言、CI覆盖和超时上限均保留，未宣称整套测试已提速。

本包未运行全量Godot回归或实时画面；生产功能范围仍查技术总表，不把计时工具算新玩法。提交检查点复用已登记终态；push后不另开查找/等待，不扫testlog、不派等待代理。下一实现包须重新确定单一范围。

## 保护工作

四份原环境WIP仍在命名stash`424f956d280fb390d17e1f6dd879f3614b51a430`，不自动应用；逐字备份与清单在`logs/world_engine_finish/protected-wip/`。95份原验收证据在`logs/world_engine_finish/validation-artifacts/`。来源与安全边界已记录于[分支页](branches.md)及[收尾QA](../qa/20261107_world_engine_finish.md)，不要重复搬回活跃计划。

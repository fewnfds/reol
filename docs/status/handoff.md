# 当前接续

更新：2026-11-11。本轮任务是代码与项目记忆整顿，结果提交并整合到main。性能实验已按用户要求停下；下一开发阶段先讨论，不自动恢复候选或长测试。

## 接手入口

- [代码入口](../../scripts/README.md)给出新局、运行、结算和存读的阅读顺序；[owner表](../engineering/architecture/02-owners.md)定位原状态。
- [唯一计划](../plans/foundation-priorities.md)保留阶段范围和暂停的候选；[BASELINE](baseline.md)保留当前版本、近期性能与本轮短验证。
- 旧性能实验已移入[历史记录](../archive/qa/20261111_performance_experiments.md)，默认不读、不继续其中的下一步。

## 本轮整顿结果

退役热量模拟、旧迁移链、独立环境验收会话、boot/继任原型和旧测试旁路已删除；设备参数只由`ThermalDefinitions`验证。新局装配归`WorldOpening`，世界捕获/独立候选恢复归`RegionalSnapshot`；领域目录与restore factory移到persistence。模拟规则不再引用呈现层的地图常量，JSON值处理复用`SnapshotValues`。

有效CPU批、来源GPU候选、同规则CPU回退与共同因果续算保留。AGENTS和基础边界已精简，性能历史与当前事实分开，工程页的旧接口/已退役测试声明已修正。可选`check_structure.py --audit-code`供下次定位静态引用疑点，不是新的门禁。

仍有较大的领域owner和公开Dictionary；本轮重点是删旧、去重和分开职责，不把目录整理当成完成全部玩法审计或类型化重写。300人混合活动的偶发长帧与目标整机验收仍未解决，准确范围见BASELINE。

## 工作区与受保护内容

当前分支、dirty和远端以Git为准。未完成性能实验已停，无需补跑旧CI/回归；临时检查和原报告在忽略的logs，未改写fixture、内容或用户存档。

- 保留`codex/field-contest`（`4e17c5c165cf8fca9ef884a111aa1c3ca35f445f`）及其他已有工作分支。
- 原stash `424f956d280fb390d17e1f6dd879f3614b51a430`原样保留。
- 退役测试WIP仍在忽略的`logs/retired-test-workflow-20261111-012331/`，不恢复为任务。

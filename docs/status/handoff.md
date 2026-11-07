# 当前接续

2026-11-07当前任务：用户明确授权主计划第一阶段的plan→coding→review→push，并要求主代理创建Goal。Goal已active，分支`codex/world-space-actions`，起点`b3ae3399d24e01975d231cd000c0af342740070b`。目标及边界沿[唯一主计划](../plans/foundation-priorities.md)，现有18份研究/计划文档先独立提交，代码包继续到阶段出口。

## 本阶段执行与验收

1. 复用原地面/结构局部索引，接身体的原位置变化与恢复；组合有预算、明确范围/共同时间的实时空间查询，保留历史快照合同。原owner提交变化后维护相关候选并通知消费者，未知/欠算不伪装空集。
2. 从已有耗时取放与施工提炼实际共用的条件/占用、时序、终态和清理接缝，效果仍由原生命周期/建筑/库存提交。普通Main使用这些接口，保留能力、观察和权限边界。
3. 以不同布局、跨格/多格、创建/取放/建拆、途中条件改变、取消与在途保存/完全停开恢复验证同一事实；先定向，最终一次完整check，实际普通入口观察和有界成本证据。一次原生Sol/custom静态审查后修复、提交并推送，不自动合并main。

本阶段不提前实现通用植物、多工地/任意家具、全局动态绕路、房温或自由背包。新接口不复制原物/位置、不新增世界时钟或历史重放模型。Godot4.7.2 doctor与review_model检查通过；起点18份文档备份于`logs/framework_stage1_20261107_113554/`，受保护旧分支/stash保持不动。当前进程状态沿本阶段收尾记录，不复用前序handle。

实现已接原位置writer、`SimWorldSpace`实时局部查询/冻结变化和恢复重建、`SimActionContract`取放/施工共用条件/占用/复核/释放/终态；普通F8移除和实物面板已用共同接口。新增`test_world_space`，原过程和运行层定向已通过；普通Main两份在途档已用独立进程验证同checkpoint/完整未来。最后补齐首次准备前及失败重建后的通知订阅，最终定向3组443断言通过，最终代码普通Main再次独立write/read通过且完整快照SHA保持一致。正在准备代码提交，随后一次原生审查、一次完整check和分支推送。详见[本阶段QA](../qa/20261107_world_space_actions.md)；准确未提交状态以Git为准。

2026-11-07：用户授权的已有工作收尾与主线集成已完成，根工作区回到main。通用参与索引、环境/健康稀疏执行、普通环境入口命名、测试4片CI及顶层框架/术语/等待策略文档均进入主线；本轮没有新增游戏功能或移植旧实验。完整实时提交和未提交状态以Git为准。

## 集成与验证

- 最新代码提交为`f166cdb4360e91055a3f942cedf66ae446f2301e`，后续只整理Markdown/项目技能；main从`eff27a7dcf77031a4084258cc688bbb3616b64e4`快进，保留开发历史。本轮仅推送main，其他已合分支保留历史引用。
- 代码提交与已审查对象`2b9828040343e53a469ec8cdce5f12df16656e31`的parent、完整tree及8份文件哈希相同。复用一次Sol/custom静态审查、本机4片完整248组/124981断言/0失败、Python72项和错误退出smoke；没有重复长回归或模型审查。一个未改组的墙钟预算循环计数波动已有单独证据，未删断言或放宽门禁。
- 第一阶段文档提交检查点一次发现并登记[CI42365643089](https://github.com/fewnfds/reol/actions/runs/42365643089)，headSha `b3ae3399d24e01975d231cd000c0af342740070b`相符，工具核completed/success；这是起点main的证据，不代替本阶段新代码。未额外轮询或取消run。
- 完整来源、审查复用、备份与隔离边界见[集成QA](../qa/20261107_mainline_cleanup.md)；本轮之前的测试成本、每片耗时与计数差异见[优化QA](../qa/20261107_test_optimization.md)。全部验证/审查进程已终态，不复用旧handle。

## 开发入口与边界

- 领域职责只看[顶层框架](../engineering/architecture/05-framework-domains.md)，建设依赖/出口只看[基础建设计划](../plans/foundation-priorities.md)，实际能力/缺口看[技术总表](technical-status.md)，操作看[FEATURES](features.md)，准确证据看[BASELINE](baseline.md)。本轮收尾不自动启动下一框架。
- 术语和真实代码定位见[唯一映射](../engineering/terminology.md)。当前普通环境成员为`RegionalSimulation.environment_fields`，区域存档schema43/根52仍通过codec使用JSON键`local_heat`；只有一套当前运行模型。
- 长验证有独立工作就继续做，只剩测试时由一次工具编排持有同一handle等待终态；模型不每60秒续等、不读日志数PASS、不重复报告无变化。规则已写入AGENTS与测试/审查工作流。
- Context7认证已通过真实4.7文档查询；key保存在Windows用户环境变量，本机Git忽略配置只引用变量名。共享仓库不包含认证值。

## 保护工作

`codex/field-contest`的`4e17c5c165cf8fca9ef884a111aa1c3ca35f445f`是旧根43的未完成争环实验；4份环境草稿在命名stash `424f956d280fb390d17e1f6dd879f3614b51a430`，两者保持隔离、不应用、不删除，不算待发布正式功能。用途见[分支页](branches.md)，原备份在`logs/world_engine_finish/protected-wip/`。

主线收尾开始前89份文件及差异保存在`logs/mainline_cleanup_20261107_184537/`；前序架构文档重构/English名称整理均已纳入已完成文档提交，原文件内容可从本机备份与Git追溯。运行代码无待收尾修改；当前研究文档的未提交状态以Git为准，不留测试、审查或等待进程。

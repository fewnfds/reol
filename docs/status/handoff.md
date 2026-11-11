# 当前接续

更新：2026-11-11。当前按轻量功能试游的反馈修复可玩问题，已改用数值开发HUD和同格对象检查。没有active或paused goal，不恢复旧容量攻坚；分支、提交和推送状态以Git为准。

## 接手入口

- [功能试游入口](../engineering/tooling/usage.md#功能试游)说明启动、存档和导览位置；体验步骤只在游戏内维护。[主计划](../plans/foundation-priorities.md)维护范围；[BASELINE](baseline.md)维护实测证据。
- [计算接入](../engineering/execution-batches.md)是直接领域逻辑、事件/分频、CPU批与GPU场的唯一选择指南，按需使用，不要求所有功能实现统一接口。具体领域只查[工程地图](../engineering/README.md)。
- [代码入口](../../scripts/README.md)、[owner表](../engineering/architecture/02-owners.md)定位原状态；[FEATURES](features.md)定位可玩操作。当前只支持最新存档，见[compatibility](../engineering/compatibility.md)。

## 本轮接续

试游通过独立场景继承普通Main，复用原双聚落及领域；初始设施带真实材料回执，之后沿普通动作。导览是场景专用UI，没有新增计算内核、玩法后端或存档格式。

会话可选择独立保存槽；生活面板的用户开关与身份/交锋可用性分开，避免刷新强行弹回。普通Main使用同一数值开发HUD，原保存槽保留。

开发观察及选择入口只查[操作](features/controls.md)，其线程/快照边界见[呈现](../engineering/architecture/03-time-space-presentation.md)。NPC的同格画面挪位已删除；这没有新增人群碰撞/避让。结构感知消耗与实际遮光已分开，定义与规则只查[建筑合同](../engineering/construction-contract.md#几何围合与用途)；含旧建筑定义的开发档需新开局。

上一轮计算接入与项目记忆整顿已提交；当前实现查工程指南，旧研究调用链及测量在[历史](../archive/qa/README.md)。临时验证脚本、截图及日志仍在忽略的logs，不恢复旧测试或容量队列。

## 受保护内容

- 保留codex/field-contest（4e17c5c165cf8fca9ef884a111aa1c3ca35f445f）及已有工作分支。
- 原stash 424f956d280fb390d17e1f6dd879f3614b51a430原样保留。
- 退役测试WIP仍在logs/retired-test-workflow-20261111-012331/，不恢复。门仍自由穿行并保持房间，锁门后续再议。

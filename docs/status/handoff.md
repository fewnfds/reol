# 当前接续

2026-11-07：用户授权的基础建设第一阶段plan→coding→review→push已达到交付出口，保留在`codex/world-space-actions`，不自动合并main。Goal按实际推送终态关闭；当前Git指针与未提交状态以Git为准。起点`b3ae3399d24e01975d231cd000c0af342740070b`，唯一施工顺序仍是[基础建设计划](../plans/foundation-priorities.md)，没有新增第二份计划。

## 本阶段交付

- 世界地块与空间、实体/物品接入：`SimWorldSpace`组合当前身体、地面器物/数量堆、蓝图/结构与固定组件，有界实时查询、冻结变化、恢复重建和旧handle失效；原地面/结构索引、身体位置、器物与账本继续由原owner持有。
- 单位行动与交互：`SimActionContract`让耗时取放/施工共用原身体条件/占用、执行复核、自主权与原预约释放、终态投影。原阶段/截止时间/成本及效果未迁到第二套执行器；普通实物面板与F8移除已使用共同接口。
- 实现`fa45228`，审查修复`5fd6e3152464fd30320ac858d28c19caaea46559`，最终受检代码/测试`f50f0a84085294faf72e6315e99aa5343e7dbf15`。随后仅整理本阶段Markdown证据；完整提交记录在Git。

## 验证与审查

- Godot4.7.2 stable doctor、导入和review_model核对通过。一次原生`gpt-6.1-sol`/custom静态审查发现3项P2，均已修复并用对应反例验证；未递归审查或运行重复审查者。
- 最终准确代码本机完整check **249组/125102断言/0失败**，约1286秒，结构/导入/脚本错误门禁及退出码均通过。前轮唯一热拓扑夹具类型不适配已接当前authority，原断言保留并补终态，不修改产品代码凑绿。
- 普通Main原物取放及施工两份在途档已完全停止游戏进程后独立恢复，checkpoint及完整未来SHA相同，原截止时刻与成本保留；实际取放/施工界面已查看。两格实时查询1000次约59.8ms，仅局部CPU样本。
- 完整范围、首轮失败、审查修复及日志见[本阶段QA](../qa/20261107_world_space_actions.md)。本机验证/编辑器/审查/等待进程均已结束，不复用旧handle。
- 起点main的[CI42365643089](https://github.com/fewnfds/reol/actions/runs/42365643089)已核完整SHA一致且success。本阶段分支推送将触发现有CI，远端结果未核验；留到下次真实提交检查点，不立即查询、轮询或声称回调能唤醒聊天。

## 后续入口与边界

下一交付仍是主计划第二阶段“通用建筑与组合空间”：多定义、多格结构/家具、多处施工及围合/屋面/用途区域复用。此处记录依赖关系，不自动启动新范围。通用植物、完整动作整合/绕路、跨账本搬运、房温及自由背包继续按原领域和主计划推进。

领域职责查[顶层框架](../engineering/architecture/05-framework-domains.md)，已接范围/缺口查[技术总表](technical-status.md)，操作查[FEATURES](features.md)，版本证据查[BASELINE](baseline.md)，真实代码名查[唯一映射](../engineering/terminology.md)。当前根52/区域43/村落7不变；只维护一套运行模型和写档格式。

## 保护工作与环境

`codex/field-contest`的`4e17c5c165cf8fca9ef884a111aa1c3ca35f445f`旧根43争环WIP及命名stash `424f956d280fb390d17e1f6dd879f3614b51a430`的四份环境草稿均保持隔离，不应用、不删除。来源见[分支页](branches.md)与[主线集成QA](../qa/20261107_mainline_cleanup.md)。阶段前18份文档备份在`logs/framework_stage1_20261107_113554/`；既有89份收尾备份在`logs/mainline_cleanup_20261107_184537/`。日志、截图、存档与本机配置不入库。

Context7认证使用用户环境变量及Git忽略配置，仓库不含key。长验证只剩等待时以一次工具编排持有同一handle到终态，未按时间查询CI或让模型定期读PASS。

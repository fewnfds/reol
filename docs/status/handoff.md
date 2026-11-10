# 当前接续

2026-11-10：用户允许必要时从Hello World重建；文档/项目数据清理已完成。本轮按要求将剩余代码原样提交为重构前WIP保留点，并为A建立干净开发分支。新运行实现尚未开始，未创建Goal。

## 当前依据

- [唯一主计划](../plans/foundation-priorities.md)：P01–P16核心问题、S01–S12联合验收、A–D四个交付包；取代旧六阶段及零散算法队列。
- [执行规格](../specs/world-engine/execution.md)：计算粒度、热数据、局部因果、CPU/GPU批执行、空间/AI、呈现与长期成本。
- [领域划分](../engineering/architecture/05-framework-domains.md)维护逻辑职责，现有class/schema/数据结构/同步链可替换。身份、原物、因果、认识与失败原子性继续保护。
- 下一实施包是A：用普通可玩纵向链路交付共同运行/数据底座及真实CPU并行，同步核对GPU接缝；不用先把旧单线程局部优化完。大范围重构已获授权，常规内部实现不重复询问。

## 工作区与保护

当前分支`codex/execution-foundation`，从`codex/navigation-data-reuse`的保留点建立。文档清理提交`95eac7d624b39d12fe36ba2b936ac342e7bcee89`；原有8份GDScript以`10260b3b45952b7b45055e807f360824227efce2`单独WIP提交，均未推送。已核完整CI的代码祖先仍为`8c3deaa972f932e999167b61ea6b166b928cfe5f`。

8份GDScript保持字节不变：地形/导航复用、局部身体查询与隐藏视图、交谈候选和压力驱动，以及对应回归。WIP提交用于保留工作，未完成主审/完整回归/最终性能验收；可按新结构保留、替换或放弃，不作为必须收尾的旧队列。按项目工作流不对备份WIP启动原生模型审查。

上次定向7组637检查/0失败，日志`logs/test-20261110-230001.log`与`logs/test-timings-1794322801789678300.jsonl`；导航/地形6组898检查日志`logs/test-20261110-223722.log`。它们只证明受检补丁，不是新架构验证。

本轮只核对差异、123份保护文件SHA256、结构/链接及Git范围；doctor和项目review_model配置核对通过，没有运行游戏或新增行为回归，没有活测试、审查或终端handle。保留点辅助证据在忽略的`logs/pre-rewrite-code-checkpoint.json`。

57份JSON均有代码/测试引用并保留原字节，包含旧兼容基线；`tests/fixtures`同样不改写。数据分工见[data](../../data/README.md)。清理前本地文档副本及精确删除清单在忽略的`logs/rewrite-reset-backup/`、`logs/rewrite-reset-manifest.json`；入库旧文档可按固定Git SHA追溯。

## Git与验证边界

main/origin/main保持`839ff88f1b7fee240d0c798f533314a3ae446430`，无自动合并。旧争环分支`4e17c5c165cf8fca9ef884a111aa1c3ca35f445f`及命名stash `424f956d280fb390d17e1f6dd879f3614b51a430`不恢复/删除。

旧main CI42776609463已核success；本次真实提交准备点通过`tools/ci.py status`核对`8c3deaa972f932e999167b61ea6b166b928cfe5f`的[CI42833827684](https://github.com/fewnfds/reol/actions/runs/42833827684)已completed/success。这只证明该代码祖先，不覆盖WIP保留点或新运行架构；本轮提交没有远端CI。旧失败/夹具修补详情见[BASELINE](baseline.md)。不轮询，不声称已接GitHub完成→聊天回调。

本次清理的实际范围与验证在[重构节点记录](../qa/20261110_execution_rewrite_reset.md)。新模型尚未实现，GPU独立服务和Godot渲染线程都不算普通模拟已加速。

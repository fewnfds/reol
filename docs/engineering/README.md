# 工程索引

本目录保留稳定工程约束及现存Demo接口参考。[领域职责](architecture/05-framework-domains.md)是逻辑边界；其余带具体class/API的合同说明当前实现，不要求重构保留相同类、存储或调度。目标结构见[执行规格](../specs/world-engine/execution.md)，实施范围见[主计划](../plans/foundation-priorities.md)。

## 共同约束

- [架构与目标硬件](architecture.md)、[文件放置](project-structure.md)、[术语映射](terminology.md)。
- [依赖方向](architecture/01-dependencies.md)、[现有owner定位](architecture/02-owners.md)、[时间/空间/呈现](architecture/03-time-space-presentation.md)、[存读](architecture/04-persistence.md)。
- [兼容政策](compatibility.md)：一个当前模型、明确支持范围、候选失败不改活世界。

## 现有实现参考

- [结算](settlement-contract.md)、[批计算与采用](execution-batches.md)、[事件](event-contract.md)、[运行流速](simulation-pacing.md)、[参与索引](sparse-execution.md)。
- [对象查询](object-query-contract.md)、[原物生命周期与行动](object-lifecycle-contract.md)、[建筑](construction-contract.md)、[植物](plants-contract.md)、[普通环境](world-environment-contract.md)。

旧隔离场/cache/GPU接口的细节随对应[QA证据](../qa/README.md)按Git版本追溯，不作为新环境的强制实现。复用、改写或删除由真实需求及验证决定。

## 工作流和工具

- [测试](workflow/testing.md)、[审查/CI](workflow/code-review.md)、[AI开发流程](workflow/ai-development.md)。
- [工具使用](tooling/usage.md)、[配置](tooling/setup.md)、[维护](tooling/maintenance.md)、[选型方法](tooling/evaluation.md)。
- [Godot与Unity对应](godot-for-unity.md)：学习资料，不是本项目所有系统的实现方案。

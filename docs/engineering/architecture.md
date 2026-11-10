# 架构与工程边界

目标结构由[执行规格](../specs/world-engine/execution.md)定义，范围/问题与验收由[主计划](../plans/foundation-priorities.md)定义。[领域划分](architecture/05-framework-domains.md)维护七个逻辑职责；现有class、索引和调用链可替换。

本目录其余接口页用于定位重构前Demo及有效合同，不证明新结构已完成。实际能力/证据见[技术起点](../status/technical-status.md)与[基线](../status/baseline.md)。

## 全项目性能基线

目标平台是 **PC、16GB整机RAM、单张RTX3060级显卡**。允许合理使用约10GB进程内存，这是可接受量级，不是必须填满的预算；仍需为系统和图形等留余量。不同显卡分别记录，不相加算力/显存，不以移动/Web限制本项目方案。

CPU多核、GPU和数据/模型共同设计，以普通游戏的端到端吞吐、帧时、输入响应和积压采用；缺设备有明确回退。不为省少量内存增加无收益的复杂度，允许合理缓存/预计算，控制真实无界增长。

整机目标、模块估算、临时守卫和实测是不同数字。32GB开发机结果不代表16GB整机验收。记录准确SHA/差异、内容/命令、CPU/单张实际GPU、整机RAM/显存、运行/导出模式、冷启动/预热、重复次数、P95/P99和峰值；初始化、稳态与存读分开核算。具体场景和增长曲线由主计划定义。

每次性能样本预先声明有限超时与内存守卫，按实际可用RAM/显存及已有进程留余量；仅协调本项目所属进程，不并发压力任务，不为跑完绕过守卫。

## 实现参考

- [依赖](architecture/01-dependencies.md)、[现有状态定位](architecture/02-owners.md)、[时间/空间/呈现](architecture/03-time-space-presentation.md)、[存读](architecture/04-persistence.md)。
- [结算](settlement-contract.md)、[批计算与采用](execution-batches.md)、[事件](event-contract.md)、[流速](simulation-pacing.md)、[参与索引](sparse-execution.md)。
- [原物/查询](object-query-contract.md)、[生命周期/行动](object-lifecycle-contract.md)、[建筑](construction-contract.md)、[植物](plants-contract.md)、[普通环境](world-environment-contract.md)。

来源、缓存及静止响应的旧隔离合同通过[QA](../qa/README.md)和固定Git版本追溯，不作为普通世界已GPU加速的依据。

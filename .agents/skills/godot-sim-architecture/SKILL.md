---
name: godot-sim-architecture
description: 修改Reol共同时间、跨域状态、批执行或恢复边界时使用。
---

# 模拟架构变更

全局不变量只查[constraints](../../../docs/engineering/constraints.md)，逻辑分工查[领域职责](../../../docs/engineering/architecture/05-framework-domains.md)。当前接口通过[工程地图](../../../docs/engineering/README.md)选读，不把目标规格当已实现结构。

先指出本次实际读写哪些原状态、依赖哪个逻辑区间、工作由何种变化或到期唤醒、结果在哪里采用。性能问题量出准备/计算/提交成本后再选择热数据、任务粒度和设备；不要在每个领域复制调度器。

取消、对象替换或读档影响了本次接口时，明确哪些候选作废、哪些已提交事实保留；只验证相关反例。详细方法需要时读[时间与持久化](references/time_and_persistence.md)，验证强度遵循原开发循环。

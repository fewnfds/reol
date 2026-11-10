# 当前运行装配

类型：实现参考。职责查[领域划分](architecture/05-framework-domains.md)，稳定技术/硬件边界查[constraints](constraints.md)，目标与当前结果分别查[主计划](../plans/foundation-priorities.md)和[BASELINE](../status/baseline.md)。

```text
Main / 场景装配
  输入与UI → runtime适配 → sim状态、规则和过程
                  ↓              ↓
             已提交视图      data定义与开局
                  ↘ persistence文件/候选恢复
```

当前业务时钟为`GameClock`，共同结算由`RegionalSimulation`装配的`SimSettlementKernel`推进；身体批计算用`SimBatchExecution`，结果由原领域采用。Godot负责SceneTree、呈现、资源及适用的原生几何/线程能力。普通环境对象为`SimWorldEnvironmentFields`，旧独立GPU服务没有因此自动接入。

- [依赖方向](architecture/01-dependencies.md)解释代码层；[owner表](architecture/02-owners.md)定位状态来源，不表示每域需要一个Node或同一巨型对象。
- [时间/空间/呈现](architecture/03-time-space-presentation.md)定位连续身体和已提交视图。
- [存读管线](architecture/04-persistence.md)说明独立候选、领域登记和文件边界。
- 具体算法接口按[工程地图](README.md)查询。调用链、数据布局和class均可重写，存在接口不证明规模性能已达标。

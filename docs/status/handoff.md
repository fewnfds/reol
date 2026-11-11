# 当前接续

更新：2026-11-11。首要任务仍是普通游戏的性能，用户已授权逐篇研究、按实测逐项尝试和大范围重构。资料来源与适用限制在[研究页](../../design/research/large_simulation_optimization.md#用户参考网址逐篇核对2026-11-11)，所有候选及状态在[唯一主计划](../plans/foundation-priorities.md#参考资料驱动的实验清单2026-11-11)。接续从已有结论出发。

## 当前证据与实现边界

- [同一发布包复核](baseline.md#同一发布包的持续巡行复核)：RTX5060Ti与RTX3060上，300人125秒都无主动缓行，仍有少量长帧；512人20秒仍有短时降速。固定镜头巡行未覆盖真实生产、连续战斗或全部人物同屏；RTX3060实测沿用开发机的CPU和约32GB内存，整机验收仍未完成。
- [稀疏执行](../engineering/sparse-execution.md)：读取已受理轨迹不物化全体身体；移动只有实际环境、认识、空间消费者时唤醒对应规则；相交或未知路线才因局部几何变化失效。认识保存每事一份原文、个人紧凑获取索引；现有根版本内可读旧认识档，已做实际联合恢复。
- [环境合同](../engineering/world-environment-contract.md)：普通内部来源候选实际采用常驻GPU，协调器仍一次提交场和身体响应；冷块、同步外部命令及设备失败走CPU。相同版本CPU/GPU的对照已完成。
- [发布与节奏](../engineering/simulation-pacing.md)：规则完成可保留原pending最多一宿主帧。排队攻击由`ConflictRuntime._on_advanced`受理，`ConstructionRuntime._on_advanced`处理视野，之后才捕获统一画面。人物用原生Sprite2D/共享shader消费已提交时间和姿态。
- 已撤回的主要路线：身体与到期索引的类型化迁移、降低worker起批阈值、整批画面延期、增量布局缓存和固定镜头的可见性改造。共享反向导航、局部连通性和MultiMesh有隔离证据；保留为对应负载的候选。详细保留与放弃依据见[BASELINE](baseline.md)。

## 下一工作包

用同一release入口从巡行扩到**300人混合负载**：持续行走中加入真实搬运/交互、动态来源/结构和移动观察；按已具备的战斗能力加真实交锋。分别看1×、超16.67ms的频率和最大帧，确认长帧落在规则、命令、发布还是渲染等待。按可复现的最大成本决定架构改动，有目标整机时用同一场景复核。普通巡行A*占比小；密集同目标或不可达开始主导时才推进共享/分层导航。持续复制或分发开始主导时，优先收敛该数据所有权和批量采用边界。

复现入口见[实际性能](../engineering/tooling/usage.md#实际性能)。临时探针须使用当前`scripts/diagnostics/`实现；旧路径或继承旧完整SceneTree的探针只作历史。按[短验证](../engineering/workflow/testing.md)工作，不恢复旧CI或全量测试。

## 工作区与受保护内容

分支、dirty和主线指针以Git为准。实现未自动合main；原报告与临时探针在忽略的logs。无待恢复插桩、身体迁移或待等采样。

- `codex/field-contest`，`4e17c5c165cf8fca9ef884a111aa1c3ca35f445f`：隔离旧争环实验，保留。
- stash `424f956d280fb390d17e1f6dd879f3614b51a430`：原样保留。
- fixture、内容和用户存档未改写。旧测试WIP在忽略的`logs/retired-test-workflow-20261111-012331/`，历史入口见[归档](../archive/README.md)。

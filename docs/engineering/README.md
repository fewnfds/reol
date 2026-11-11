# 工程接口地图

类型：按需实现参考。稳定边界只在[constraints](constraints.md)，逻辑分工只在[七个领域](architecture/05-framework-domains.md)。下面的class/API定位当前代码，可随重构修改；实际结果看[BASELINE](../status/baseline.md)。

| 处理的问题 | 先查哪里 |
|---|---|
| 运行装配、分层与状态owner | [architecture](architecture.md)、[owner表](architecture/02-owners.md) |
| 调度、共同时间、同刻结算 | [settlement](settlement-contract.md)、[pacing](simulation-pacing.md) |
| 新计算归类、CPU/GPU接入、线程/结果生命周期 | [execution-batches](execution-batches.md) |
| 离散到期/触发事件、失效 | [event](event-contract.md) |
| 活动、到期、变脏集合与局部查询 | [sparse-execution](sparse-execution.md) |
| 空间查询、容器位置与生命周期 | [object-query](object-query-contract.md)、[object-lifecycle](object-lifecycle-contract.md) |
| 墙、门、家具、房间与施工 | [construction](construction-contract.md) |
| 植物、产物、环境输入 | [plants](plants-contract.md)、[world-environment](world-environment-contract.md) |
| 保存管线、候选恢复、支持范围 | [persistence](architecture/04-persistence.md)、[compatibility](compatibility.md) |
| 连续位置、动作、已提交画面 | [time-space-presentation](architecture/03-time-space-presentation.md) |
| 文件放置、定义和代码标识 | [project-structure](project-structure.md)、[terminology](terminology.md) |
| 测量/短验证、运行/编辑器连接 | [workflow](workflow/testing.md)、[usage](tooling/usage.md)、[setup](tooling/setup.md) |

本页只定位正文；当前测量只看[BASELINE](../status/baseline.md)，历史实验需要时显式查[archive](../archive/README.md)。

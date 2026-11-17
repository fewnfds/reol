---
name: performance-optimization
description: 调查或验证Reol的卡顿、模拟吞吐、延迟、内存或CPU/GPU瓶颈时使用；日常实现仍先遵守AGENTS的访问规模约束。
---

# 性能分诊与有效工作

本地重写原performance-optimization；归属见[NOTICES](../../../THIRD_PARTY_NOTICES.md)。写前避免明显访问放大是默认开发要求，**不以“没测所以先全扫”推迟算法设计**；本技能负责判断真实瓶颈和证明改进，不代替领域正确性。

- 固定可比较的场景/存档、人数与活跃量、运行倍率、引擎/构建、硬件和窗口。区分冷启动、稳定负载、周期尖峰与长时增长；有仪器开销时说明。先用现有`tools/benchmark.py`、`capacity.py`、`cpu_sample.py`与诊断，不另造长期遥测框架。
- 分开主线程输入/显示、Runner关键模拟、软服务、后台准备/复制/计算/采用、同步等待和GPU。Godot脚本Profiler不是GPU计时器，也未必完整覆盖自主线程；Visual Profiler/真实渲染与显式计时按需要补证。`Performance.TIME_PROCESS`等时间monitor的单位核官方文档，通常秒，报告ms须换算。
- 所读monitor是否支持release、何时刷新也须确认；部分内置指标在release恒为0，部分最多延迟约1秒更新。恒0不是零成本，连续读同一个采样也不是多次独立测量。
- 统计调用次数×实际读集合、复制/排序/分配、写维护/失效、事件扇出与重试，而非只计函数本体。采样CPU热点不证明谁在等待，headless高模拟速度不证明渲染快。
- 软预算下的低耗时可能是少做工作。和帧时一起核有效完成量、到期/ready/未准入积压、年龄/最坏等待、失败/陈旧丢弃；不能降低模拟速率、遗漏碰撞/知识消费者或不调度远方人物后声称优化完成。
- 年龄诊断覆盖仍未出队和未准入的需求，不能只统计已服务者；按原owner实际结构选有界维护方式，计时/采样本身也有成本。累计`*_usec`可能嵌套或跨线程，不相加冒充CPU利用率；离线完成计数也不能补出缺失的帧尾延迟、工时或公平性。实验与现有日志的口径查[方法](../../../docs/engineering/simulation-methods.md)。
- 选择能减少总工作的结构，再按实测考虑缓存/分片/线程/池化；维护/取消/恢复成本一起计。GDScript引用计数与C#追踪GC不同，不把所有周期卡顿叫GC；容器、字符串和上传分配仍需核。
- 渲染查真实draw calls、透明overdraw、材质/图集切换、缓冲上传与排序；MultiMesh降低提交不自动解决全体更新或排序。降分辨率对照只能帮助定位像素负载，不能独自证明某个shader是瓶颈。
- 同条件短窗比较变化并核完整结果；测量不足就限定结论。未出现新变更、失败或疑点时不无限重复大矩阵，目标也不自动升级为万人极限。

具体读集合与已知反例沿[复杂度范式](../../../docs/engineering/simulation-costs.md)，新结论回原BASELINE/问题页。用必要测量支持本次取舍，不为每个普通实例写成本报告。

官方依据：[General optimization](https://docs.godotengine.org/en/4.7/tutorials/performance/general_optimization.html)、[Profiler](https://docs.godotengine.org/en/4.7/tutorials/scripting/debug/the_profiler.html)、[MultiMesh](https://docs.godotengine.org/en/4.7/tutorials/performance/using_multimesh.html)。

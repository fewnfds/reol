# 工程地图

当前正式后端是重建后的 `scripts/sim/kernel/`，唯一场景入口是 `scenes/main.tscn`。旧世界、全域逐毫秒边界、活世界借还和旧GPU场已移除。旧实现不能从其他文档恢复成开发前提。

| 要找什么 | 唯一正文 |
|---|---|
| 当前状态、写入者、线程与显示边界 | [运行架构](architecture.md) |
| 逻辑领域的长期归属 | [领域职责](architecture/05-framework-domains.md) |
| 自主宗门的迁移前缺口与演进理由 | [共享框架审查](architecture/foundation-audit.md)；当前完成边界看[任务表](../plans/foundation-priorities.md#百人宗门实施任务表) |
| 新计算如何选择直接调用、跨步/后台、CPU批或GPU | [计算接入](execution-batches.md) |
| 系统装配成本、访问范围、窄投影、派生索引和失效 | [复杂度与扩展范式](simulation-costs.md) |
| 共同时间、倍率、过载与精度 | [运行与精度](simulation-pacing.md) |
| 产品与数据边界 | [constraints](constraints.md) |
| 存档支持现状 | [compatibility](compatibility.md) |
| 运行、导出、短检查与性能采样 | [工具命令](tooling/usage.md)、[验证方式](workflow/testing.md) |
| 插件、顾问、技能配置 | [工具配置](tooling/setup.md) |
| 技能领域覆盖、33项删并去向与替代资料 | [覆盖审查](tooling/skill-coverage.md) |

实测只在[BASELINE](../status/baseline.md)，操作与缺口只在[FEATURES](../status/features.md)，施工顺序只在[主计划](../plans/foundation-priorities.md)。

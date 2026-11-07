# 环境首轮方法与历史入口

本目录保存普通接管前的来源、缓存、连续响应及优化方案，属于制定时资料。后续环境建设只按[基础建设与改造计划](../foundation-priorities.md)，当前运行只按[普通环境合同](../../engineering/world-environment-contract.md)；实际支持/缺口及证据分别查[技术总表](../../status/technical-status.md)与[基线](../../status/baseline.md)。

旧正文中的A1/A2、第二阶段、旧Q、根51、待接Main、下一包和停止点均用于追溯，不形成独立施工队列。普通世界接管及有限旧档拒绝已经有现行工程合同和[收尾QA](../../qa/20261107_world_engine_finish.md)，不能按旧起点再次开发。

## 按问题查方法

| 主题 | 原方案参考 | 现行使用边界 |
|---|---|---|
| 来源定义、原物投影与事务 | [sources](sources.md) | 读取[来源查询合同](../../engineering/environment-source-query-contract.md)及普通环境合同；原物/材料仍归原owner |
| 分块缓存与基础目标计算 | [cache](cache.md)、[GPU候选](gpu-ground.md) | 读取[缓存合同](../../engineering/environment-ground-cache-contract.md)；GPU隔离服务不等于普通游戏设置或整机收益 |
| 连续响应与原物共同提交 | [continuity](continuity.md)、[受限响应方案](response-ground.md) | 现行普通响应/事务由普通环境合同描述；旧开发会话和单源边界不决定当前能力 |
| 移动来源、输入、时间与过载 | [scheduling](scheduling.md) | 保留为未接能力的详细候选；按主计划阶段及实际原移动/时间合同核对后采用 |
| 实测热点与有限优化 | [optimization](optimization.md)、[cold-build](cold-build.md) | 结果只对应各QA版本；后续性能改动归原框架和真实瓶颈 |
| 验收方法 | [acceptance](acceptance.md) | 负载与支持范围按主计划及[全项目基线](../../engineering/architecture.md)声明，不沿用旧分包数字担保当前世界 |

## 后续接缝的归属

植物/建筑/身体和携带物的来源与受体、容器影响、房间及材质条件归环境框架；原几何、实物生命周期与行动过程各归原领域。具体职责见[顶层框架](../../engineering/architecture/05-framework-domains.md)，未接范围不从旧方案自动获得实现或授权。

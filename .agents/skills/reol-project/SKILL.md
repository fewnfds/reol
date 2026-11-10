---
name: reol-project
description: Reol入口：读取真实停点，围绕性能目标选择相关代码和少量技能。
---

# Reol 项目入口

Reol是GDScript、2D正交格子的持续世界。用户最新授权优先，旧代码/测试/文档不限制重构。当前首要目标是普通游戏300人1×/60FPS，硬件为16GB RAM、RTX3060级单卡。

先读`docs/status/handoff.md`，再按任务读唯一主计划`docs/plans/foundation-priorities.md`及相关源码。领域职责在`docs/engineering/architecture/05-framework-domains.md`，已确认方向在`design/vision.md`与`design/rules/`。不要默认加载历史QA、全库或所有技能。

旧CI、260组回归、分片和每包自动审查已退役；不要从其他技能重新引入。开发以最大热点和短性能对照推进，必要smoke按改动选择，方法只看`docs/engineering/workflow/testing.md`。引擎/实际性能证据看BASELINE，旧绿色结果不是新架构完成证明。

按需选GDScript、模拟架构、地图、UI或性能技能，工具方法不是新的审批/交付门禁。允许替换内核、存储和执行链；保持状态事实与共同因果，普通运行实际收益决定方案取舍。

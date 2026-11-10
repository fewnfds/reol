---
name: spec-driven-game-dev
description: Reol跨系统需求或架构取舍尚不清楚时，收敛范围和可观察结果。
---

# 收敛设计

明确的小改动直接实施。只有范围/接口不清时才使用这个方法，不为文档模板制造额外任务。

从[领域职责](../../../docs/engineering/architecture/05-framework-domains.md)定位原owner，区分当前事实、用户目标和候选做法。优先修改[现有主计划](../../../docs/plans/foundation-priorities.md)或对应接口页；范围、取舍、预期结果和证据写到一个合适位置即可。

内部小步不成为另一份主计划，也不扩大授权。需要选择真正影响产品方向的未知条件时才澄清，普通技术选择由现有上下文解决。验证按[开发循环](../../../docs/engineering/workflow/testing.md)，不追加完整矩阵。

可选写作提示：[设计](references/design-note.md)、[技术取舍](references/tech-plan.md)、[任务](references/task.md)、[独有决策](references/adr.md)。这些是提问提示，不是必须填写或各建一个文件。

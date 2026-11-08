# 工程入口

本目录说明实际代码所有者、工程约束与工具用法。实现和验证范围查[功能](../status/features.md)与[基线](../status/baseline.md)，当前工作状态查[接续](../status/handoff.md)；历史结果及旧待办不构成现在的任务。

- [代码架构](architecture.md)：顶层框架入口、全项目性能基线、依赖方向、状态所有者、时间空间和存读边界。
- [领域归属与跨域合同](architecture/05-framework-domains.md)：七个顶层框架、原代码定位及建筑/空间/环境/行动等领域的交接；算法在框架内定位。
- [术语与代码映射](terminology.md)：固定中文概念、真实class/字段、不同领域及存档键的对应。
- [稀疏执行框架](sparse-execution.md)：能力成员、当前参与、到期与依赖失效的通用接口和新能力接入方式；普通接入范围按状态/证据核对。
- [项目文件架构](project-structure.md)：代码、数据、设计和文档各放在哪里。
- [兼容与历史退役](compatibility.md)：单一当前模型、有限迁入和独立候选原则。
- [建筑、家具与组合空间](construction-contract.md)：定义/实例/能力、多格与操作位、真实储藏/生产、耐久和损毁的原owner合同。
- [普通世界环境合同](world-environment-contract.md)：室外冷热与五行响应、原物来源事务、共同时间及当前室内边界。
- [环境来源查询](environment-source-query-contract.md)、[地面来源缓存](environment-ground-cache-contract.md)：真实原物投影、基础目标及失效边界，不等同实际环境响应。
- [Godot 给 Unity 开发者](godot-for-unity.md)：引擎和工具的基础对应。
- [AI 开发流程](workflow/ai-development.md)、[测试选择与成本](workflow/testing.md)、[提交审查与 CI](workflow/code-review.md)：开发和验证边界。
- [规则与skill来源](workflow/ai-development.md#规则来源与技能职责)：用户决定、项目规则、技能建议及开发者选择的区别，不把文档增生归因于模板。
- [工具用法](tooling/usage.md)、[实际配置](tooling/setup.md)、[维护](tooling/maintenance.md)、[选型方法](tooling/evaluation.md)：连接与工具维护。旧工具审计在[历史目录](../archive/engineering-context-20261105/)。

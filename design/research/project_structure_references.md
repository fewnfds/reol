# 文件组织参考与 Reol 取舍

> 研究资料：记录来源与适用限制，不授予引入依赖或改变规则的权限。

核查日期：2026-11-02。一手官方/开源来源，不将教学示例或GitHub热度等同商业成功。没有引入或复制依赖代码。

| 来源 | 核实内容 | Reol采用 |
|---|---|---|
| [Godot 4.7 官方项目组织](https://docs.godotengine.org/en/4.7/tutorials/best_practices/project_organization.html) | 场景资源就近、统一命名、第三方边界；gdignore影响运行加载 | 保留简单顶层职责，场景独占资源可就近；测试目录不加gdignore |
| [GDQuest OpenRPG](https://github.com/gdquest-demos/godot-open-rpg) | 教学demo；src/combat、field、common按领域组织，并非完整商业RPG框架 | 模块按玩法责任分组，避免所有新逻辑堆main/runtime；不照搬回合制 |
| [Thrive架构](https://raw.githubusercontent.com/Revolutionary-Games/Thrive/master/doc/architecture.md) | 长期开源Godot/C#项目；模拟玩法与Godot显示/GUI分离，simulation_parameters存JSON | 纯GDScript模拟与场景适配分离，复用参数/引用校验思路；不引入C#/ECS |
| [Endless Sky](https://github.com/endless-sky/endless-sky) | 非Godot的开源C++游戏，data/source/docs和unit/integration测试分开 | 内容、运行状态和验证分责；不照搬其全局对象结构 |

实际核查树：OpenRPG d59f2f7、Thrive b4d86c5、Endless Sky d943c9e。相关细节：[Thrive参数加载](https://raw.githubusercontent.com/Revolutionary-Games/Thrive/master/simulation_parameters/SimulationParameters.cs)、[Endless Sky测试](https://raw.githubusercontent.com/endless-sky/endless-sky/master/tests/README.md)、[Godot ResourceUID](https://docs.godotengine.org/en/4.7/classes/class_resourceuid.html)。

许可仍逐依赖/素材核对：[OpenRPG素材清单](https://raw.githubusercontent.com/gdquest-demos/godot-open-rpg/main/CREDITS.md)、[Thrive许可](https://raw.githubusercontent.com/Revolutionary-Games/Thrive/master/LICENSE.txt)。本轮只研究职责，没有安装这些项目。

由这些来源推导的Reol方案：保留scripts/data/assets/scenes顶层，纯模拟与runtime/persistence分开；定义与开局分开；当前状态/计划/设计/研究/历史分开。没有证据支持为了“像大项目”预建完整ECS、插件框架或几十个autoload。

## Agent-first 流程参考（2026-11-13）

这些资料只用于校准工作方式，不是Reol的额外门禁：

| 来源 | 对本项目有用的结论 | Reol取舍 |
|---|---|---|
| [OpenAI：Harness engineering](https://openai.com/index/harness-engineering/) | 给agent一张地图，不给一千页手册；短`AGENTS.md`指向结构化知识库；用渐进披露、可检查的边界和持续小步清理抑制文档/代码漂移 | 保留`AGENTS → HANDOFF → 文档地图 → 唯一owner`入口；不引入新的harness目录、阶段上下文文件或长日志体系 |
| [OpenAI：How OpenAI uses Codex](https://openai.com/business/learn/how-openai-uses-codex/) | 大改动先问模式再实现；任务按issue描述，范围足够小，验证强度与任务风险匹配 | 现有开发循环采用五步；小任务不写计划，不为“完整”而扩大测试 |
| [OpenAI：Maintaining software with the GPT-6 family](https://developers.openai.com/blog/maintaining-software-with-the-gpt-6-family) | 清理先从小范围和证据开始，复核后再扩大；模型/提示词要用结果校准，旧指令会误导时应删除 | 先改一个owner并核对行为/成本；只有重复失误或大改动才做全局文档清理 |

这些经验支持当前的“少入口、单归属、短反馈环”，不支持把每次对话转成新的规则文件。模型能力或外部流程变化时，先在小任务上验证，再决定是否改本页或开发循环。

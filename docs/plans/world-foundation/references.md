# 世界骨架：公开参考与取舍

以下来源支持具体工程选择，不代表 Reol 已经实现或具备相同容量。观察与推论分开；仅学习思路，不复制未审查许可的代码或资产。

| 来源 | 原项目公开说明 | 对 Reol 的实际选择与边界 |
|---|---|---|
| [Factorio：Optimizations 2.0](https://www.factorio.com/blog/post/fff-421) | 将闲置设施停更，在需要时激活；覆盖区域使用区块登记与分桶更新；机器人可以安排下次事件并平滑呈现；部分并行实验受内存带宽限制。 | 静态对象不逐帧执行，局部变化使索引失效；时间边界与显示插值分开。先测吞吐和分配，再决定分批、多线程或 GPU，不承诺复制其性能。 |
| [Cataclysm: DDA 开发 FAQ](https://docs.cataclysmdda.org/DEVELOPER_FAQ.html) | 区分子地图、地图缓存、活动地图和宏观地图，并说明 NPC 的存储与活动集合。 | 局部查询走分块/空间索引，视觉载入不拥有世界事实；来源不证明所有远区逐帧模拟，Reol 的远区仍须按共同时间及明确近似合同运行。 |
| [Thrive 架构](https://raw.githubusercontent.com/Revolutionary-Games/Thrive/master/doc/architecture.md) | 长期 Godot 项目的模拟、参数和呈现职责分离；原项目使用 C#。项目已有[只读核对](../../../design/research/project_structure_references.md)。 | 使用 GDScript 纯模拟与 Godot 表现适配，定义和实例分开；不因此引入 C#、复制其 ECS 或声称结构完全相同。 |
| [Dwarf Fortress 作者的模拟原则](https://www.gameaipro.com/GameAIPro2/GameAIPro2_Chapter41_Simulation_Principles_from_Dwarf_Fortress.pdf) | 分别考虑环境条件，利用条件关系形成可解释的世界，并强调理解每种模拟的作用。 | 先使时间、空间、对象和可查询状态成为共同基础，再接环境之间的作用；不把写了气候名称当作系统已运行。 |
| [Project Porcupine](https://github.com/TeamPorcupine/ProjectPorcupine) | Unity 教程衍生社区项目；以地块连接推导房间，并将房间过程与储量区分。它不是商业成熟游戏容量的证据。 | 后续参考结构变化如何重建空间关系；房间不能成为独立的物品/温度副本。本阶段只约定空间接口，尚不实现完整房温。社区代码及素材有各自许可证，不复制。 |
| [Godot Resource 指南](https://docs.godotengine.org/en/4.7/tutorials/scripting/resources.html) | Resource 可保存、复用数据并与场景组合；共享资源存在共享状态语义。 | 内容定义与世界实例分开；沿项目现有 JSON/内容包作为权威，不因参考示例并行新增一套定义来源。 |

更多原始技术背景、许可及取舍见[世界引擎研究](../../../design/research/world_engine_references.md)。本目录只解释对第一阶段的具体用途；完成证据在 QA，不用参考链接替代实测。

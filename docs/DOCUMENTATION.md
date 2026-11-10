# 文档维护

用户最新指令优先。文档帮助查代码和做决策，不为每次改动制造额外流程。

| 内容 | 位置 |
|---|---|
| 当前授权、停点、未提交工作 | docs/status/handoff.md |
| 唯一开发计划 | docs/plans/foundation-priorities.md |
| 游戏方向和已定规则 | design/vision.md、design/rules |
| 领域职责、现有接口和工具 | docs/engineering |
| 目标结构和必要详细规格 | docs/specs |
| 当前能力、版本和有效证据 | docs/status |
| 有日期和范围的原验证记录 | docs/qa |
| 候选机制和研究来源 | design/systems、proposals、research |

优先改现有页面，不为一个小包复制计划、规格、进度和QA。只在新增独立知识时加页；重复流程直接合并或删除。没有固定页长、QA数量或四套材料的交付要求。

现有class/API说明实现位置，允许重构替换；历史计划和QA不产生任务，不恢复已退役CI/测试。结果必须说明实际版本和范围，旧成功不能替新架构背书。保留历史证据原结果，失效工具链接改为对应Git版本即可。

Godot等专有术语及真实English标识符沿用，不另造同义名；定位现有代码可看[术语表](engineering/terminology.md)。移动/删除页面顺手修入口和链接，不要求每次变动重扫全库。分类目录只是索引，不是开发门禁。

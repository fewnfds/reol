# 项目文件架构

核对：2026-11-04。本文只负责文件放置；文档权威见[DOCUMENTATION](../DOCUMENTATION.md)，代码所有者见[ARCHITECTURE](architecture.md)。目录服务于当前规模，不预建空模块。

```text
reol/
├── project.godot、scenes/       Godot工程与场景装配
├── scripts/
│   ├── sim/                    纯模拟状态和规则；services/为跨聚落服务
│   ├── runtime/                输入、时钟、寻路、表现与场景适配
│   ├── persistence/            快照值规范、迁移与文件存读；不依赖runtime工具
│   ├── data/、core/            内容加载/定义类、通用小工具
│   ├── entities/、world/、ui/   人物视图、地形、界面
│   └── autoload/、social/      时钟、隔离继任原型
├── data/
│   ├── definitions/            人物/出身/身份/服务规则定义
│   └── scenarios/              开局、设施、初始资源和验证装配
├── assets/                     美术/声音/字体；来源与许可证随包
├── tests/
│   ├── sim/                    规则与多人因果测试
│   ├── runtime/                行程、地形、输入和存读整合
│   └── run_tests.gd、test_*.py  统一入口、Python工具测试
├── design/
│   ├── rules/                  已确认的游戏概念与世界法则
│   ├── systems/、proposals/    详细领域设计和候选提案
│   └── research/               一手来源、比较与取舍
├── docs/
│   ├── status/                 当前停点、功能和验证状态
│   ├── engineering/            代码所有者、工具和开发流程
│   ├── specs/、decisions/      候选合同、决策及其适用性
│   ├── plans/                  实施优先级与长期目标
│   ├── qa/                     验收记录与里程碑截图
│   ├── archive/                旧版资料，不作为待办
│   └── README.md 等            文档入口与维护规则
├── tools/                      Godot封装、MCP、本机配置生成
├── addons/                     第三方插件，禁止手改
└── .agents/、.codex/            项目技能、本机Codex连接配置
```

## 放置规则

| 内容 | 放置与约束 |
|---|---|
| 已确认概念与世界法则 | design/rules；写适用范围、失败和可观察后果 |
| 详细领域设计或候选 | design/systems、design/proposals；区分既定概念和待验证方案 |
| 建议范围与验收 | docs/plans；描述依赖和可验收范围，不在每页维护实施状态。当前任务见status/handoff，证据见status/baseline和qa |
| 世界运行与创作工具 | [总计划](../specs/world-engine/program.md)定义运行层/编辑/内容依赖；工具不能另存第二套世界真值，现有JSON定义/开局保持唯一持久来源 |
| 当前玩家可用功能 | docs/status/features.md；列入口、后果、样本边界与实现/QA引用 |
| 当前构建与验证 | docs/status/baseline.md；登记测试、兼容版本和证据 |
| 当前游戏理念 | design/vision.md汇总；design/systems与design/rules负责详细规则，区分用户方向与开发建议 |
| 决策理由 | docs/decisions；日期、状态、后果，旧提案仍标提案 |
| 参数定义 | data/definitions；代码读取，不写到人物真值里 |
| 初始条件 | data/scenarios；运行中不能修改它当存档 |
| 可无头执行规则 | scripts/sim；不能引用HUD或场景 `Node` |
| 地图权威与显示 | sim/world_map_data.gd保存原生成查询，RegionalSimulation持有联合地图；world/world.gd借用并负责区块/动态阻挡适配，候选不能反查活视图 |
| 游戏 `Node` 与规则接缝 | scripts/runtime；规则改变时调用明确API |
| 共用素材 | assets/；独占某场景的小资源可与场景放近，不机械拆散 |
| 存档/缓存 | user:// 与 .godot/，不进运行定义或Git |

village.json 暂仍同时定义生活规则和初始库存，是既有schema的过渡边界；复用需求成立后再拆，当前目录整理不改变其语义。测试纯规则与运行时按执行依赖分组；Python测试保留根位置，避免无意义改发现机制。

`.gd` 移动必须带 `.gd.uid`，更新文本引用并重新导入；资源 UID 只标识文件，定义 ID 和人物实例 ID 仍由游戏维护。场景、插件、技能和许可证没有为了整齐而移动。addons/ 不编辑，新增依赖按项目规则核用途、许可、维护和兼容性。

## 文档与兼容输入

文档按职责路由：status/handoff管当前停点，status/features管可玩行为，status/baseline管版本/验证；design管概念/规则，specs管候选合同，plans管建议优先级，qa管证据，archive保留旧全文。根README/AGENTS不复制长进度。新目录和全路径见[CATALOG](../CATALOG.md)。

原目录迁移记录留在[历史原文](../archive/documentation_consolidation_20261104/docs/PROJECT-STRUCTURE.md)。

## 结构验证

运行 `python tools/check_structure.py` 检查现行文档入口、本地 Markdown 链接和 scripts/、tests/ 中的字面量 `res://` 路径，包括移走后仍可能存在的旧路径。检查只读，失败返回非零；不验证网页可达性、标题锚点、代码示例和 archive/ 历史引用，也不推断动态拼接路径。

`Node` 层级、Resource UID 和 Scene 引用的正确性仍需按[测试入口](../../tests/README.md)执行实际 Godot 导入及运行验证。结构检查不能替代 Godot 导入、行为测试或实际运行。

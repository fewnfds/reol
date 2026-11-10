# 文件与数据放置

本页描述当前目录职责，不冻结文件名、class或内部拆分。重构可以替换实现，状态唯一性、依赖方向、内容/实例与表现分离继续成立。

| 位置 | 内容 |
|---|---|
| scripts/sim | 模拟事实、过程与领域规则，独立于HUD/活SceneTree |
| scripts/runtime | 场景、输入、呈现、计算后端与规则接缝 |
| scripts/persistence | 文件、候选输入及存读值规范 |
| scripts/data、core | 内容装配、定义与必要通用工具 |
| scripts/entities、world、ui | 当前人物/地图视图与界面 |
| data/definitions、scenarios | 可复用规则和初始条件；运行状态不回写模板 |
| tests | 当前合同、失败后果与联合入口的验证；fixture不可改写 |
| design/rules | 已确认世界法则 |
| design/systems、proposals、research | 独立领域候选和有日期/证据边界的来源 |
| docs/plans、specs | 唯一主计划及独立的详细技术合同 |
| docs/status、qa | 当前状态与不可混用版本的验证证据 |
| tools、.agents/skills | 工具与项目技能，按需路由 |
| assets、scenes、addons | 场景/素材/第三方组件及许可；第三方不手改 |

状态与领域职责见[架构](architecture.md)，数据引用见[data](../../data/README.md)，文档权威见[DOCUMENTATION](../DOCUMENTATION.md)。存档、日志、缓存、导出和本机配置不作为内容输入或公共提交。

移动Godot脚本须同时处理UID、字面/动态引用与实际导入；文档整理不顺带移动运行资产。目录层次不替代模拟领域划分，不为“统一架构”复制身体、库存或时钟。

`python tools/check_structure.py`只读检查当前入口、文档链接/大小与字面资源路径；不能证明Godot导入、动态加载、行为、画面或性能。游戏改动按[测试策略](workflow/testing.md)实际验证。

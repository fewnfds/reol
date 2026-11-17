---
name: godot-verify
description: 为Reol改动选择相关短验证，排查Godot headless错误退出、挂起、导入或异步检查问题。
---

# Reol短验证与排错

按[开发循环](../../../docs/engineering/workflow/testing.md)选择相关证据，直接从本次改动对应入口开始：

- 文档、路径或资源引用：`python tools/check_structure.py`；需看静态入口/职责时加`--audit-code`。它不能证明动态路径或游戏行为；技能目录链接按需单独核对。
- 新增/移动场景或资源、UID/大小写/内部引用问题：按需运行`python .agents/skills/godot-gdscript/scripts/check_godot_project.py .`，补充结构检查未涵盖的UID冲突、ExtResource/SubResource及场景连线检查。工具不代替Godot实际导入；导出交付另核`godot-export`的包内完整性。
- 规则、定义或存读：从[检查地图](../../../tests/README.md)选相关短检查，[命令](../../../docs/engineering/tooling/usage.md)由`tools/godot.py`提供；不把kernel_smoke通过当作全玩法证明。
- 输入、画面或真实帧时：用实际项目/场景运行观察，性能按release同条件窗口；headless不能证明MultiMesh、shader和真实渲染帧时。
- 查询/调度访问变化：按[规模反例](../../../docs/engineering/simulation-costs.md#怎样验证而不追逐人数极限)核与本次有关的访问量、完整结果及产出/等待，不只看预算内耗时。
- 经济/社会规则是否真的改变行为：按需用[模拟实验方法](../../../docs/engineering/simulation-methods.md#用不同证据回答不同问题)区分机制短反例、单因对照、正常跨周期与实际试玩；现有宗门日志可用`tools/settlement_report.py`离线取相邻差值。解析成功不等于游戏通过，缺失的队列年龄/个人轨迹不能由汇总数补造。

编写headless检查或遇到导入、退出/挂起、异步故障时读[排错要点](references/troubleshooting.md)。结果回原证据位置，不另建验证制度或重装长矩阵。

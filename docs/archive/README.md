# 历史资料

类型：归档。这里的“当前、必须、active、下一包”都属于原日期；既不授权工作，也不约束现行开发。当前任务从[HANDOFF](../status/handoff.md)进入，当前正文归属见[记忆地图](../README.md)。

| 追溯什么 | 范围 |
|---|---|
| 历史验证、调查、截图 | [qa](qa/README.md)，保留当时的代码、负载和原结果 |
| CPU根因和worker样本 | [CPU调查](qa/20261110_runtime_cpu_root_cause.md)、[首条CPU批](qa/20261111_actor_batch_execution.md)；当前采用结论只查BASELINE |
| 旧CI/回归为什么退役 | [流程退役](qa/20261111_workflow_retirement.md) |
| 后置正式美术的网页提示词 | [character_generation](art/character_generation/README.md)；不是当前任务 |
| 工具选型/旧版本更新 | [tooling](tooling/evaluation.md)、[2026-11-09版本记录](tooling/20261109-updates.md) |

`.ignore`使本目录退出默认rg搜索；需要历史时用`rg --no-ignore "关键词" docs/archive`，或直接打开已知路径。Git仍跟踪这些文件，链接可读取；它们不会自动注入agent上下文。

更早已删除的计划、ADR和文档快照在固定[8c3deaa版本](https://github.com/fewnfds/reol/tree/8c3deaa972f932e999167b61ea6b166b928cfe5f/docs/archive)。本次合并/删除的重复入口可从[整理前主线](https://github.com/fewnfds/reol/tree/4bf039fe8fadf95e639ae64a077e4fc3c7bdeeea)追溯，例如`git show 4bf039fe8fadf95e639ae64a077e4fc3c7bdeeea:docs/status/technical-status.md`。不另复制整套旧文档，旧fixture已按开发期政策删除，需要追溯时查Git。

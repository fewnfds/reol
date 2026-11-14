# Reol

GDScript / 2D正交俯视的修仙模拟世界。当前在自主模拟、多核批处理的新内核上恢复了实物、建筑生活、环境植物、战斗、交往修行和有限地区的代表性闭环。

双击根目录唯一的[启动.cmd](启动.cmd)，选择战斗试玩、普通世界、当前成品包或Godot编辑器。源码试玩修改后重启即可，无需导出；当前成品包是已验证的导出快照。运行方式见[命令说明](docs/engineering/tooling/usage.md)。

P2单剑切片已接入三连节奏、闪步避伤、轻重敌与混战重练；Esc→设置可改键、调整战斗反馈。当前成品在`build/windows/act-p2/`，统一由启动菜单进入；旧构建只归档程序文件，不再各放启动脚本。

按主题查[记忆地图](docs/README.md)；未完任务见[HANDOFF](docs/status/handoff.md)，agent入口为[AGENTS](AGENTS.md)。

- [可玩能力、键位和明确未迁回的玩法](docs/status/features.md)
- [实际性能与构建](docs/status/baseline.md)
- [运行和导出命令](docs/engineering/tooling/usage.md)
- [当前运行架构](docs/engineering/architecture.md)与[唯一主计划](docs/plans/foundation-priorities.md)
- [产品愿景](design/vision.md)、[已定规则](design/rules/README.md)、[文档职责](docs/DOCUMENTATION.md)

旧世界实现已退役，可由Git的a493bf0追溯；当前没有旧后端回退。代码许可证尚未选定，第三方来源见[NOTICES](THIRD_PARTY_NOTICES.md)。

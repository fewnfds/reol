# Reol

GDScript / Godot 4.7的2D正交俯视修仙模拟世界。当前支持自主世界模拟、多核批处理、实物与建筑生活、环境植物、ACT＋弹幕战斗和有限交往修行。

双击根目录唯一的[启动.cmd](启动.cmd)，选择战斗试玩、普通世界、当前成品包或Godot编辑器。源码试玩修改后重启即可，无需导出；当前成品包是已验证的导出快照。运行方式见[命令说明](docs/engineering/tooling/usage.md)。

P4通用行动基座已接入近战血刃、远程星焰行者与多种机制范例；技能由原生Resource制作，支持状态/资源/防御、有界反应、召唤与自主器物。当前成品在`build/windows/act-p4/`，统一由启动菜单进入；Esc→设置可改键、调整战斗反馈。框架完成到P4，后续敌人编排与正式内容见[主计划](docs/plans/foundation-priorities.md)。

按主题查[记忆地图](docs/README.md)；未完任务见[HANDOFF](docs/status/handoff.md)，agent入口为[AGENTS](AGENTS.md)。

- [可玩能力、键位和明确未迁回的玩法](docs/status/features.md)
- [实际性能与构建](docs/status/baseline.md)
- [运行和导出命令](docs/engineering/tooling/usage.md)
- [当前运行架构](docs/engineering/architecture.md)与[唯一主计划](docs/plans/foundation-priorities.md)
- [产品愿景](design/vision.md)、[已定规则](design/rules/README.md)、[文档职责](docs/DOCUMENTATION.md)

构建产物不入库。新检出安装Godot 4.7.2和Python后可直接运行源码入口；独立包按[导出命令](docs/engineering/tooling/usage.md)生成。退役实现与旧报告由[Git历史](docs/archive/README.md)追溯。代码许可证尚未选定，第三方来源见[NOTICES](THIRD_PARTY_NOTICES.md)。

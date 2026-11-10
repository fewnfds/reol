# Reol

GDScript / 2D正交俯视的修仙持续世界。玩家是众生之一，可以生活、修行、创造、冒险或组织他人。Reol取意于Dota Allstars的`/reroll`。

项目进入模拟执行架构重构。旧Demo提供可复用内容和行为样本，现有代码结构不限制新方案；多核、GPU、计算粒度、数据布局及呈现共同设计，以普通游戏的整体规模验收。

## 开发入口

1. [HANDOFF](docs/status/handoff.md)：授权、停点、工作区及受保护内容。
2. [唯一重构计划](docs/plans/foundation-priorities.md)：16类核心问题、12类验收情况、交付依赖与规模目标。
3. [执行架构规格](docs/specs/world-engine/execution.md)：目标结构；[领域职责](docs/engineering/architecture/05-framework-domains.md)明确问题归属。
4. [愿景与规则](design/vision.md)、[Demo功能](docs/status/features.md)、[证据基线](docs/status/baseline.md)：分别说明游戏方向、现有行为和已验证范围。

旧阶段编号、已完成样本和旧class不构成新任务。文档权威与完整导航见[文档入口](docs/README.md)，稳定工程规则见[AGENTS](AGENTS.md)。

## 运行旧Demo

按[基线](docs/status/baseline.md)安装采用的Godot稳定版并配置`GODOT_BIN`：

```text
python tools/godot.py doctor
python tools/godot.py editor
python tools/godot.py run
```

键位见[操作说明](docs/status/features/controls.md)，验证和工具见[工程入口](docs/engineering/README.md)。当前Demo尚未达到规模目标，不能用已有完整CI替新架构验收。

项目代码许可证尚未选定。第三方来源与限制见[THIRD_PARTY_NOTICES](THIRD_PARTY_NOTICES.md)。

# Reol

GDScript / 2D正交俯视的修仙开放世界沙盒。玩家是持续世界中的一员，可选择生活、修行、创造、冒险或组织他人。Reol取意于Dota Allstars的`/reroll`。

项目正在收束世界基础架构，已有功能、样本限制和验证范围分别见[功能](docs/status/features.md)与[证据基线](docs/status/baseline.md)。Godot 跟进最新稳定版，采用版本单独登记。

## 开发入口

- [AGENTS.md](AGENTS.md)：短工程规则，按任务取技能和文档。
- [HANDOFF](docs/status/handoff.md)：当前授权、暂停状态、未提交工作与恢复顺序。
- [文档路由](docs/README.md)：按问题定位权威文件；无需加载全部文档。
- [游戏概念](design/vision.md)、[实际功能](docs/status/features.md)、[代码架构](docs/engineering/architecture.md)：分别说明目标、可玩行为与真实状态所有者。

## 运行

安装项目当前采用的Godot稳定版并配置`GODOT_BIN`：

```text
python tools/godot.py doctor
python tools/godot.py editor
python tools/godot.py run
```

验证与工具配置按[TOOLCHAIN](docs/engineering/tooling/usage.md)；当前操作按[FEATURES](docs/status/features.md)。程序CI不替代实机画面、手感和性能证据。

项目代码许可证尚未选定。第三方组件、资源与技能来源见[THIRD_PARTY_NOTICES](THIRD_PARTY_NOTICES.md)；候选资源不等于已安装或可直接商用。

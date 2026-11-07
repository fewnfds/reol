---
name: reol-project
description: Reol 项目入口：核对当前状态与约束，并按任务选择领域和验证技能。
---

# Reol 项目入口

Reol 是 GDScript / 2D 正交俯视的修仙开放世界沙盒、宗门模拟与 RPG。单角色人生、持续世界、多种生命和有限认识是长期方向；设计不等于已实现。用户最近指令和实际授权优先于历史记录。

Godot 跟进最新稳定版；当前已安装和已验证版本以 `docs/status/baseline.md` 为准。每次升级记录实际版本并核对插件、CI 与导出模板。第三方技能正文可能针对较旧引擎，API 不确定时查询目标版本官方文档。

第三方技能中的固定职业、强制属性面板和样例组件只是通用示例，不覆盖 Reol 的无固定职业、有限认识与对象实际归属；不要将样例复制成项目事实。当前基础目标优先平面世界引擎，高低差研究延后；实际停点与已实现范围见下列入口。

## 先找权威入口

- 当前授权与构建：`docs/status/handoff.md`、`docs/status/baseline.md`；玩法是否接入看 `docs/status/features.md`。不要从旧计划、数字或样本推断完成度。
- 世界方向：`design/vision.md`与`design/rules/README.md`是已确认层；`design/systems/`、`design/proposals/`是详细候选，不能用其中的旧实现快照判断进度。
- 基础建设依赖与框架出口只查`docs/plans/foundation-priorities.md`；主计划按顶层框架组织，内部算法/优化明确归入模块和原owner。授权范围内持续推进到约定出口，内部小步不自动成为停止或再次确认边界；执行项只由HANDOFF登记，不自动恢复旧Goal或样本队列。
- 领域职责：`docs/engineering/architecture/05-framework-domains.md`；实际状态所有者：`docs/engineering/architecture.md`；文件职责：`docs/engineering/project-structure.md`。按任务读相关设计与 `docs/decisions/README.md`，不要把所有历史每次全读。

## 按任务选技能

GDScript 用 `godot-gdscript`；共同时间、跨域或存档用 `godot-sim-architecture`；工作/房间用 `colony-sim-systems`；地图/区块用 `open-world-2d`；UI、AI、动画、美术等按具体问题取对应领域技能。较大的新需求用 `spec-driven-game-dev`，验证按需用 `godot-verify`。不要求每次读完所有入口。

遵守 `AGENTS.md` 和本次任务范围：保留原主体、物品和共同时间的所有权；视图不能代替规则；不重做已存在系统。按变更范围验证，有可见效果须实际观察，不用猜测代替证据。

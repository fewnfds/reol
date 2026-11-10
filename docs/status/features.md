# 重构前Demo：功能与操作

核对：2026-11-10。下列入口描述现有有限Demo，供试玩与迁入参考，不代表新执行架构已实现或必须保留旧界面/代码。主线与工作区、版本与证据分别见[HANDOFF](handoff.md)和[BASELINE](baseline.md)。

| 内容 | 入口 |
|---|---|
| 开局、身体选择、键位与面板 | [操作](features/controls.md) |
| 环境、场与隔离计算服务 | [环境边界](features/environment-and-prototypes.md) |
| 双聚落、行旅、采集、生产与生活 | [世界与生活](features/world-and-livelihood.md) |
| 请求、社交、服务和有限机构事务 | [交互](features/interaction-and-organizations.md) |
| 认识、温石/修行、记录与衣着 | [器物与认识](features/knowledge-items-cultivation.md) |
| 有限交锋、雀身、残识与大体型 | [战斗/生命](features/combat-and-lifeforms.md) |
| 多格建筑、家具、使用与存读 | [建筑/存读](features/construction-and-save.md) |
| 原株、产物、花盆、残株与最小灵智 | [植物](features/plants.md) |
| 可串联样本及明确缺口 | [体验边界](features/playthroughs-and-gaps.md) |

现有Demo有共同时间、过载缓行、连续人物/镜头显示和临时人口压测。普通Main较大身体到期集合已接真实CPU worker，其余大部分规则和状态发布仍同步；GPU数学服务未接普通环境，不能把渲染线程或局部批计算当成整体性能达标。300人1×/60FPS、完整战斗、长期规模和正式独立发布尚未验收。

“有限样本”只代表具体入口；“隔离后端”不等于普通运行接入；“待验”需要准确代码及范围的证据。新架构以[主计划](../plans/foundation-priorities.md)的普通纵向链路、规模、因果与停开出口重新验收，旧阶段完成声明不继承。

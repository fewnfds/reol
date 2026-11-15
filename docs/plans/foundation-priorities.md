# 当前实施计划

当前实现见[FEATURES](../status/features.md)，构建与验证见[BASELINE](../status/baseline.md)，接续见[HANDOFF](../status/handoff.md)。本页保存阶段边界，不重复施工日志。

## 已完成基座

**ACT＋弹幕框架完成P0～P5，基础框架优化已收口。** 近战强调直接操作、连招与取消，远程强调移动瞄准、交付变化与空间控制。全部发生在原World，普通生活和存读共用同一后端。

| 阶段 | 已交付能力 | 维护位置 |
|---|---|---|
| P0～P1 | 60Hz共同时间、WASD/鼠标、改键、输入失效、贴墙/方向提示 | [运行与精度](../engineering/simulation-pacing.md)、[当前操作](../status/features.md) |
| P2 | 单剑三连、推进/取消/缓冲、轻重受击、闪步及基础音画 | [战斗规格](../../design/systems/combat_framework/act_and_barrage.md) |
| P3 | 原生Resource、弹体/区域/状态/器物与基础范例 | [制作流程](../../design/systems/combat_framework/act_and_barrage.md#102-制作者新增技能的实际流程) |
| P4 | 公共准入/领域作用、资源/防御/反应/召唤/光环/器物，近远组合 | [公共行动](../../design/systems/action_effect_framework.md)、[战斗合同](../../design/systems/combat_framework/act_and_barrage.md#13-p4通用战斗基座) |
| 框架优化 | 索引扫描、变化时属性重建、轨迹消重、可靠通知与慢统计 | [架构](../engineering/architecture.md)、[选型](../../design/research/large_simulation_optimization.md#godot原生能力与本轮实施取舍) |
| P5 | 共同决策/任务/交接/分层唤醒、策略Resource、个体差异、序列与三类敌人 | [单位决策](../../design/systems/unit_decision_framework.md) |

原RTS攻移、停止、警戒和点击追击已移除。完成表示基座与范例已交付，不代表正式素材、成熟构筑、平衡或主观手感已验收；旧讨论不恢复为待办。

## P5交付

| 重点 | 已实现结果 |
|---|---|
| 共同协调 | 生活/工作/战斗/逃离/跟随接Decisions；发现不提前停工，合法交接，手动松手不交回AI |
| 持续任务 | 原host/run反馈、有限序列、合法取消、buffer失效闭合；旧回执不覆盖，物资/费用不回滚 |
| 制作与个体差异 | 7套Policy、有序规则、独立参数/记忆、受信评分脚本、Inspector与F12诊断 |
| 三类打法 | 轻敌闪步三连、重敌承诺与收招、射手拉距及普攻/技能回退，遵守原成本/CD与可见性 |
| 跨域/调度/恢复 | 采集→威胁应对→脱离后重选；日常事件/到期，战斗默认50ms，运动原精度；存读任务/唤醒/自主输入 |

检查、真实GUI/制作、恢复、短性能窗与顾问复核归BASELINE。未安装外部AI运行时或复制商业游戏代码；Resource/Inspector、WorkerThreadPool、原AStarGrid和显示管线继续复用。

## 下一阶段候选

等待P5试玩反馈后选具体体验或制作缺口，不预订P6/P7清单。可继续内容/构筑、敌人配合或编排工具，是否实施另定。**新增预警系统后置**；图编辑器、公开脚本沙盒、运行时模型、全生活数据化和完整Boss未包含在P5。现有区域技能表现继续保留。

## 性能与扩展取舍

实测大世界拖慢选定战斗负载才降低相关次要过程的精度/频率；当前512²地图、60Hz和世界精度保持。流场、远区LOD、分块按实际瓶颈评估；测量沿[开发循环](../engineering/workflow/testing.md)，不追加万人/极密弹指标。

新增内容先判断配置、局部脚本、共享机制或新领域，沿实际owner扩展。长期产品依赖归[产品层次](roadmap.md)，候选设计不自动成为施工要求。

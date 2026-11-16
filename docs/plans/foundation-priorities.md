# 当前实施计划

当前实现见[FEATURES](../status/features.md)，构建与验证见[BASELINE](../status/baseline.md)，接续见[HANDOFF](../status/handoff.md)。本页保存阶段边界，不重复施工日志。

## 已完成基座

**ACT＋弹幕框架已交付P0～P5及一轮基础框架优化。** 近战强调直接操作、连招与取消，远程强调移动瞄准、交付变化与空间控制。全部发生在原World，普通生活和存读共用同一后端。已交付范围不代表全部扩展组合无缺陷；审查后的合同整改见下文。

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

## 审查后的框架整改方案

**已实施并按相关反例验证。** 两个并行审查对话发现的是同一批交接缺口，现归并为一份实现与问题账。问题编号及关闭证据归[问题清单](../status/issues.md)，当前构建与验证范围归BASELINE。原分析稿由Git追溯，不继续保留“光环规则待定”“仅分析未实施”的过时停点。

共同根因是唯一owner、共同时间和恢复约定没有贯穿所有入口与失败出口：同一事实被不同路径重复解释，一个值承担了来源、聚合或预测末态等不同含义。收紧现有owner之间的合同，不新建全世界事件总线、事务框架或调度器。

| 共同边界 | 已实现的修正 | 合同正文 |
|---|---|---|
| 对象生命周期和空间 | 开局、地区和施工共用完成设施装配/空间事实；受控移除清登记与依赖；放置判断共用纯规则；恢复检查实际身份、完整占地及双向关联，合法拆空登记可恢复 | [空间与施工](../../design/systems/construction_and_space/places.md)、[架构](../engineering/architecture.md) |
| 准入和执行反馈 | 已接受缓冲等待取消点、控制与CD共同开放且保留原期限；生活即时/异步失败关联原操作与目标，按个人有意义新观察、期限或真实成功解除，避免反复撞同一不可达候选 | [公共行动](../../design/systems/action_effect_framework.md)、[单位决策](../../design/systems/unit_decision_framework.md) |
| 预测和提交 | 器物收集只生成轨迹/转态候选，按真实时刻采用；较早死亡/损坏截断较晚候选；同刻死亡落点和先落地/接回再死亡分别按实际状态处理 | [公共行动](../../design/systems/action_effect_framework.md) |
| 来源、原因和通知 | 防御反应拥有自身来源与规则，上游攻击仅作平面cause证据，共享链预算不重置；World输出统一信封，表现先识别种类，再按施动者或受影响者选择可见主体 | [公共行动](../../design/systems/action_effect_framework.md)、[架构](../engineering/architecture.md) |
| 贡献和有效性 | 状态实例保存独立期限与来源/模板槽；普通驱散只移除recipient生命周期且可驱散的状态；source贡献随来源或范围关系撤回；显式标签压制只改变有效性，不删原贡献、不刷新寿命；控制总值由有效贡献与普通硬直聚合 | [状态合同](../../design/systems/action_effect_framework.md#4-状态属性与资源) |

Godot Resource/Inspector继续承载作者配置，原AStarGrid、WorkerThreadPool、MultiMesh和Frame管线保留。跨域真值继续归原owner：不因这些修正复制HP、物资、身体、导航或工作过程。不存在可供任意不受信脚本调用的沙盒。

恢复合同升为format14，动作运行合同与决策签名同步升级；新默认文件保留旧开发档，坏候选整份拒载。测试覆盖入口差异、同刻排序、实际文件与图形消费者，不把字段存在或顾问意见当作修复证据。压制目前覆盖Effects持续状态/光环贡献，不宣称所有瞬时治疗、护盾或资源交付均已有统一禁用政策。

## 下一阶段候选

上述审查整改完成后，根据P5试玩反馈选具体体验或制作缺口，不预订P6/P7清单。可继续内容/构筑、敌人配合或编排工具，是否实施另定。**新增预警系统后置**；图编辑器、公开脚本沙盒、运行时模型、全生活数据化和完整Boss未包含在P5。现有区域技能表现继续保留。

显示改造采用[纯二维显示](../engineering/architecture.md#纯二维显示)：二维斜视素材、分部遮挡和可关闭的轻微远近变形。三维探索已撤除；不把显示改造编号为下一战斗阶段。

## 性能与扩展取舍

实测大世界拖慢选定战斗负载才降低相关次要过程的精度/频率；当前512²地图、60Hz和世界精度保持。流场、远区LOD、分块按实际瓶颈评估；测量沿[开发循环](../engineering/workflow/testing.md)，不追加万人/极密弹指标。

新增内容先判断配置、局部脚本、共享机制或新领域，沿实际owner扩展。长期产品依赖归[产品层次](roadmap.md)，候选设计不自动成为施工要求。

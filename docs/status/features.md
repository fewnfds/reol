# 游戏功能与操作入口

核对：2026-11-07。当前是可操作的有限世界原型；普通世界已接入共同时间上的室外冷热与五行场，并通过当前准确SHA完整回归、独立进程存读和普通稀疏负载验证；满密度动态规模与16GB整机联合验收仍未完成。当前普通存档根格式为52，根1–51暂不自动迁入；具体行为与限制按下列领域页查阅，最终验证状态见[基线](baseline.md)和[接续](handoff.md)。

技术是否进入Git main、开发分支与隔离服务的区别统一查[技术落地总表](technical-status.md)。本页只维护操作与玩法范围，不另存一套技术施工清单。

| 领域 | 入口及现状 |
|---|---|
| [开局与操作](features/controls.md) | 人身、雀身和残识各有不同入口，键位与面板按身体能力分开。 |
| [环境与计算原型](features/environment-and-prototypes.md) | 普通世界已接室外冷热与五行响应；墙门屋面不隔场，GPU计算仍为独立服务，没有玩家开关。 |
| [世界连续性与生活](features/world-and-livelihood.md) | 双聚落共同时间、行旅、有限采集、生产和NPC生活；不是完整大世界或经济。 |
| [交互、社交与组织办事](features/interaction-and-organizations.md) | 有限请求、钱货、受托劳动、公源及野外样本；不是任意谈判或自由组织治理。 |
| [认识、器物、修行与衣着](features/knowledge-items-cultivation.md) | 原温石、有限引息、研究/记录、衣着和八向占位；不是通用创法、全装备或完整修炼。 |
| [战斗与非人生命](features/combat-and-lifeforms.md) | 有有限对练、身体后果、雀身、残识与大体型样本；不是完整战斗、生态或转生。 |
| [施工、居住与存读](features/construction-and-save.md) | 原工地、墙门、床、屋面及联合存读有有限样本；不是通用建筑与完整室温。 |
| [有限体验链与未实现项](features/playthroughs-and-gaps.md) | 可串联的样本、明确不能玩的内容及其范围。 |

状态用语：**已接入/有限样本**指实际入口和特定路径已有证据，不代表通用完整功能；**专用工具**需显式启动且不等于玩家能力；**隔离原型**未接普通游戏；**待验**缺对应范围或最终 SHA 的验收。每个领域页面保留原始范围与对应 QA，版本证据以基线为准。45–60 分钟完整切片、正式美术和独立发布均未验收。

开发侧有[对象与空间查询接口](../engineering/object-query-contract.md)与[生命周期和动作接口](../engineering/object-lifecycle-contract.md)：受管实物有唯一原物与位置，提供受控生成/移除、转移、拆合和最小耗时搬运。F8开发编辑可放置/移除受管实物，普通物品面板有耗时取放接缝；这不等于材料通用背包或任意NPC指挥。既有[查询QA](../qa/20261105_world_object_contract.md)与[生命周期QA](../qa/20261105_object_lifecycle.md)记录当时的受检范围。

普通世界的[环境合同](../engineering/world-environment-contract.md)以地面真实来源、固定器物和共同时间驱动室外温度/五行目标及残留响应。相同材料同堆数量不放大源强；人物随身物整体辐射、房间隔热与完整五行修行尚未接入。历史[来源QA](../qa/20261105_environment_source_bindings.md)、[缓存QA](../qa/20261105_environment_ground_cache.md)和[响应QA](../qa/20261105_environment_response.md)是各自版本的局部证据，不能代替当前整包验收。

普通来源变更与目标刷新目前同步运行于CPU。独立的CPU/GPU/auto计算服务和旧版本性能数据见[计算QA](../qa/20261105_environment_ground_compute.md)与[优化QA](../qa/20261106_environment_optimization.md)；普通游戏尚无GPU开关，也未完成端到端大规模性能验收。

`codex/sparse-world-execution`已接入[通用执行索引](../engineering/sparse-execution.md)：环境选择实际变化效果及到期响应，健康选择未愈伤口和活动诊疗；世界阶段/规则不变，没有新增玩法。完整回归、存读和短测范围见[本包QA](../qa/20261107_sparse_execution.md)，其他旧域仍按原路径，分支尚未自动合入main。

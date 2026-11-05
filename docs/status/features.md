# 游戏功能与操作入口

核对：2026-11-05。当前是可操作的有限世界原型，具体行为与限制按下列领域页查阅；证据、采用版本和完整回归状态见[基线](baseline.md)。共同时间已接原世界，普通 Main 仍使用旧 Q 冷热；源场与温度候选尚未接管普通游戏。四处新环境相关工作区改动未提交、未验，不能当作已交付功能。

| 领域 | 入口及现状 |
|---|---|
| [开局与操作](features/controls.md) | 人身、雀身和残识各有不同入口，键位与面板按身体能力分开。 |
| [环境与隔离候选](features/environment-and-prototypes.md) | 地表编辑、旧冷热、天气/日照等为有限样本；新源场和 GPU 服务为隔离原型，没有玩家开关。 |
| [世界连续性与生活](features/world-and-livelihood.md) | 双聚落共同时间、行旅、有限采集、生产和NPC生活；不是完整大世界或经济。 |
| [交互、社交与组织办事](features/interaction-and-organizations.md) | 有限请求、钱货、受托劳动、公源及野外样本；不是任意谈判或自由组织治理。 |
| [认识、器物、修行与衣着](features/knowledge-items-cultivation.md) | 原温石、有限引息、研究/记录、衣着和八向占位；不是通用创法、全装备或完整修炼。 |
| [战斗与非人生命](features/combat-and-lifeforms.md) | 有有限对练、身体后果、雀身、残识与大体型样本；不是完整战斗、生态或转生。 |
| [施工、居住与存读](features/construction-and-save.md) | 原工地、墙门、床、屋面及联合存读有有限样本；不是通用建筑与完整室温。 |
| [有限体验链与未实现项](features/playthroughs-and-gaps.md) | 可串联的样本、明确不能玩的内容及其范围。 |

状态用语：**已接入/有限样本**指实际入口和特定路径已有证据，不代表通用完整功能；**专用工具**需显式启动且不等于玩家能力；**隔离原型**未接普通游戏；**待验**缺对应范围或最终 SHA 的验收。每个领域页面保留原始范围与对应 QA，版本证据以基线为准。45–60 分钟完整切片、正式美术和独立发布均未验收。

开发侧有[对象与空间查询接口](../engineering/object-query-contract.md)，覆盖多类真实来源和显式集合空间快照；[生命周期与动作接口](../engineering/object-lifecycle-contract.md)提供受控生成/移除、同账本位置转移、材料拆合及最小耗时搬运。它们是权威开发接缝，尚未提供新玩家菜单、通用NPC指挥或新环境接管。受检范围见[查询QA](../qa/20261105_world_object_contract.md)和[生命周期QA](../qa/20261105_object_lifecycle.md)。

另有[地面环境来源查询](../engineering/environment-source-query-contract.md)：真实地面实物/材料堆按显式定义投影五行和单项冷热等级，支持有界局部max基础目标查询；原物搬运、拆合、移除后的下次查询直接读取原owner。它是开发查询接口，未形成实际温度/五行残留、普通Main新环境玩法或房温。范围和测量见[来源QA](../qa/20261105_environment_source_bindings.md)。

[真实来源分块缓存](../engineering/environment-ground-cache-contract.md)在同一原世界上提供预算装配、16×16基础目标块、热读、通知前局部失效及恢复重绑；不是某一具名物品专用脚本。独特物/材料堆和512²真实密度已做定向及离线测量，完整回归状态看[缓存QA](../qa/20261105_environment_ground_cache.md)。现在开发计算接口也接受真实缓存的CPU/GPU/auto，具备来源准备、过期拒绝及取消回收；接入验收看[计算QA](../qa/20261105_environment_ground_compute.md)。没有新玩家按钮或实际环境渐变，普通Main未接此服务；原四份WIP继续单列保护。

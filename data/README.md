# 游戏内容与开局数据

`definitions/conflicts.json`定义有限地面交锋的三种手段、时序/成本、学习背景、步长/距离与NPC判断参数。实际动作、命中与学成经历归SimConflicts，不回写定义；新局真实木剑由WorldContinuityRuntime显式加入原器物开局，旧档不补造。`artifacts.json`按能力类别提供实物动作，木剑不携温石热字段；`health.json`的挫伤恢复独立于经脉护理。灵源运行状态2记录历史检查点/施术成本floor，原灵源定义仍1。

交锋感知的`sight_radius`、`last_seen_ms`、`last_seen_arrival_px`与`threat_margin_px`也在`conflicts.json`，分别约束本人视距、最后目击时限、抵达旧位置的容差与来弹威胁余量。它们不保存NPC所见，不授予听声或神识；真实最后目击和`perception_since_ms`只进入交锋运行状态2。旧档在原保存现在启用，不由参数反推历史；定义版本仍为1。范围与本轮验收入口见[有限感知规格](../docs/plans/conflict_perception.md)。

`definitions/local_heat.json`定义正余热近场的容量/源脉冲、整数步长、导通/室外散失与稀疏预算。实际存量和来源回执归SimLocalHeat，原温石储量归SimArtifacts，房间和天气都不复制这些值；规则改变需显式版本迁移。

| 目录 | 放什么 | 当前文件 |
|---|---|---|
| definitions/ | 可复用定义和规则参数 | 人物/身份、服务/信息/放行、身体/短动作、器物/温养、雀妖/自然来源与寄魂等JSON |
| scenarios/ | 开局装配、初始状态与验证场景 | village.json、world_continuity.json、artifacts.json、avian_life.json |

当前内容：[人物](definitions/pawns.json)、[出身](definitions/origins.json)、[身份](definitions/ranks.json)、[跨聚落服务](definitions/settlement_services.json)；装配入口：[宗门生活](scenarios/village.json)、[双聚落](scenarios/world_continuity.json)。服务交付见[实现记录](../docs/SETTLEMENT-SERVICES-IMPLEMENTATION.md)。

village.json 当前保留原需求、动作和开局库存的一体配置，字段引用密切，暂不为了目录拆成碎片。它是已注明的过渡边界；以后多个开局需要复用时再抽公共动作定义。world_continuity.json 定义两地位置、库存差异、路线和消息时延。

规则：定义不持有运行状态；稳定小写 ID 与显示名分离；多个实例可复用一个 definition_id。修改参数后运行 check；配置变化会影响档兼容性，不假装旧档自动适配。存档放 user://，生成缓存与日志不放 data/。JSON 与 Resource 均按实际编辑需求选择，不混用两份权威值。

`heat_methods.json`规定有限试验可选的流量/时长、指导成本和材料类型；玩家运行中拟定的具体版本属于SimHeatMethods存档目录，不回写内容定义。实际耗费、储热、学习来源仍由原器物过程和事件承担。

`construction.json`规定有限宗门工地的使用/用料授予、日常施工者、观察距离、门墙成本/工时与拆回量。登记的具体工地、蓝图/结构、进行中材料/劳动属于运行存档，不回写JSON；没有按按钮直接扣资源完成的另一个建造余额。

`personal_production.json`定义私人配方的场所、原料/燃料、产物与工时；实际批次保存在SimPersonalProduction，数量仍属原库存。干药收购政策只在settlement_services.json，显式v24迁移加入未来政策，不补钱货或历史订单。

`budgeted_labor.json`定义机构现金差事、原动作引用、工资/期限与验收时长；不提供启动金或库存。实际签约依据/尝试归SimBudgetedLabor，专款仍在原SimInventory，验收仍在原服务。v25仅迁空合同和服务版本，不补历史。

`capability_conversation.json`定义有限话题/自述白名单、意愿参数与显示文字；实际答复只进入原社会事件，不写回定义。来源来自本人日常/经历/学习/任职，不增加一个隐藏通用技能表。

`autonomous_livelihood.json`定义新局启用的生活背景、一份随身口粮目的、公开寻找地点/原生拜访和退避间隔；它不提供工资或物资。计划的寻找/重试归SimAutonomousLivelihood，钱货/身体/自述仍归原系统；旧档只迁未来动作和空意愿。

`definitions/clothing.json`定义有限衣物的穿法/形状/颜色、雨具用途、取放穿脱时长和湿润/晾干默认值，以及仅新局一次的实物来源。与数量库存分开的是唯一物件身份，不是第二份资源。

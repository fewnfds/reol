# 术语与代码映射

本页固定跨文档使用的名称，并把中文概念指向真实实现。游戏规则由[design/rules](../../design/rules/README.md)负责，状态所有者见[architecture](architecture/02-owners.md)。表中的多个入口分别表示定义、实例或视图，不是可互换的别名；候选模型不因列在这里成为已实现功能。

## 命名方法

- 中文原生概念在正文中保持中文；English原生名称与API保留原拼写。代码需要English标识符时，复用本页及领域owner已采用的名称，并遵循snake_case/PascalCase。
- 同一层级的同一对象使用一个确定标识符；新代码不得为了重新翻译而另加同义字段、平行class或兼容getter。首次建立映射时写清概念、实际标识符及所属owner。
- 代码引用用真实class/字段/路径。局部`const Rules = preload(...)`等别名在其文件内成立，跨文档引用使用真实class名或文件路径。没有实现的候选职责用中文描述，不虚构看似现有class的English名称。
- 改名同步更新调用方、调度注册、反射访问、测试、工具及现行说明。持久化键由格式合同决定，通过明确codec映射连接代码；不要为了文档措辞改变存档格式。历史引用、原始fixture与第三方名称保留原文。

## 环境与修行资源

| 固定概念 | 实际代码入口 | 含义/边界 |
|---|---|---|
| 五行 | `elements`；键`metal`/`wood`/`water`/`fire`/`earth` | 金/木/水/火/土；中文正文统一“五行” |
| 五行亲和 | [NaturalEnvironment](../../scripts/sim/natural_environment.gd).`affinity_at()` | 地表的静态适宜性，区别于实际环境响应和可消耗库存 |
| 五行环境影响 | [SimEnvironmentPhaseState](../../scripts/sim/environment_phase_state.gd)；`SimWorldEnvironmentFields.elements_at()` | 不被修炼消耗的环境影响；类名中的`Phase`指五行，不指动作阶段 |
| 环境来源定义 | [EnvironmentSourceDefinitions](../../scripts/data/environment_source_definitions.gd)；`environment_sources.json` | 原物对外影响的`elements`/`thermal_grade`/`radius_cells`，不另持实物 |
| 冷热等级 | `thermal_grade` | 有符号等级；正热、负冷、零无影响，区别于五行火/水通道 |
| 温度 | [SimEnvironmentTemperatureState](../../scripts/sim/environment_temperature_state.gd)；`temperature_milli` | 实际温度与目标温度在接口中分别标注，不能混称“热量” |
| 室外环境域 | [SimWorldEnvironmentFields](../../scripts/sim/world_environment_fields.gd)；`RegionalSimulation.environment_fields` | 当前温度和五行响应的共同owner，区别于人体环境后果域`RegionalSimulation.environment` |
| 灵气 | 人物记录`qi`，上限来自`PawnDef.max_qi` | 人物可使用/消耗的储量；文档及数值UI统一“灵气”，不另称“灵力” |
| 物品灵气储量 | [规则](../../design/rules/environment.md)；通用实现待定 | 与五行环境影响分开；不把现有任意充能/储热字段宣称为它 |
| 灵源储量 | [SimSpiritSources](../../scripts/sim/spirit_sources.gd)；`sources[id].amount` | 现有有限来源的储量，`qi_gain`等记录实际转换；不是无穷五行场 |
| 器物充能 | [SimArtifacts](../../scripts/sim/artifacts.gd)；`objects[id].charge` | 现有特定器物用途的充能，不能泛指所有物品灵气 |
| 储热量 | `SimArtifacts.objects[id].stored_q` | 热设备存储的热量单位，区别于温度、冷热等级、灵气 |
| 体力 | 人物记录`stamina` | 与`qi`、饥饿、精力各有用途，不能用“能量”笼统替代 |
| 灵机 | 残识观察的叙事用词 | 表示角色感受；不是又一项已实现的环境通道或库存数值 |
| 风水 | [环境规则](../../design/rules/environment.md) | 中文世界概念；尚无可与现有class等同的通用风水实现 |

五行数组顺序由接口决定：来源定义的外部顺序是`wood/fire/earth/metal/water`；packed缓存及实际五行响应顺序是`metal/wood/water/fire/earth`。[SimEnvironmentFieldRules](../../scripts/sim/environment_field_rules.gd)的`source_to_packed_channels()`与`packed_to_source_elements()`负责转换，调用方不自行猜顺序。

## 人物、实物与空间

| 固定概念 | 实际代码入口 | 含义/边界 |
|---|---|---|
| 人物定义 | [PawnDef](../../scripts/data/pawn_def.gd) | 静态内容，不是身体实例状态 |
| 人类身体记录 | [VillageSimulation](../../scripts/sim/village_simulation.gd).`actors[id]` | 原人类身体及位置/灵气/体力等实例状态；`actor`不是所有实体的统一class |
| 人物视图 | [Pawn](../../scripts/entities/pawn.gd)、[PawnState](../../scripts/data/pawn_state.gd) | 场景呈现与从原身体投影的数值；不与`actors`建立第二套模拟权威 |
| 主体与载体 | [SimEmbodiment](../../scripts/sim/embodiment.gd) | 主体、居留与控制关联，分别成立 |
| 雀身/大型身体 | [SimAvianLife](../../scripts/sim/avian_life.gd)、[SimLargeBodies](../../scripts/sim/large_bodies.gd) | 各域的真实非人身体，不能按人类`actor`直接强制转换 |
| 实体定位查询 | [SimEntityQuery](../../scripts/sim/entity_query.gd) | `actor`/`avian`/`artifact`/`large_body`的只读解析，非全量状态注册表 |
| 世界对象查询 | [SimWorldObjectQuery](../../scripts/sim/world_object_query.gd) | 复用定位并扩展数量条目/资源/结构等参照；与`SimEntityQuery`接口不同 |
| 独特器物 | `SimArtifacts.objects[id]` | 独特实例；`artifact`在该接口不代表所有物品 |
| 数量物品/容器 | [SimInventory](../../scripts/sim/inventory_ledger.gd)、[SimStorageQuery](../../scripts/sim/storage_query.gd) | 数量账本及原容器查询，不与独特器物重复计数 |
| 地面放置 | [SimGroundPlacements](../../scripts/sim/ground_placements.gd) | 原物/数量条目的引用与覆盖格，不复制原物状态 |
| 实物生命周期 | [SimObjectLifecycle](../../scripts/sim/object_lifecycle.gd) | 受控生成/移动/堆拆及共同动作，位置与成本仍归原owner |
| 建筑结构 | [SimConstruction](../../scripts/sim/construction.gd)、[SimStructureQuery](../../scripts/sim/structure_query.gd) | 墙、门、屋顶、家具等实体及只读投影 |
| 区域/房间/工作场所 | [空间设计](../../design/systems/construction_and_space.md)；`SimWorkplaces` | 指定区域、推导围合空间、人/器具办事条件分别成立，不合称一个建筑单位 |

## 社会、能力与时间

| 固定概念 | 实际代码入口 | 含义/边界 |
|---|---|---|
| 宗门/组织 | [社会规则](../../design/rules/society-and-knowledge.md)；`SimInstitutionBook.institutions` | 中文概念及现有有限机构记录；组织完整模拟仍按实际范围判断 |
| 职位/任职者 | `SimInstitutionBook.institutions[id].offices` / `holder` | 职位与当前任职者分离 |
| 贡献 | [SimInstitutionBook](../../scripts/sim/institution_book.gd)；`entries`、`balance()`、业务条件`contribution` | 机构记录与认可的数额；“功德堂”是办事地点专名，不把余额另称“功德” |
| Claim | [社会系统提案](../../design/systems/social_system.md) | 原生English候选模型；现有`entries`、交互verb `claim`及局部归还主张不自动等于此模型 |
| 功法/技法/本领 | [能力设计](../../design/systems/combat_framework.md)；`SimHeatMethods`、`SimCapabilityPractice`、`SimMethodRecords` | 分别沿实际方法、练习和记录入口定位，不虚构单一`Skill`万能对象；读过记录不等于学会 |
| 共同时间 | autoload `GameClock`，类型[ReolGameClock](../../scripts/autoload/game_clock.gd) | 访问实例用`GameClock.elapsed_ms`；类型名不是可直接访问实例字段的singleton |
| 行动阶段 | 具体过程的`phase` | 执行过程状态，区别于五行类名中的`Phase` |
| 地块/区块 | `WorldMapData`；`cell`/`chunk` | 单格坐标与分块存储/流式单位分开；物品可跨多格 |

## 持久化边界

当前运行成员和调度domain使用`environment_fields`。区域存档schema 43仍使用JSON键`local_heat`；`RegionalSimulation.SNAPSHOT_KEYS`在capture和shape validation处做明确映射，restore读取该既有键。当前根存档仍为schema 52，没有运行时`local_heat`兼容getter或第二环境owner。

`ReolContentDB.local_heat`和`data/definitions/local_heat.json`保留为热设备参数定义入口；历史`SimLocalHeat`不因此成为当前环境owner。使用时写出限定路径/所属对象，不能只写`local_heat`猜它指运行域、存档还是定义。

本页不重命名第三方API、官方作品名、原fixture或历史证据。新增/更名概念同时维护本页及其领域owner文档，不另建一套翻译词表。

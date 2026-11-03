# 当前代码架构

Godot 4.7.2 / GDScript。文件布局见[PROJECT-STRUCTURE](PROJECT-STRUCTURE.md)。此页记录现有边界；未来系统先写[开发计划](ROADMAP.md)，不把目标写成现状。

## 依赖与状态

```text
main.gd 装配场景
  UI signals → runtime 命令/表现适配 → sim 规则与持久状态
                    ↓                       ↓
             world 地形/寻路             data 内容定义
                    ↓                       ↓
             entities 人物视图        persistence 快照读写
```

- scripts/sim/ 是可无头推进的数据规则，不依赖 UI、游戏节点路径或每帧渲染。
- scripts/runtime/ 连接时钟、合法地形路径、场景视图、玩家输入与状态；不拥有社会判定或机构余额。
- scripts/persistence/ 只处理快照文件的验证、替换与备份，不决定游戏规则。
- scripts/world/ 拥有地形、区块与可走性；scripts/entities/ 是人物和飞行物的画面/输入表现；scripts/ui/ 只呈现可知信息并发出意图。
- scripts/data/ 加载和校验定义，data/definitions/ 是只读内容，data/scenarios/ 是开局/验证装配。运行状态不回写定义。

## 已有模块

| 模块 | 唯一负责的数据/行为 |
|---|---|
| GameClock（当前游戏 autoload） | 共同整数毫秒、分钟投影、暂停/倍速/等候与时间信号 |
| VillageSimulation | 一地人物状态、日常选择、身体、局势与执行装配 |
| SimActionExecutor | 本地动作阶段、耗时、取消、实际取物和交付 |
| SimRouteTravel / SimLocalMotion | 原身体位置的路线段投影 / 手动速度与闪身阶段 |
| SimSparring / SparringRuntime | 对练持久规则与短动作 / 输入、面板及获准可见扇区 |
| SimInventory | 容器库存、预约、幂等操作 |
| SimLandResources | 各地有限自然来源的增长相位/产生与采出汇总，实物只存原库存；原执行器负责采集劳动/携回 |
| SimSocialMemory | 事件事实、每人所知、来源、有向关系、请求决定 |
| SimInstitutionBook | 职位任职与权限、机构账目、签署依据 |
| RegionalSimulation | 共同时间、区域边界与执行责任、在途货物、运输/消息 |
| SimEmbodiment | 主体ID/旧actor别名、载体源引用、居留、排他控制通道；不复制位置/库存/个人记忆 |
| SimSoulVessels / soul_vessel_schema | 唯一戒指位置/封纹、独立寄魂者旧知/注意/休眠、逐人约定和实际指导经历；只向器物提供已完成学习的只读证据 |
| SoulVesselRuntime / SoulVesselPanel | O/可见旧戒选择、亲历对话与玩家意图，不读取私人精力/全部旧知 |
| SimArtifacts / artifact_schema / SimArtifactUnderstanding | 唯一容器、裂损/储能、个人阅历/实验与具名说明、投入/进行中检查和真实作用；理解投影只读 |
| SimAvianLife / PlayerAvatarRuntime | 实际雀身、栖地/食源、原毫秒生活与轻物操作 / 一次开局身份绑定、身体输入及感知视角 |
| SimLocalMotion | 现有玩家身体连续位置/速度/朝向、闪身三阶段与地形扫掠；无独立体力、背包、计时器或无敌状态 |
| SettlementServices 与 services/ helpers | 访客事务、交付证据、机构办理、互助承诺与托管支付、服务快照校验 |
| VillageRuntime / WorldContinuityRuntime | 场景适配、可见视图、玩家行程与联合快照 |
| WorldObjectsRuntime / ObjectInspectionPanel | 可见器物绘制、选择/靠近和操作意图；面板只收获准认识 |
| SettlementServicesRuntime | 跨聚落操作意图与可见信息适配，服务面板刷新 |
| WorldSessionSnapshot | 一致提交点的联合快照、独立候选构造与验证；不修改存活场景 |
| ReolUITheme / PawnVisuals / FacilityVisuals / PawnViewLayout | 共用样式、人物/设施绘制和拥挤显示布局；不持有游戏真值 |
| SimSchema / SimSnapshotSchema | 配置形状、引用、快照约束 |
| SimSaveStore | JSON 文件边界与备份替换 |

跨区服务已放 sim/services/，通过明确命令连接区域模拟，不继续增加通用巨型运行脚本。旧 SuccessionResolver 留在 social/，是隔离提案，不自动主宰社会系统。

运行适配以明确的玩家命令/查询连接服务面板，HUD由时钟事件合并更新；F3诊断另作低频采样。联合存档的候选校验在专属runtime协作者中，成功后才由WorldContinuityRuntime替换场景引用和时间。文件原子读写仍由persistence处理。人物绘制偏移仅改变轮廓与点击位置，不回写人物格、节点真实位置、路径或快照。

## 不变量

- 人物实例 ID、定义 ID、职位和任职者分开。跨区引用稳定 ID，不用 NodePath 或数组序号。
- 同一行动只有一个权威执行/提交负责人；物资只能有一个实际保管位置。当前动作由单一人物执行，后续共同过程可有多个参与者，不能各自重复产出结果。切换画面或精度不初始化人物、不重复结算。
- 近区细算，远区批算稳定区间；全局先处理最早必要变化。跨区写入前同步有关区域，修改后使预测失效。
- 世界事实不等于人物知识。广播、存档和开发面板不能自动赋予 NPC 全知。
- 外部输入、权限、资源和地形在实际提交时复查；业务失败返回结果，开发不变量才使用断言。
- 存档先在一致提交点取样；读取完整验证候选后替换。游戏规则持有自己的状态，文件存储不偷偷修补坏档。
- UI 与插值在帧循环；规则在固定世界时间。没有证据不承诺远区与物理轨迹逐位一致或大规模帧率。

当前限制与验证以[BASELINE](BASELINE.md)和对应实现记录为准。[旧技术草图](archive/architecture_before_structure_20261102.md)仅作历史参考。

## 世界模型的实际接缝与后续边界

当前根schema14/区域11/村落3/器物3/寄魂2/临时放行1。有限自然来源从第一版存增长相位和实际来源账，采集复用原身体、预约、路线和原库存；旧档迁空来源，不改历史。区域保留开局配置作为候选兼容基准，不能用上次加载的旧配置锁住后续新档。见[实际证据](qa/20261103_renewable_livelihood.md)。会话avatar引用原人身、雀身或戒中残识；身体真值不复制，读档先设所选感知再恢复探索。新开局只能选一次，旧档迁原人身。器物裂损属于物，背景阅历属于主体，实际检查事件保留操作者/在场听者；收到结论不复制操作技能，公开活动不含私人结论。请求检查使用原社会决策与实际执行权，强注使用真实裂损/储能/原体力，所有过程进入共同毫秒边界。见[玩家雀身](qa/20261103_player_life.md)与[知物/用器](qa/20261103_artifact_understanding.md)。

以下按接入阶段保留各旧版本决策；其中“NPC仍分钟”“鸟尚不可玩”“数据未迁移”只描述当时，不覆盖上文和BASELINE。

最新补充：`SimAvianLife`独立持有实际雀身/栖地/库存与本人所见，`avian_body`是经交叉校验的源引用，不复制成Village人类actor。身体宽度与轻物容量约束真实进入/拾取；稀疏飞行/需求/生长边界加入原世界时刻。跨域交付先同步有关聚落，再一次提交原库存与鸟嘴库存，唯一成功签名留在鸟域。`AvianLifeRuntime`只处理可见呈现/B/意图，不读取隐藏需要生成面板。根schema8/区域6迁旧档为空域，候选同时验证人类与雀身来源、进行中几何和实物操作。当前是非人NPC，尚无玩家鸟妖开局；[验收](qa/20261103_avian_life.md)。下面按接入阶段说明各领域。

2026-11-03实施补充：当前世界快照schema5由`SessionSaveSchema`显式链式迁移真实v1–v4档，验证生成与探索；Fog只保存探索记忆，实际可见性重算。区域定义版本1与快照版本3分离，先后加入`SimEmbodiment`和器物领域。注册表以`subject:*`与`body:*`分别引用现有人类，身体源为既有`village_actor`；入场/读档校验每个源唯一且实际存在。居留不授予控制，移动/行动/通信每个通道最多一名控制者，原生工作/服务/器物/当前玩家短动作互斥占用同一身体，通过弱引用连接区域权威。

器物实例只引用既有容器，不再在数量库存放一份石头；其实际位置从身体/设施解算。实验事件归独立主体，并保存动作/耗时/投入来源；查询只投影本人的经历和当前可见外形。温火石以原`SimInventory.transform`一次提交米水到饭的变化，不把灵火伪造成柴；原成果凭据与机构登记继续分开。器物仍按分钟边界结算，旧档迁移不倒造器物或学习。当前方法是有限规则，未扩展成任意作用平台。

`SimStockInformation`通过既有个人stock_memory与stock_statement事件投影库存认识，NPC决策查该投影、执行仍查实际物资；来源和事件由原社会账保存，不新增第二份仓库或“全世界相信”的字段。此样本不等于通用命题/器物认知已实现。

共同`ReolGameClock.elapsed_ms`为整数世界毫秒；`time_advanced`提交玩家短动作、原生/访客/器物和远区关键边界，旧`tick`保留为整分钟通知。正常一现实秒对应一世界秒，倍速统一缩放；显式等候保留目标/暂停。帧欠算与相位进入快照。原actor身体唯一持有连续位置，`SimLocalMotion`读写同一字典并持有速度/闪身阶段，节点只采输入/投影；actor.cell是位置的格子索引。`SimRouteTravel`为NPC与自动路线计算相同步速的几何段，劳动从到达毫秒计满时长。固定点需求/体力余数使细步与稀疏推进一致。身体变化立即更新HUD，入场不等分钟；呈现不推进规则。见[执行包](plans/shared_time_actions.md)与[精度证据](qa/20261103_continuous_life.md)。

`SimSparring`持有一个有界自愿对练的参与者、短动作、命中去重和结算边界，不持有第二份体力/位置或背包。`RegionalSimulation`只在实际对练存在时接其50ms/阶段边界；收集同刻接触再汇总作用。原生/访客/器物查询同一执行所有权，结束恢复NPC原自主性。`SparringRuntime`只路由K/J、显示获准阶段与扇区；具体地形/高差资格由已绑定世界提供。根schema7/区域5显式迁旧档为空练习；坏状态在独立候选里拒绝。当前为同区山门样本，非伤亡/通用战斗完成，见[范围](plans/sparring_sample.md)。

[世界总纲](../design/systems/self_consistent_world.md)与[W0–W7](plans/world_first_sandbox.md)要求逐步分开主体、身体/载体、控制、社会识别与知识。主体/控制首步已接现有居民，个人记忆等仍以旧actor别名持有；非人形仅纯代用品验证，不代表多种可玩生命、器物寄魂、换身和社会识别已实现。新领域按真实动作接入，不全量重写模拟或建立通用ECS。

[整体评审](plans/world_architecture_review.md)进一步标记时间/打断、认识命题、作用冲突、共同过程、有限方法规划与动态候选装配的未实现契约。现有事件转述不是完整信念模型，单一active动作不等于未来只能单参与者/无持续效果；这些要在首次对应样本中验证，不能直接宣称既有架构已具备。

2026-11-03[W0-a状态目录](plans/world_state_contracts.md)完成首轮静态梳理：当前手动玩家位置经runtime写回sim，身体面板可能按安静间隔投影，本地事件ID有各自作用域，动态恢复仍受固定装配约束。新代码须先明确权威写入、单位/命名空间与主体可知查询，不能仅依据目标分层断言这些接缝已统一。数据未迁移、游戏行为未改。

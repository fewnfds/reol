# 当前短检查

`settlement_opening_smoke.gd`核正常原生Resource的100人一次性装配、无木源合法世界、零时刻/真实活动中恢复，以及缺床/错误角色/自师承/重复种子、堵灶/封屋、同组不同服务、占位探索污染和资源隔离反例。`settlement_ui_smoke.gd`从正常main直接开100人，观察原生人物页与实际文件存读；均不是持续供养证明。`settlement_cycle_smoke.gd`按需运行正常开局的真实源耗长窗，不清夹具、不补料、不缩内容周期，核来源/转化/消耗、各院实际流程和个人最坏状态；须显式给足长检查时间，不能加入默认15秒短检查，也不能当图形帧时。

`qi_sources_smoke.gd`核有限灵植非整秒积累、成熟跨界、满额余数、阶段/容量坏档、共同修行准入和真实实践。`qi_agency_smoke.gd`核自主补灵/真实伤害自疗后再补、空源恢复/换源、微小缺口、满灵未精通的远方复查、来源移除及手动中断恢复；`qi_refinement_smoke.gd`核小需求保留公料、普通技艺探索、外部临时指派后回归自主及资源字段owner；`qi_ui_smoke.gd`在正常原生Game读取修行中文件、人物修行页与玩家满额按钮禁用。不是百人装配或性能验收。

`cultivation_duties_smoke.gd`核同World自主田务、稳定宿主跨株授权、两种作物、真实公井用途、满仓继续照料、撤职退料、空源恢复和受阻畦改选。`cultivation_duties_ui_smoke.gd`以正常Game人物页查看NPC任职/活动，实际文件存读后由NPC继续播种；截图在`logs/cultivation-ui/`。

`sect_provisioning_smoke.gd`按需核三实际游戏日的来源→田务→公库→烹饪→送餐→进食/休养，并中途候选恢复及全部粮/水/餐核账；约43秒是小规模逻辑夹具时间，不属于默认短检查，不代表正常百人装配或图形性能。设施完成统计按操作ID（如`draw_water`），handler不是结果ID；有界近期结果不能当作长期计数。

`python tools/godot.py test`只运行kernel核心交接、守恒、导航、存读和线程反例，保留15秒退出上限。512人串/并行配置至少推进1世界秒，且两者都完成真实交付后结束该段。其他专题独立选择，避免默认检查累积成整库长回归；原断言继续保留。

| 命令 | 覆盖 |
|---|---|
| `python tools/godot.py test` | kernel核心，包括导航与实际文件停开 |
| `python tools/godot.py test --suite features` | 小型综合世界、社会/修行、交战与过程恢复 |
| `python tools/godot.py test --suite sight` | 观察/迷雾/最后所见与隐藏信息 |
| `python tools/godot.py test --suite equipment` | 原子换装、真实派生属性、装备存读与槽复用 |

每次选择一个相关专题，不自动串起全部检查。失败退出码、引擎错误和超时都视为失败；验证强度查[开发循环](../docs/engineering/workflow/testing.md)。

`being_capabilities_smoke.gd`按需单独运行，核非人实际取放、代谢/环境隔离、个体接触差异、资格变更中断、与劳动无关的手动移动、源状态/规则签名及进行中资格拒载、常驻召唤形态与槽复用、静物实物/qi及身体费用边界。原临时召唤生命周期沿`action_spatial_smoke.gd`验证。

`operations_smoke.gd`按需单独核对共同查询/UI/owner要求、真实烹饪、未知/非法目标拒绝不污染run、过时和缺失观察、规则签名/重名/递归冻结、同机制Resource变体直接执行；另验木愈实际多费用/P4归因、被控和动作承诺拒绝、普通run保留及恢复。它不证明完整配方、多人课程或人生目标已实现。

`activities_smoke.gd`按需运行，核原World中的实际部分拿取/同刻取空、施工中断换人和中途恢复、未到场/忙方/伙伴死亡/静止教师、线索成功反馈、播种完工与采木失败、共享结果按人/全局淘汰及活run与历史互斥、放置和派工回执。结果纯存储的边界另用有界历史反例；不把施工接续当作加工在制已完成。

`growth_smoke.gd`按需运行，核真实授课/读书/实践分责和独立本领、亡师/售书/暂失能力后保留进展、玩家/NPC同材料工艺差异、派生解锁与显式授予并存、素质实际消费者、真热伤/满HP持续条件/安全休养及半途恢复、定义和坏成长源状态拒绝；不是全境界、共时课堂或百人闭环验收。

`teaching_smoke.gd`核学生/教师对称入口、到场才占伙伴、相向合流、玩家主动参加、有界汇合与中断/恢复、教师私人目的和组织责任采用同一结果、已从别处学懂不虚报工。`teaching_agency_smoke.gd`核自主教师与学生、真实实践消耗并再传第三人、中途恢复；`-- --busy`核真实忙碌与急需拒绝、短窗内实际加入，`-- --partial`核低悟性多课与跨宿主履行。`teaching_ui_smoke.gd`在原Game用正常按钮实际加入邀请、共同授业文件存读与人物页角色/理解反馈，截图归`logs/teaching-ui/`。均不是百人供养或性能验收。

`teaching_meeting_smoke.gd`默认核远距相向会合，`-- --manual / --dead`核双手动及目击学生死亡；`teaching_obligations_smoke.gd`默认核未学成教师依本人权限自修后授课，`-- --borrowed / --witness`核借书练完再还与学生host实际履约见证。`teaching_consent_smoke.gd`默认核同意/资格顺序与无视觉拒教回执，`-- --duty / --search / --duplicate`核岗位空闲、搜索中实际机会及重复事项单次记功。`teaching_refinement_smoke.gd`核运动片内接触、双手动已懂/急需、旧锚点失效的书籍保留、已知死亡正式责任和学生host结案的当面消息。

`custody_smoke.gd`核公私同包/拆合/保权、满包交换/费用、共同授权、公料烹饪/中断恢复/退料、撤权后返还、旧公物搬回不记新供给、明确捐赠、施工材料回收和死亡遗物历史引用，以及规范批次/未结责任坏档。`custody_ui_smoke.gd`从独立真实档进入原Game，通过原生用途表单取公粮并观察背包自有/受托量；截图归`logs/custody-ui/`，不改用户档和偏好。两者不代表在制生产或百人自主供养已完成。

`production_smoke.gd`按需核标准劳动与熟练工时、实际入锅/换人/死亡/中断/恢复、静置释放占用与人工收取、费用和出料阻塞、旧过程不能重复生产、保权拆除、有限水源回补及规范过程拒载；同机制配方变体仍走原World。`custody_smoke.gd`另核公料在制换人后原领料责任闭合。`production_ui_smoke.gd`用原Game正常按钮完成请教、煎药、静置实际文件存读、收药及取尽井水；详情支持滚动，截图归`logs/production-ui/`，档与偏好独立清理。不代表完整自主计划或百人源耗已成立。

`production_authority_smoke.gd`补公料静置/收药中断与满仓、原领料人死亡/撤权/无权者拒绝、原炉体及受托在制回收归库、饱和批次拒拆、在途预约前驱与等待请求不重开、中立炉台他人私料保护。它与生命周期专题分开以保持短退出窗口，不加入默认套件。

`knowledge_smoke.gd`核个人观察/传闻溯源、脱离副本、静态反证防旧消息复活、移动位置失效/空旧格与远死隔离、来源移除和2跳限制；真实交谈驱动NPC走到远灶台取食，真实教学拒绝及同院新教学证据改变可尝试性；另核容量和坏认识数据拒载。

`knowledge_boundaries_smoke.gd`补旧位置反证不误杀异地目击、技术取消不洗拒教、真实非视觉教学回执、人物目击不刷新教学来源/时间/跳数、两跳求助不挂幽灵承诺、远方不可达承诺遵守原退避、删除直接来源与目标仍可恢复、线索洪泛保护近期反证/教学、首次发现尸体且排除普通战斗目标、行走/手动宿主未完也能观察。它们不代表T08目的或百人供养已经交付。

`agency_food_smoke.gd`核缺料精确取物/开锅/打断与恢复/续锅进食、自身背包与玩家共同规则；`agency_learning_smoke.gd`核真实拒教后取书/读书/实践。`agency_boundaries_smoke.gd`核交付/倾向差异/紧急抢占/预算和坏档，`agency_custody_smoke.gd`核公料换用途/撤权归还/短忙不退料重领，`agency_failures_smoke.gd`核拥挤时自身候选、私人饭归属、无饭不无谓抢占、instant完成与不可见旧址退避。分别短运行，不组合为默认长回归。`agency_ui_smoke.gd`通过原Game、真实文件与原生按钮观察NPC自主读书；私有目的仅F12决策诊断显示，普通人物页不透露。它们不是百人宗门供养或图形性能验收。

`institution_duties_smoke.gd`与`institution_channels_smoke.gd`核现场职责的真实发布、读案、受理、生产/配送、回报、重复周期和恢复；`institution_duty_recovery_smoke.gd`核来源耗尽、受阻释放、缺席到期和换任；`institution_channel_edges_smoke.gd`核旧缓存争抢、条款伪造、旧案现场结案、告示容量、双用途材料/饥饿抢占和有限记忆；`institution_duty_distance_smoke.gd`核远源复检与删除来源回报；`institution_channels_ui_smoke.gd`在真实窗口核查阅→受理→领物→中途存读→配送→回报→撤回告示。它们共同证明T09c链路，不代表T09d联系、T10教学、T11供养或百人装配。

`society_state_smoke.gd`核相识、实际送达、拒绝/延期、时间零/惰性过期和坏档；加`-- --lifecycle`核真实履行、第三方满足和死亡保留责任。`society_boundaries_smoke.gd`核条款修订、份额别名和历史压缩；加`-- --capacity`核一人向50人当面委托与联系人保护，加`-- --cooldown`核冷却容量恢复。分别独立短运行；这些是T09d-1内核证据，正常求助/个人判断与GUI闭环仍按后续小项验证。

`navigation_smoke.gd`由kernel调用，`tile_smoke.gd`复用features的世界；它们和feature/sight/equipment一样是RefCounted模块，不直接用Godot的`--script`启动。其余SceneTree专题按下面的范围选用。

`tool_smoke.py`在修改Python运行或性能工具时使用，核对进程退出/超时、历史复用、单倍率次数上限及不可比条件，不启动游戏。性能用真实release短窗口，不用smoke通过数量代表容量。

`ui_smoke.gd`按需单独运行，约数秒核对实际GUI输入、共享格子数量取放、图标换装/卸下、人物与背包并排和缩放、工具取消/旋转、交互上下文和小地图只移动镜头、迷雾详情、人物事件与百分比缩放确认，不加入kernel默认套件。图形运行将本机截图写入忽略的`logs/ui-smoke/`，缩放探针不写用户偏好；不冒充全玩法人工游玩。

`equipment_smoke.gd`由`test --suite equipment`调用，覆盖满包换装/卸下原子性、真实伤害/护甲/移速、发射后换装、品质转移、派生缓存恢复、非法槽位拒绝和身体槽位重用；原磁盘续接反例同时核对穿戴。功能性能对照独立使用[capacity入口](../docs/engineering/tooling/usage.md#功能性能对照)，不加入默认测试。

`experience_smoke.gd`按需单独运行，针对普通/压力场源分离、冷热耐受/小数余量、危险中禁止恢复、战斗不吃耐受、死亡顺序、有界个人日志与存读做短反例，不扩大kernel默认套件。

`act_smoke.gd`按需单独运行，核对已退休RTS指令拒绝、三连/锁向/短缓冲、动作承诺、步长与慢域节奏、闪步/CD、弓持续发射/松手、扇射保护、墙体积/移动折线扫掠、在飞弹跨射手死亡、生活中断释放预约、候选恢复及非法状态拒绝。`act_ui_smoke.gd`在真实图形窗口核对WASD/鼠标攻击/武器技/真装备/闪步、F交互、旧按钮移除、失焦/背包/暂停清输入及音频播放器触发；截图在`logs/act-ui/`。它们不证明正式动画、音效混音或人工试玩已收敛。

暂停检查区分冻结世界与清除输入：kernel核对暂停后世界时间不推进、管理命令回执仅交付一次；`act_ui_smoke.gd`核对暂停中按闪步后恢复不会补发动作或重播持键。普通非暂停界面仍允许世界继续运行。它们不替代全部跨界面操作的人工检查。

`response_smoke.gd`按需单独运行，核对Runner诊断信封的时间先后、回执绑定/只消费一次与原请求不被修改，不加入默认kernel套件。真实窗口的合成移动响应测量见[响应链实验](../docs/engineering/tooling/usage.md#响应链实验)；短检查不证明操作手感或显示器延迟。

`control_smoke.gd`覆盖P1键鼠配置的上下文冲突/安全交换/保存重载/损坏回退，旧输入代次失效、玩家与NPC缓冲的恢复边界，以及直角墙、单格门和高速身体扫掠。`control_ui_smoke.gd`在真实图形进程通过实际GUI输入改键、确认交换、Shift反复捕获、失焦清捕获、鼠标侧键触发世界动作、重启保留/恢复默认、缩放/小窗口布局、自由镜头瞄准和锁向分离；偏好使用独立测试文件并清理，截图在`logs/control-ui/`。两者按需单独运行，不扩大默认kernel套件；Windows原生Alt-Tab实查与本机走查证据见BASELINE。

`movement_smoke.gd`单独核对斜向接触的合法落点与分段净空、立即退开、旧微小重叠恢复而不穿整墙、两种身体的地图边界、真实平砍贴家具及恢复后离开、家具南侧一格通道。`movement_ui_smoke.gd`在真实窗口核脚点与GPU位置一致、家具和人物的批次排序、原生鼠标斜向三连后用键盘走过通道；截图在`logs/movement-ui/`，测试档/偏好独立清理。它们不将人物整张贴图高度视为地面碰撞，不加入默认长矩阵。

`melee_smoke.gd`验证P2三连/终结收招、分类型短缓冲和失效、闪步90ms边界、箭穿避伤者/掠过身份存读、单刀无假确认、稳固/原收招保留/单次失衡、控制预算与残余击退不劫持新闪步。`melee_ui_smoke.gd`在真实图形窗口用鼠标/键盘完成轻敌三连、重敌稳固→闪步→收招重斩，检查图形会话保存/恢复不重复伤害或刷新CD、三种练习切换/死亡重开、反馈偏好/200%UI、镜头不扰瞄准及多目标音效合并/预留通道；截图在`logs/melee-ui/`。两者按需运行，不扩大默认kernel套件，不代替人类手感与主观混音判断。

`abilities_smoke.gd`验证P3递归只读定义、独立资源变体/非法时序、规则签名拒载、多人CD与激活隔离、散射/追踪与失视退化、减速/DoT和预警/区域/飞剑中途恢复；覆盖来源死亡、目标移除、到期半开区间、到期前续期当拍跳伤、飞剑损毁不吞后到弹、接回不抹早到攻击、墙阻/重合回收和非法弹状态拒绝；制作/恢复载荷共用校验，非法格挡比例/时长、状态标识和嵌套状态整份拒载，宿主不支持的效果阶段拒绝编译，零前摇缓冲召剑在启动时刻只交付一次。按需运行，不加入默认kernel套件。

`action_timing_smoke.gd`核对真实铁剑命中后缓冲等待CD、恰在原截止时刻启动、挥空过期及NPC中途恢复；另验器物收集不提前采用状态、早死截断后命中、死亡同撞墙与先落地/接回再死亡的落点。

`effect_ownership_smoke.gd`核对防御效果自身归因与平面cause、长短控制的独立期限/移除回算、光环固定模板槽与成员撤销、普通驱散保留source贡献、来源消失只撤依赖贡献、显式标签压制/恢复、同毫秒DoT与压制顺序，以及坏类型/聚合拒载。

`facility_lifecycle_smoke.gd`核对开局/地区/人工设施的碰撞、容量/物资不重复、共用放置规则、受控删除与登记拆空后恢复；覆盖地板/实体同格、取空堆的自身run、盆栽双向宿主/索引及坏档拒载。

`outcome_ui_smoke.gd`在真实图形进程核护盾到期/破盾通知、无来源但作用于玩家的结果、未知通知安全忽略，以及真实取放物资的操作者特效。它不把所有通知target都当作身体，也不证明全部特效已经完成美术验收。

`abilities_ui_smoke.gd`继承图形输入辅助，通过原生下拉框和真实鼠标/键盘选择八套范例并施放左右键；检查状态/弹体发布、落雷预警和飞剑返航中的实际文件保存/恢复。截图在`logs/abilities-ui/`；独立测试档和偏好结束后清理。`combat_authoring_editor.tscn`在一次性Godot编辑器中加`-- --combat-authoring-check`运行，验证真实Inspector插件、范围/阶段布局与合法/非法资源提示，截图`logs/combat-authoring-editor.png`并自动退出；未带该参数时不会自动执行。具体命令见[usage](../docs/engineering/tooling/usage.md#开发期直接试玩)。

`action_foundation_smoke.gd`核对公共门禁、陈旧run通知、正常收招后的续段、一次终止、坏载荷/幽灵预约拒载；`action_domains_smoke.gd`核对工作/伤害先后、新生短到期、手工/ACT照料消费/恢复。`action_domains_ui_smoke.gd`以原生配置选择和真实右键验证选定植物的ACT交付；截图仍归`logs/abilities-ui/`。按需运行，不扩大默认kernel套件。

P4新增检查按改动选用，不加入默认kernel长矩阵：

| 检查 | 必要反例 |
|---|---|
| `action_resources_smoke.gd` | 资源别名/多成本原子性、修饰重建、盾/格挡/真实吸血、同刻姿态和半开到期 |
| `action_reactions_smoke.gd` | 命中/定时分裂残段、兄弟共享预算、死亡传播、跨施法满层、两目标标记脚本与在途恢复、完整动作FIFO/不污染缓冲、零方向接触派生；来源移除/身体槽复用后的攻击力与阵营、两代传播/受伤反击归因、快照恢复及坏lineage/快照/反应阶段/emit模板拒载 |
| `action_spatial_smoke.gd` | 召唤独立感知/人口需求隔离、图腾光环/可破坏受体、瞬移无隐藏避伤、双器物回收不修复；精确到期/主人死亡/单槽损坏/地图边缘与身体页扩容；受控随从周期、定义持有规则恢复、移除身体清未启动请求 |
| `action_combinations_smoke.gd` | 血刃获怒→耗怒→守势/回元、远程四槽；弹/传播/双盾/狼/图腾/双剑共存恢复后结果一致；合法取消后不继承旧惩戒窗口 |
| `action_combinations_ui_smoke.gd` | 真实键鼠左右键/E/C、原生配置切换、多槽HUD、两条组合及机制显示、四种实际文件存读、旧选中对象不可见仍可出招 |

P4 GUI截图归`logs/abilities-ui/p4-*`，独立测试档/偏好自动清理。组合GUI用已有手动指令暂停靶子政策，保留原HP/技能/物资规则；NPC三类挑战另由P5 GUI核验。窗口激活与原生popup分别确认焦点，合成键发往实际Window ID；完整组合含多次文件交付，可单次20秒上限执行，默认kernel仍15秒。近战路线检查原生E/C；指向位置的技能用临时原生鼠标侧键映射，执行后恢复原映射且不写偏好。合成MouseMotion不会移动Window读取的系统鼠标，不能把注入成功冒充系统指针已到目标。`combat_authoring_editor.tscn`另覆盖共同Status/Reaction/Loadout Resource校验、缺失template和嵌套/跨类型引用提示，不只验证Ability预览；定义规则还验证坏Loadout短路与原生DoT周期一致性。通过这些检查不等于正式手感、长局或密弹容量验收。

`framework_smoke.gd`按需核对移速变化缓存的到期/换装/恢复、多目标重建与槽复用；索引的当前位置/阵营/死亡/扫掠dt和负查询边界；通知只交付一次、旧Frame不可变、非full弹信息、身体布局匹配、暂停管理命令/环境刷新及只读配置。它不加入默认kernel套件。

`python tools/check_structure.py --audit-code`核当前文档链接/标题锚点、原生Resource/场景字面路径与UID；静态可达图包含data与项目Inspector插件，不把仅由.tres引用的类型当死代码。它仍不能证明动态引用或运行语义。


`decisions_smoke.gd`按需独立检查P5：政策编译/只读/参数与个体隔离、采集—威胁—重选、预约和已交付物资、陈旧run、连段/合法取消与中途恢复、射手回退/拉距、重敌承诺、受信评分实际出招、休眠和需求阈值、手动交接、失败退避、移动通道恢复、被困逃离、buffer作废、单次居民命令/目标消失/即时操作、召唤限额与序列失败/外部替换、坏schema/唤醒配对拒载。约7秒，不加入默认kernel；保持15秒watchdog。

`decision_feedback_smoke.gd`按需核对通用执行反馈：即时拒绝及记忆目标探索的异步寻路失败保留操作/目标，实际改选可达设施并交付；失败和在途任务中途恢复、人物/操作隔离、16条上限、期限/坏数据拒载、真完成清理及手动绕过。另核对未变化的观察时间与隐藏库存/全图地形版本不清失败，新观察和期限允许重试；施工承诺等待不反复规划、可见空位置当场证伪且不更新远处人物。约4秒，不加入默认kernel，保留15秒退出上限。

`decisions_ui_smoke.gd`以真实图形/键鼠检查三类策略输出、原生练习切换、交战中实际文件存读、独立记忆与手动移动/出招；截图`logs/decisions-ui/`，独立档/偏好自动清理。原生Inspector检查另覆盖Policy/Library/评分范例及坏距离带，截图`logs/decisions-authoring-editor.png`；编辑器截图使用显式force_draw，避免等不到后台窗口绘制信号。它们不代表主观手感、完整Boss或长局验收。

生活、作业位置及会话边界按需独立运行，不加入默认kernel套件：

| 检查 | 必要反例 |
|---|---|
| `livelihood_smoke.gd` | 成长阻挡检查身体半径、已知满箱/未成熟种子候选、过期协作与手动控制、站在自建占地后的接近、单次工作/社会伙伴不被普通需求打断、忙碌协作不转入无关工作、远方本人蓝图记忆、定身时完成已在作业位置的取放 |
| `work_positions_smoke.gd` | 非阻挡植物/木材本格、盆栽宿主、多格四邻/大身体角点净空、固定工位四向旋转/堵塞、可复用配置校验、真实烹饪、完整占地被身体占用时等待、等待中/施工中恢复和劳动一致、开工阻挡/中断续工/拆除、非法阶段拒载、多人施工竞争不重启成品或污染存档、寻路预算耗尽时仍选择直接可达位置 |
| `work_positions_ui_smoke.gd` | 真实图集的单格/横向/纵向半成品、旋转占地、单灶台工位发布、真实文件恢复、施工阶段详情与原生续工按钮完工；截图`logs/work-positions-ui/` |
| `ui_session_smoke.gd` | 空对象菜单、背包快捷键开关、键盘平移脱离跟随、200%窄屏抽屉、失效目标清理、可见未选中工具目标、选择切换关闭旧容器/人物详情、地板拆除、暂停菜单读档恢复原暂停状态与正确选择；截图`logs/ui-session/` |

两个图形专题使用独立测试档/偏好并在结束后清理。以上覆盖真实状态与针对性反例，不代表完整物流、锻造玩法或长局验收。

`view_ui_smoke.gd`在真实窗口核对世界直接绘制、斜视分部素材、墙体伸出占地的alpha拾取、同深度选择、震动下视觉选择；覆盖多种窗口/缩放的原生坐标反解、震动不改瞄准、实际系统指针、暂停平移/迷雾、奇数与1366×768窗口的竖直像素边逐行稳定、旧形变偏好忽略/清除。截图`logs/view-ui/`；普通非整数缩放的采样特性不等于透视切变。原移动、控制、普通UI、作业与P4组合图形检查继续使用共同ViewRig定位输入。

`institution_access_smoke.gd`按需核岗位Resource/定点与物品授权、真实领料/撤职留锅换人接续、指定床资格与现场预约分离、改安排中断与隐私、窄退料及坏范围/签名拒载；另走无宽权NPC自主备料烹饪。`institution_access_ui_smoke.gd`用真实Game文件与原生表单领公粮、查看禁用专用床并实际存读，截图归`logs/institution-ui/`。它们不代表组织职责/事项或百人供养已经交付。

事项相关短检查按实际变化独立选用：`institution_matters_smoke.gd`核多人部分交付、已受条款不被修订改写、当面托付→自主备料实际生产及植物按声明用途采送；`institution_obligations_smoke.gd`核原库往返/私人寄放/错用途余料不计、重放不能转记另一份额、施工暂停存读/恢复、超期和死者责任不暗重发；`institution_production_shares_smoke.gd`核静置/他人收尾、不丢受托、近期证据淘汰后的进度及共同采木用途/恢复；`institution_matters_bounds_smoke.gd`核512事项/4096份额容量与闭合引用；`institution_matters_review_smoke.gd`核跨处用途拒绝、已知满仓/工位消失退料、非本源批次及释放后下调总额恢复；`institution_matters_handoffs_smoke.gd`核过期求助显式再办、原采木撤权/收尾重入和临时自主探索取消。`institution_matters_ui_smoke.gd`在真实Game原生点施工协作/选择助手、文件存读并沿原工地完工，截图仍归`logs/institution-ui/`。它们不能代替T09c自主职责/现场通道或最终百人供养。

`society_recovery_smoke.gd`默认核迟到的事项关闭；`-- --death / --construction / --removed / --accepted / --bad / --strict / --allocation / --proposals / --origins / --archives / --labor`各为独立短运行，覆盖旧冷却锚点、移除后完工保责任、接受跨回应窗、回复与Share起源/取消原因坏档、跨事项施工分配与无主地提案、真实归档/同源工位和死者生前劳动的延迟核销。`society_judgment_smoke.gd`默认核实际本人判答后施工/目击支持，`-- --remote / --needs / --exchanges / --influence`分别核远方归因隔离、饥困/预算/手动/玩家、经历/水位/坏档/死亡，以及实际交流影响同一个请求。挂起/延期后的正常UI仍待后续小项，不能以直接内核调用替代成品交互验收。

`society_judgment_smoke.gd -- --scope / --defer / --teaching / --memory`独立核窄授权/配方估算/非成员、单次有因延期、真实交易与教学受益，以及25次真实交谈后的有界重要经历保留。默认模式清空助手木料，证明私人蓝图沿原预付材料建造，不另开自动运输合同。

`society_followup_smoke.gd`默认核接触失败的纯时钟退避，`-- --player / --defer [--recover] / --hidden / --late / --seek`独立核玩家显式回应与在途恢复、延期后实际进食再回应施工、双方均不知第三方完工、跨响应窗口的履行消息，以及缺劳动能力者自主求助。`society_followup_boundaries_smoke.gd`默认核本人/第三方撤单的实际消息，`-- --release / --budget / --absent / --unbound / --partial-budget / --known-dead / --resident-busy / --single-request / --long-work / --history / --need-budget / --player-participation / --reply-scope / --unseen-followups / --local-review`分别核显式释责、预算保留、失踪不泄露位置、自由参与恢复、111～127余量重唤醒、本地死亡认识、忙时保复评、单目标不重复求助、长工序复评及32条关闭历史后新请求的实际回应；追加预算不足后的紧急重评、玩家自由参与严格恢复、逐请求退避不串扰、16个失联已接受跟进+满目的目录实际答复与无预注入的接触线索。`society_followup_ui_smoke.gd`在真实Game原生“人物→约定”页点击延期、保存/读回在途回应、再点击接受并核可见消息和玩家控制；截图归`logs/society-ui/`。这些验证不代表百人供养或多人教学已经交付。

`cultivation_smoke.gd`单独核播种取消/进行中恢复、同机制两作物、实物种子/水、幼苗观察、满水健康拒绝、受托投入结清及保权移除、成熟跨界/满株余时、非法时钟/占株/签名拒载；`-- --source-cycle`沿原World跨三个昼夜核自然增量、有限井水、缺水停长、补水采收后再产出及恢复，未缩内容周期。`cultivation_ui_smoke.gd`在真实D3D12窗口点播种/照料、实际文件存读和正常湿度反馈，截图归`logs/cultivation-ui/`；不证明百人供养、全年平衡或性能极限。

# 当前运行基线

更新：2026-11-15。本页只保留当前构建、有效证据和已知限制。能力查[FEATURES](features.md)，运行接口查[架构](../engineering/architecture.md)。

## 当前构建

Godot 4.7.2 stable（ed1daf0bf），GDScript，Windows release，D3D12 Forward+，1280×720，无VSync。正式入口scenes/main.tscn；当前P4成品为build/windows/act-p4/reol-act.exe及同目录pck，源码试玩和导出快照的差别见[usage](../engineering/tooling/usage.md)。

当前源码与`build/windows/act-p4/reol-act.exe`＋pck为基础框架优化后的P4测试版，由根目录启动.cmd选择源码或成品；默认血刃＋混战，顶栏切星焰行者、机制范例或单轻敌/单重敌。当前PCK SHA256为`bbc0b8cba166b1e91cdbd5c9fae8a4b1fe30e9f660d7380a806365a0a8f03346`，exe为`3d19ee4a764e8bb153bfa7f811f98e0dfb0139c9e0c8bc6b76b93d3ed09185bf`，导出日志`logs/export-20261115-165136-2276100.log`。源码/实际PCK签名均为`04042c8edd9719b61192e5932f02a6346dfd643f280714a330d8e8f3e063a928`，40动作/24配置。F5/F9默认format11的`act-p4-quicksave.reol`；本次未改规则签名或格式，优化前有效P4状态可恢复；更早缺来源快照的开发档仍拒载并保留。优化前审查包PCK为`8607ecc200ee8be03984d5b3acc3803be00fdc4656e3a0340cf4500132fe02a3`，归档于`build/windows/act-p4/archive/framework-before-20261115-1655/`；更早审查前包、P1/P2/P3包和旧档保留。

原正式人物/装备/背包版由02958cc提交对应，PCK指纹、开发机与各倍率历史样本统一记录在[performance.json](performance.json)。它是工具可直接读取的数值原件，包含实际倍率而非倍率达成比例；本机原始报告在logs/capacity-20261113-shipped/。不要求新机器拥有这些日志才能接手。

## 已接受测量与验证

历史capacity-v1测量包含真实生活、房间、植物、环境、固定交战与施工群，零死亡且物资守恒。它用于后续同负载性能对照，不是全员同时交战或所有未来内容的普遍上限。采样/判据与工具入口见[usage](../engineering/tooling/usage.md#功能性能对照)。

人物换装的真实属性、原子转移、候选恢复和NPC只读交互已通过相关短检查；证据在logs/ui-smoke/与logs/smoke-20261113-222841-372329000.log。旧容量报告完成了19个窗口，仍保留作历史参考；今后的验证强度只查开发循环。

工具精简后以同一包的900人/4×历史配置做25秒复核，真实窗口通过；该次步均较历史约−4.4%，运行代码未改，只视为短窗波动，不替换已接受基线。证据在logs/performance-workflow-20261113-verified/；首个窗口因工具精确比较镜头浮点数被误判失效，已修复容差并补短反例，本次该倍率共运行2次，没有扩测其他倍率。

玩家外围地表/矮物准备与共享柔边通过源码图形对照：墙角半格墙体、斜移、0.1格移动、历史探索、开阔地、地图边界、100格视距、零视距没有采到透出的未缓存地表；三种窗口/缩放下遮罩对齐、静止复用与失效更新通过。相关sight/feature短检查、普通24人入口、外围对象不可拾取及夜间全遮蔽检查通过；截图、探针与日志在logs/fog-inset-20261114/。当时的整套kernel检查触及15秒进程上限，未取得全套通过结果，最新日志为logs/smoke-20261114-072426-79927300.log。

同一1280×720静态墙角负载（仅绘地表/静物/迷雾）、RTX3060、D3D12源码运行中交替旧/新显示，各取360帧，移动遮罩的视口GPU均值（新显示含遮罩子视口）约0.17→0.11ms。120次连续跨格观察的CPU均值约4.37→5.01ms/次，新增工作只在玩家本次观察变化时准备，不逐NPC或逐显示帧执行。该局部对照不重测人口容量，不替换release历史基线；截图间的限帧/设备时钟状态不用于算法成本比较。

ACT灰盒的kernel、ACT规则/候选恢复、response诊断、Python工具与两套真实GUI短检查已通过；最新日志分别为`logs/smoke-20261114-160910-240530800.log`、`logs/act-smoke-20261114-161148-601761200.log`、`logs/response-smoke-20261114-155854-491160600.log`、`logs/ui-smoke-20261114-160242-124340500.log`、`logs/act-ui-smoke-20261114-160310-562676900.log`，图形截图在`logs/act-ui/`。这证明相关流程可执行，不证明主观手感或音频混音完成。一次全套规则打印0错误后仍因总时长超过15秒失败；分段诊断在14.37秒结束规则，余下退出超过时限，日志为`logs/smoke-20261114-160532-347803600.log`和`logs/kernel-profile-20261114-160815-422258600.log`。保留15秒上限，把最前面的512人双配置固定6秒推进改为至少1秒且两者均已完成真实交付后结束，所有既有断言保留；上述最新完整进程退出通过。

60Hz普通24人25秒窗保持约1×、帧p99 16.80ms，合成移动到CPU显示准备p95 18.72ms；900人ACT高密交战复核后仍只有约0.748×，没有通过规模验收。方法、构建哈希和失败细节只维护在[专题研究1.3](../../design/research/act_barrage_references.md#13-60hz灰盒与密集交战实测)，不替换历史performance.json。新压力场景标为capacity-act-v1，工具阻止与旧capacity-v1或不同心跳的步均直接比较。

### P1直接操控验证

P1没有新增人口/弹量性能测量，没有改地图规模、植物/环境精度或权威身体半径。2026-11-15完成以下相关检查，图形进程串行运行在D3D12/RTX3060：

| 检查 | 证据与范围 |
|---|---|
| 输入/配置/空间规则 | `logs/control-smoke-20261115-001845-668905600.log`：改键冲突/安全交换/配置重载/损坏回退、旧代次拒绝、玩家与NPC缓冲恢复边界、单格门/墙角/快速身体扫掠通过 |
| 实际GUI改键与方向 | `logs/control-ui-smoke-20261115-002503-641881700.log`：点击设置控件、Shift反复捕获/释放、确认交换、键鼠互绑、失焦清捕获、重新启动保持配置/恢复默认、UI比例200%与960×540窗口、自由镜头/不同缩放瞄准、锁向分离通过；截图在`logs/control-ui/` |
| 既有ACT及生活UI | `logs/act-ui-smoke-20261115-002712-81284000.log`与`logs/ui-smoke-20261115-002301-99752000.log`：剑弓/闪步/持续输入、背包取放/营造/旋转/换装等仍通过 |
| 共同规则和回执 | `logs/smoke-20261115-002122-510040500.log`、`logs/act-smoke-20261115-002112-949364600.log`与`logs/response-smoke-20261115-002112-949377500.log`完整退出通过 |
| 图形空间走查 | `logs/space-walk-20261115-002222-536248600.log`：实际输入贴墙停止、侧滑至单格门后通过、L角阻挡与非法自拿取拒绝；`lab-wall/door/corner.png`已观察 |
| 两路线接敌/脱离 | `logs/p1-lab-slice-20261115-002946-215880700.log`：同一24人测试开局，剑两段实际命中后向左闪步脱离，弓命中后向左闪步脱离；两次末尾玩家HP100。`lab-sword.png`、`lab-bow-exit.png`已观察。不是完整遭遇平衡或持续十分钟人工手感验收 |
| Windows原生切窗 | `logs/p1-native-focus-20261115-002004.log`：由本机Win32扫描码/鼠标输入持弓移动，发送真实Alt-Tab失焦并在外松键，再切回；收到原生焦点通知，持续状态清零，无自动续走/续射。该项为源码图形进程，release普通启动另单独验证 |

两位顾问对候选源码各完成一份静态审查，原件在`.local/advisor/p1-implementation-20261115/review/`。采纳了晚到失能值会擦掉新缓冲、修饰键捕获释放身份、模态逐层返回、失焦清捕获、可缩放滚动区、无目标F不急停与锁向显示边界等建议；未把顾问的“无风险”结论当运行证据。持续十分钟的人类手感与正式动画/混音仍留给后续试玩，不冒充已验收。

失败/修正记录：首次headless主场景仍命中既有`custom_samplers`问题，并发现新增键位标签API不支持headless，后者已作降级；日志`logs/run-20261115-000037-491329600.log`。图形测试的早期鼠标/窗口断言混用了未稳定相机与物理窗口/逻辑视口，已改为等待真实窗口与对应坐标，未放松玩法断言。原生输入脚本首次使用虚拟键而非扫描码未触发Godot物理键映射，切窗检查因此失败，改用扫描码后取得上述通过结果。早期练习场脚本把受害者个人日志中的actor当作攻击者且过早出刀，已改为真实敌人HP下降和命中回执核验；这些失败均保留在同目录日志。

### P2单剑切片验证

P2采用同一512²世界与默认24人，不降低后台生活精度，不追加人口或弹量压力档。2026-11-15完成以下相关检查；图形进程在D3D12/RTX3060串行运行。

| 检查 | 证据与范围 |
|---|---|
| 共同规则/存读 | `logs/smoke-20261115-022423-361352200.log`完整退出，KERNEL_SMOKE errors=0；个人事实环不保存表现Vector2载荷，新增战斗状态进入format9校验 |
| 原ACT与输入合同 | `logs/p2-act-20261115-022506-958762800.log`、`logs/p2-control-20261115-022506-973040000.log`通过：动作承诺/锁向、弹体/墙、回执/旧代次、玩家清意图而NPC恢复等；旧断言按新取消时间和1.6格后撤更新 |
| P2规则与审查反例 | `logs/melee-smoke-20261115-022334-689183900.log`通过：三连/收招、单槽/过期/CD、90ms避伤端点、箭穿避伤者及passed恢复、单刀不假确认、稳固/原收招/单次失衡、控制预算、残余击退不劫持新闪步；另覆盖到期末端确认、命中前续刀、临近CD的挥空分支/早确认丢弃、读档不提前AI决策和无硬直击杀截断危险片段 |
| P2实际图形流程 | `logs/melee-ui-smoke-20261115-022352-711197200.log`通过：鼠标三连击杀120HP轻敌，进身轻斩只扣血不打断重敌，D+Space避重劈并穿身，右键68伤害/400ms失衡；实际会话保存/读取保HP/CD/已开始重斩且不重复伤害，模式切换和真实死亡后重练通过 |
| 反馈与设置 | 同一melee GUI检查覆盖200%UI、独立偏好文件保存、镜头偏移不扰瞄准、多人同刀合并、跨帧更高重音替换声道及预警/玩家受伤保留通道。`logs/melee-ui/`的稳固、收招淡青标、失衡、射手收招撤线截图已观察；只证明合成流与播放器/分层触发，尚非主观听感或正式混音验收 |
| 普攻混战闭环 | `logs/p2-basic-combat-20261115-022745-490829500.log`：同一混战开局仅用WASD/左键/闪步处理三敌，结束HP89、世界3.633秒、无武器技CD；截图`logs/melee-ui/mixed-basic-clear.png`。这是读取Frame控制输入的自动走查，不代表人类难度或十分钟手感结论 |
| 生活UI回归 | `logs/p2-life-ui-20261115-021226-989414200.log`取放、施工/取消、真装备/卸下、面板/缩放通过；没有把P1改键GUI的旧通过记录算作本包新增通过 |
| 最终release短窗 | `logs/p2-release-final.json`与同名log/png：24人/单轻敌练习/玩家迷雾、60FPS、1×、3秒预热＋5秒采样，实际约1.000×、帧p99约17.43ms、步均约0.326ms、零过载需求。最终exe/pck身份与上文一致；不与旧高人口负载直接比较，不替换performance.json |

双顾问实现审查均完整返回，原件在`.local/advisor/p2-implementation-20261115/review/`，采用/拒绝依据见[研究](../../design/research/act_barrage_references.md#p2实现审查与交付取舍)。顾问只做附件静态审查，未实际操作或听评游戏。

失败与边界：早期新GUI走查在重敌2.1格外直接挥剑，属于操作脚本未进身；修成真实WASD接近后通过，未扩大剑范围。初版混战射手距离超过警戒范围，已调整出生位置；死亡后的通用输入限制原先挡住重练，已修正并实机验证。P1完整`control_ui_smoke.gd`本轮未取得通过：脚本要求系统游标停在(616,314)，实际游标多次落在窗口外/其他位置（`logs/p2-controls-ui-20261115-021632-160430300.log`等）；当时镜头offset=0、焦点=true、无模态，尚未证明游戏转换错误。临时诊断未留入测试，也未降低方向断言；P2的实际点击瞄准、震动转换反例及输入规则分别通过。未重做原生Alt-Tab、目标低配机、长局或主观混音验收。

### P3框架与范例验证

2026-11-15完成原生Resource作者层、World四类过程与八套范例；图形检查串行运行于D3D12/RTX3060。仍为512²地图/24人，没有降低生活/环境/植物精度，没有新增人口或弹量压测。

| 检查 | 证据与范围 |
|---|---|
| 原内核/ACT/输入/近战 | `logs/smoke-20261115-044819-430503600.log`与`logs/p3-act-rules.log`、`p3-control-rules.log`、`p3-melee-rules.log`完整退出，errors=0；验证原World恢复/装备/生活，以及迁为资源后的P2规则 |
| 框架规则与时序 | `logs/p3-abilities-rules.log`完整退出errors=0：资源值隔离、缺失子资源/非法时序/签名、多人CD/激活、散射/减速/DoT/追踪、区域/器物恢复、死亡/移除；续期端点、同区间碎剑不吞后弹、接回不漏早接触、墙阻/重合与非法候选反例通过 |
| 新技能真实GUI | `logs/abilities-ui-p3.log`：原生下拉框八套选择、鼠标左右键命中/技能启动/状态发布；落雷预警及飞剑返航中的实际文件保存恢复保持原状态。`logs/abilities-ui/`火扇、雷预警、追踪/状态与飞剑截图已观察 |
| P2图形回归 | `logs/melee-ui-p3.log`完整通过：轻敌三连、重敌稳固/闪避/失衡、实际保存、200%UI、反馈/死亡后重练；未以新范例取代原单剑流程 |
| 原生Inspector | `logs/combat-authoring-editor.log`：实际编辑器中的预览布局、字段校验、非法时序提示通过；`logs/combat-authoring-editor.png`已观察。插件为项目自有轻量Inspector增强，YARD等未安装 |
| 最终release短窗 | `logs/p3-release-final.json`及同名log/png，最终包在24人/默认火术混战/迷雾、60FPS、1×、3秒预热＋5秒采样下约1.000×，帧p99约17.08ms，步均约0.570ms，零过载需求。没有操作玩家，发生1次死亡；不是持续主动施法/密弹容量或同负载性能对照，不替换performance.json |

双顾问实现与生命周期静态审查均完整返回，原件在`.local/advisor/combat-framework-implementation-20261115/review/`及`lifecycle-review/`；采用/拒绝依据见[研究](../../design/research/act_barrage_references.md#p3实现与生命周期审查)。顾问未执行代码或操作游戏。早期载荷失败为`Dictionary.merge`未覆盖默认值，已修；耐久反例原先混入敌人反击，已分离生命周期与真实受损。早期GUI重练失败为合成点击未更新鼠标悬停，补实际移动事件后通过，未改宽玩法断言。

### P4通用基座与组合试玩验证

2026-11-15完成A1/A2～E及独立包；原World唯一持有状态，512²地图、后台生活/环境/植物精度保持。GUI/编辑器检查在D3D12/RTX3060运行；下列成品短窗为RTX5060Ti，不能直接与旧硬件/火术负载计算算法成本变化。

| 检查 | 证据与范围 |
|---|---|
| 公共准入与跨域 | A1 ACT/MELEE/ABILITIES/ACTION_FOUNDATION/KERNEL和原八套真实GUI/存读通过，`logs/p4-a1-ui.log`；A2 `logs/p4-a2-final-rules.log`验证更早死亡取消较晚交付、较早提交不被较晚死亡抹除、新生短工作、身份/模式/轨迹与水守恒。`logs/p4-a2-ui.log`实际选择植物并用右键引水，与手工同源提交 |
| 属性/成本/状态/防御 | `logs/p4-resources-final.log`，ACTION_RESOURCES_SMOKE errors=0：多池原子成本、重建、同刻盾/格挡/吸血、半开周期与料理；`logs/p4-b-ui.log`实际技能/池/状态和文件存读 |
| 有界反应与脚本 | `logs/p4-reactions-final.log`，ACTION_REACTIONS_SMOKE errors=0：分裂残段、兄弟共享预算、传播、寒印、完整请求FIFO/不污染缓冲/失败无先扣、两目标标记脚本与坏lineage拒载 |
| 空间/实体/器物 | `logs/p4-spatial-final.log`，ACTION_SPATIAL_SMOKE errors=0：瞬移落点/定身、静态受体、召唤隔离、光环精确到期/主人死亡、地图边缘、单件损坏与跨页身体；`logs/p4-combinations-final.log`验证两条完整循环与混合宿主未来恢复 |
| 整合实际GUI | `logs/p4-e-ui-final.log`，ACTION_COMBINATIONS_UI_SMOKE errors=0：原生下拉选择、RMB/E/C、血刃/星焰、分裂/传播/脚本、狼与图腾/双飞剑，以及四种真实文件保存恢复；`logs/abilities-ui/p4-*.png`已观察。偏好和独立测试档已清理 |
| 原生制作 | `logs/p4-authoring-final.log`，COMBAT_AUTHORING_EDITOR errors=0：真实Inspector中的Status/Reaction/Loadout字段、引用导航和缺失模板诊断；原Ability阶段/范围预览保留。追踪默认关闭，DEV开启后F12 `actions`最多64条 |
| 既有规则 | KERNEL/ACT/MELEE/CONTROL/ABILITIES已通过；内核最新完整退出日志为`logs/smoke-20261115-151536-33645300.log`，近战、键位和跨域为`logs/p4-melee-final.log`、`logs/p4-control-rules.log`、`logs/p4-a2-final-rules.log`，定义为`logs/p4-abilities-final.log`。新增槽保旧改键，损坏旧绑定按类型回退，无中途SCRIPT ERROR |
| 导出一致性 | `logs/p4-source-catalog.log`与`logs/p4-pack-restore.log`：40动作/24配置签名一致；用Godot加载实际导出PCK，源码保存的在飞弹/传播/双盾/灵狼/图腾/双剑在途候选被接受，推进后8个相关域状态与HP一致。独立release模板不支持外部`--script`，初次该调用落入主场景并命中已知headless渲染问题，已停止自有进程，不计为通过 |
| 审查前成品真实短窗 | `logs/p4-release-shipped.json`及同名log/png，对应归档P4初版，24人/默认血刃混战/迷雾、60FPS、1×、3秒预热＋5秒采样，实际约1.000×，帧p99约16.86ms，步均约0.498ms，零过载；无引擎/脚本错误。未操作玩家，发生1次死亡，不是持续施法/密弹容量或同负载算法对照，不替换performance.json |

各小阶段均发送实际实现给本机双顾问，A1/A2/B/C/D/E每轮两份答复均已完成核查；原件和开发者裁决见[研究](../../design/research/action_editor_references.md#p4实施审查裁决)。顾问未操作或听评游戏。

修正记录：最终顾问复核补上受控随从周期、定义持有反应的器物/实体恢复、零方向派生、合法取消清旧惩戒、移除身体清未启动请求、旧选中对象不可见时的方向动作与嵌套引用/DoT周期检查，均有相关反例。一次并行运行的kernel打印0错误但进程超过15秒，记录为失败（`logs/smoke-20261115-151439-426778600.log`）；随后同一15秒上限完整退出通过，没有延长超时或删减断言。零方向新反例首版误读弹体字段`direction`，实际为`velocity`，修正测试后无SCRIPT ERROR。GUI首轮重选同一配置不发选择信号、守势收招中回元正确被拒，调整测试等候真实空闲后全程通过，未放宽动作门禁。早期反应结果方向/死亡重复提交、未来区域/新弹索敌、双端残段、无效器物槽封锁、地图边缘和光环移除已按实际反例修复。状态增加每来源/目标/定义的有限实例上限；脚本改显式逻辑版本参与签名，避免导出依赖`.gd`原文。

当前实际范围：属性add/multiply、原护甲、四种状态合并策略与有限控制；未做完整抗性/暴击/伤害转换/词缀、加层不刷新、WoW式完整递减表、随从指挥UI或器物经济。正式动画/混音、平衡/主观手感、目标低配整机/长局与极密弹幕仍待后续。通过工程/交互检查不等于上述体验已验收。

### P4主线合并审查

审查复现并修正三项问题：来源身体移除后，传播状态重新读取阵营会回退为0，下一代可能误传盟友；定时/命中派生重新采样当前源属性或默认20，导致分裂威力随换装/移除改变；旧式slow/dot允许含空格的状态标识，制作成功后运行状态却无法通过恢复校验。已交付弹/区/状态/器物现在保留阵营和近远两项攻击快照，反应沿用；受伤/格挡反击切到防守者快照，完整新行动及自主生产另行采样。起手到实际交付间的属性变化在交付时采用。运行合同版本进入签名，旧候选拒载而不猜属性。

`logs/review-action_reactions_smoke-final.log`覆盖来源在命中前/后移除、身体槽复用、定时分裂、两代传播、反击归因及恢复/坏快照拒载；`logs/review-abilities_smoke-final.log`覆盖定义/在途状态及非法标识。资源、空间、近远组合、近战、ACT、共同门禁/跨域及键位相关短检查通过，日志为`logs/review-resources.log`、`logs/review-spatial.log`和`logs/review-*_smoke.log`；内核完整退出通过，`logs/smoke-20261115-154432-779540600.log`。来源槽复用反例初版错误构造无Entity宿主的companion而被合法拒载，改用正常出生身体后通过；初次失败保留于`logs/review-reactions-snapshots.log`。

`logs/review-p4-ui.log`在RTX3060真实D3D12进程完成两条组合、机制范例和四次实际文件存读，ACTION_COMBINATIONS_UI_SMOKE errors=0，相关截图已观察。`logs/review-source-catalog.log`与`logs/review-pack-restore.log`验证实际修正版PCK签名和源码一致，源码保存的混合过程在包中恢复后，弹、区、状态、器物、池、防御、反应、实体及HP与源码继续运行一致。`logs/review-release-launch.log`为独立修正版exe的24人战斗开局/180帧正常退出，无脚本/引擎错误；合并审查当时没有新增性能容量测量，随后同日的框架研究短窗见下节。

审查当时记录的成本入口为`effects.prepare`、`reactions.prepare`、`Runner._publish`及空间索引；后续框架优化的实际范围与证据见下节，没有展开P5。

### 框架优化前的相关短窗

2026-11-15收到RTS视频字幕后，对当时审查修正版PCK做1次release短窗，尚未改运行代码。i5-13600KF、RTX3060/D3D12、1280×720、512²/24人/默认血刃混战/迷雾、1×60FPS、workers0，3秒预热＋5秒采样。`logs/framework-release-24.json/.log/.cpu.json/.png`完整退出，无脚本/引擎错误：实际1.0001×、帧p99 16.81ms，World.step均约0.50ms，发布累计70.357ms/300步（约0.235ms/步），viewport GPU均约0.079ms，零过载。统计窗口与逐步样本均值存在取样边界差，保留原值，不制造精确统一数。

玩家未操作，发生1次死亡，窗口有9次命中、23次交付；只能说明现普通近场加后台的短窗，不证明持续施法/密弹容量。未与其他显卡或火术负载计算提速，不替换performance.json。新增CPU归因和整数运算微基准的条件、结果与限制归[研究](../../design/research/large_simulation_optimization.md#rts性能视频字幕核查)；headless归因不当作FPS证据。

### 基础框架优化交付

实现提交`fe4fdcf`，范围归[架构](../engineering/architecture.md)，选型/顾问裁决归[研究](../../design/research/large_simulation_optimization.md#godot原生能力与本轮实施取舍)。512²地图、60Hz和现有世界精度保持；没有几何版本缓存、流场/LOD、每格人数截断或新技能。当前独立包由`build/windows/framework-final/`复制到原P4入口，exe/pck与上述指纹一致。

同i5-13600KF/RTX3060/D3D12/1280×720/迷雾/1×60FPS限帧、3秒预热＋5秒采样，`framework-combat-v1`使用同一World中的星焰连发/焰种/控制与耐久三敌，后台正常生活。24人一页自动串行，512人两页自动两worker。前测为原算法加相同诊断，后测为最终代码；每档各一次最终对照，中间补丁窗另留记录，不择最好窗作最终值。

| 人数 | 模拟步均，前 → 最终 | 步p99，前 → 最终 | 帧p99，前 → 最终 | 实际流速，前 → 最终 |
|---|---|---|---|---|
| 24 | 1.161 → 0.752ms | 5.394 → 2.236ms | 16.742 → 16.709ms | 1.0001× → 1.0001× |
| 512 | 9.182 → 8.341ms | 15.884 → 14.533ms | 16.859 → 16.720ms | 1.0001× → 0.9967× |

证据为`logs/framework-{before,final}-{24,512}.json/.log/.cpu.json/.png`，均完整退出、无引擎/脚本错误、资源守恒和零过载需求；不替换performance.json。步均用全窗累计差，分位数用样本窗，两种均值不强行统一。主线程process均值24人为0.864→0.642ms、512人为3.060→2.586ms；GPU未改算法，窗间波动不当作提速。512人最终发布累计200.232ms，对照194.554ms，没有总发布成本下降结论；full次数301→62，减少慢统计被通知带动，但动态状态/身体复制仍存在。索引子计时累计787.874→658.091ms。24人索引调用/细段530/465保持，512人为1692/1592→1685/1585，变化来自世界时间采样端点，并非主动减少真实细段。

24人模拟步均约低35%、512人约低9%只是这两次短窗的观察，不是所有玩法保证。中间补丁窗512人为7.94ms，最终为8.34ms，说明单窗波动；帧尾不能据此承诺改善。峰值只在开局以来主步边界观察到10弹/4状态，包含实际施放尝试被承诺/CD拒绝的过程，不证明密弹容量或人工输入延迟。命中/交付差几次与慢统计/采样边界不齐，规则等价另验，不用活动量变化证明优化。

`logs/framework-final-normal.json/.log/.cpu.json/.png`在实际P4入口另核默认24人血刃混战：世界0.9999×，帧p99 16.812ms，步均约0.503ms，主线程process约0.524ms，发布累计42.572ms/299统计步，零过载，无错误；玩家无操作，不作为持续战斗窗。

相关验证与限制：

- `logs/framework-final-equivalence.log`：临时reference子类保留优化前World.step/Effects.prepare/Scan.index，24/512人各360个固定16/17ms步，逐步outcomes、move_scales、motion一致，最终全部持久域/页一致。只针对这次变更，不作为全游戏长期确定性约束。
- `logs/framework-smoke-final.log`：到期/换装/多目标/恢复/槽复用、当前几何/阵营/死亡/dt、通知只消费一次/旧Frame不可变/布局/暂停管理命令通过。资源、空间、跨域、反应及原P3相关检查见`logs/framework-final-action_resources_smoke.log`、`framework-spatial.log`、`framework-domains.log`、`framework-reactions.log`、`framework-abilities.log`；Python工具短检查通过。
- `logs/framework-ui-final.log`与最终代码的`framework-delivery-ui.log`：真实D3D12下原生键鼠/配置选择、血刃/星焰、分裂/传播/召唤/光环/双剑、四次文件存读通过，截图`logs/abilities-ui/p4-*`已观察。首轮点目标键盘因OS鼠标位置在warp后被覆盖，合法返回target_blocked；测试补同刻指针事件后通过，没有放宽目标/地形判定。首版新反例伪造不完整hit事件触发脚本错误，改用真实damage路径；暂停反例先误用source命令字段，改为合法tile目标后通过，失败日志保留。
- `logs/framework-final-source-restore.log`与`framework-final-pack-restore.log`：源码和实际导出PCK的40动作/24配置签名相同，源码保存的弹/状态/传播/盾/狼/图腾/双剑混合过程在PCK恢复后继续结果一致；`framework-old-state-restore.log`另以新PCK恢复优化前保留的原始fixture并继续相同结果，未改格式或规则签名。
- 通用kernel在15秒入口多次打印0错误但退出超时，`logs/framework-kernel.log`、`framework-kernel-console.log`和`framework-kernel-final.log`仍记失败；阶段计时副本`framework-kernel-timed.log`曾在相同15秒上限内完整退出、定位到套件总时间接近上限，没有延长上限或删除断言。最终相关独立检查已完成；不能把默认整合入口写成稳定通过。普通场景headless初探仍出现下述已知custom_samplers错误，不能因进程0退出记为通过；本轮容量和GUI证据均来自真实D3D12。

## 已知限制

- ACT当前为灰盒，正式后撤/侧移素材、密集弹幕与目标低配机/长局未验收；900人压力档仍过载。高频帧与旧20Hz基线的有限观察见专题研究，不把普通24人达标推成大规模已经支持。
- 普通主场景在Godot4.7.2 headless的着色器编译路径报`custom_samplers`错误；单独调用未改动的`Population.configure(1)`亦可复现，原件为`logs/headless-population-probe-20261114-150332-37276200.log`。本次Runner/工具短检查与真实D3D12普通启动、两次release图形测量通过；不把普通场景headless启动写成通过，也不据此改动正常渲染。
- 满帧率不等于满世界倍率；高倍速首先可能达到模拟吞吐上限。降低渲染帧率不能保证解除模拟瓶颈。
- 既有移动/探索过程曾出现帧时尖峰，不能据静止玩家的好窗宣称所有场景锁帧。
- 目标16GB/RTX3060整机、长局、极密战斗/拆建、远区LOD未由上述样本验证。

## 历史追溯

历轮版本、失败实验、方向/素材/导航/视野对照均可从[整理前基线](https://github.com/fewnfds/reol/blob/02958cc/docs/status/baseline.md)和本机logs追溯。更早调查见[archive](../archive/README.md)；旧报告里的“当前”“下一步”不产生任务。

# 当前构建与验证

更新：2026-11-17。能力归[FEATURES](features.md)，状态归属归[架构](../engineering/architecture.md)，阶段归[主计划](../plans/foundation-priorities.md)。本页保存当前证据，完整历史由Git追溯。

## 宗门共享基座实施（源码）

T01～T05主体能力、共同操作、持续活动、成长/体况及规范物资/最低授权已完成开工/收尾咨询、独立核查及相关整改。源码存档现format18/`user://sect-quicksave-v18.reol`及主体/操作/成长定义签名；下列独立P5包尚未重导，仍为format14，不能混用这两套文件。

| 本次检查 | 证据与边界 |
|---|---|
| T01整改与T02联动 | `being-operations-integration-20261117-004907-716660600.log` errors=0，未加入和已加入伙伴失能、真实在途中途存读/现场拒绝、临时帮工原自主态/换人续工及采木释放 |
| 共同操作 | `operations-final-20261117-005356-111842600.log` errors=0；不同实际消费者、规则变体执行、多费用/被控承诺、真实归因、隐藏观察和拒绝保原run |
| 原操作/正常GUI | `smoke-features-20261117-005435-887605400.log`、`operations-work-positions-20261117-005103-890278300.log`、`operations-livelihood-20261117-005103-873542500.log`通过；`operations-ui-20261117-005131-586521700.log` errors[]，真实菜单/取物/施工/换装，`logs/ui-smoke/npc-readonly.png`已观察 |
| 主体能力 | `being-capabilities-20261117-002747-554460200.log` errors=0；实际非人取放、代谢/环境、变更中断、源/签名/进行中资格、常驻召唤形态、槽复用和静物费用边界 |
| 原真实消费者 | `smoke-features-20261117-002709-782975100.log`、`spatial-capabilities-20261117-002757-148446100.log`、`smoke-equipment-20261117-003242-235510700.log`均errors=0；原社会/修行、临时召唤/光环/空间、装备/恢复 |
| 核心检查 | `smoke-kernel-20261117-003325-490823400.log` errors=0，保留15秒上限与原计时断言；修改前及修改后先前运行曾超时或失败于“220ms禁止画面轮询时应推进650ms”。只给错误信息补实际delta/序号/步耗时，未放宽条件；两次独立同负载探针均推进866ms。失败有间歇性，根因尚未定，不以最后一次通过掩盖 |
| 结构 | `check_structure.py --audit-code`：100文档、249 Godot源、0错误；不代表运行规模或界面体验 |

本项尚未引入目的/组织/生产新模型，也未测百人宗门闭环或图形性能；不能用以上检查替代最终交付。

T02核心同一断言再失败：`smoke-kernel-20261117-005155-384976400.log`实际delta450ms/最大单步51.5ms。随后独立100人4×同窗探针推进850/900/2000ms（220/220/500ms），`operations-indexed-thread-probe-20261117-005305-352651500.log`最大步8.7ms；查询按目标类型派生索引减少无关求值。单窗口/短探针不证明根因或精确性能改善，保留整组失败事实。

T03实施已接原活动结果/参与合同，开工/收尾双顾问均已核查并整改：`activities-final-contracts-20261117-012044-862321700.log` errors=0，覆盖部分实际转移/同刻目标删除、700+1300毫秒换人施工及中途恢复、未到场不记出勤/伙伴死亡单结果/忙方不交易/静止教师、成功线索反馈、播种与采木失败、共享引用及全局淘汰、放置与派工分别回执。`operations-activity-host-restore-20261117-011955-626273400.log` errors=0，含原恢复层拒未知/instant/work_source宿主；`smoke-features-20261117-011408-930854600.log` errors=0。首次教学检查因复用已手动停下的老师不再加入而失败，已显式释放手动状态开启独立教学场景，保留原学习/能力断言。

T03核心计时仍失败：`smoke-kernel-20261117-011955-638163500.log` delta633ms/最大步17.0ms（起初与其他短检查重叠），串行复核`smoke-kernel-20261117-012050-303606400.log` delta550ms/最大步21.2ms；不改650ms断言或15秒上限。独立同负载`activities-thread-probe-20261117-012143-163940800.log`在220/220/501ms中推进850/900/2000ms、最大步8.2ms，证实无显示轮询仍推进，但未定位整组慢因，不把它写成核心全通过或百人成品性能验收。

T03真实GUI：`activities-ui-20261117-012258-710270900.log` errors=[]，实际观察人物面板的新活动阶段与原二维布局，原取物/施工/换装正常；结构审计100文档/278源/0错误。源码format16；旧独立包仍为format14，未重导本轮成品。

T03收尾整改：`activities-finish-review-20261117-013113-8083000.log` errors=0，补忙玩家拒绝单方交易、伙伴手动接管不残留旧唤醒、末端腾空等待取消/换人/续完的1999+1毫秒守恒、在途伪开工/坏播种工时拒档、木愈与施工并存恢复、本人死亡原因和facts总遍历预算。`operations-activity-review-20261117-013154-461065600.log`、`positions-activity-review-20261117-013154-461059400.log`、`smoke-features-20261117-013137-298067100.log`均errors=0；结构审计100文档/278源/0错误。以上不覆盖后续成长、组织或百人供养。

T04实现检查：`growth-partial-recovery-restore-20261117-014340-304358000.log` errors=0，覆盖两类实际课程/理解与实践分离、实际修持/中断、亡师/售书/暂失能力保留、玩家NPC同工艺费用/不同实际工时、素质、真实冷伤/HP治疗与持续条件、安全休养及半途恢复、坏源状态/签名拒载。最初取消成本比较跨过了一秒代谢边界、休养夹具误把非阻挡木床当邻格使用，已在保留原断言下隔离代谢和改为真实床本格；失败日志保留，不算生产缺陷。

`operations-growth-consumers-20261117-014442-451297300.log`、`activities-growth-restore-20261117-014442-451317200.log`及接入后的`smoke-features-20261117-013935-163348700.log`均errors=0。`growth-ui-20261117-014626-527131700.log`真实D3D12 GUI errors=[]，已观察`logs/ui-smoke/npc-learning.png`中的中文理解/实践及NPC只读界面。双答收尾已完整核查并整改；未测百人供养/帧率成品。

T04最终接缝：`growth-finish-contracts-20261117-015837-440232500.log` errors=0，新增途中丢书的精确拒绝/无理解、合法在途失书可恢复、实践精通后授课仍1000ms、坏首次来源与缺永久前提拒载、源费用超容量拒绝。`operations-growth-finish-20261117-015849-436004600.log`和`activities-growth-finish-20261117-015849-436010300.log` errors=0。先前丢书新夹具错误期待failed，且study冗余required_items先给missing_items；已核清refused状态、消除重复书本规则，失败日志保留，不以改宽断言通过。

T05收尾反例：`custody-reviewed-boundaries-20261117-023008-215389600.log`、`custody-mixed-issue-guest-20261117-023259-345936300.log`均errors=0，覆盖公私混包/保权、受托工艺与退料、实际kill后的尸体物资和穿戴回收、历史保管关联、撤权退料不夹带私货、跨权花盆/铺地/盆内植物保护、多材料拆除、普通丢弃优先自有、明确领公料不混私产，以及坏批次/账实不符拒载。前次真实死亡反例揭露宿主仍要求静态tile，已沿实际身体定位修正；花盆反例原夹具缺种子先被missing_seed拒绝，补足材料后保留精确权限断言通过。不是以删除角色入口替代真实死亡验证。

T05原生GUI：`custody-ground-public-ui-20261117-023312-777394900.log` errors=0，实际表单从公库和无所属组织的公物地堆分别声明组织/用途领粮，背包显示自有/受托量；仅供搬运的药水和剑不能点击使用/装备。`logs/custody-ui/public-pickup.png`已实看。`smoke-features-20261117-023349-487309100.log`、`smoke-equipment-20261117-023349-482872500.log` errors=0，结构审计100文档/293源/0错误。核心`smoke-kernel-20261117-022459-101879300.log`仍失败于旧220ms计时断言(delta550ms/最大步19.1ms)，未放宽断言，未据此宣称全部绿灯或百人闭环交付。

追加收尾argon已核查，`custody-recovery-authority-20261117-023828-404264700.log` errors=0，增加回收者不能冒用他人旧装备受托、盆内植物/地板清理的共同Query与立即拒绝，合法责任/原物恢复保持；`activities-custody-final-20261117-023859-718132600.log` errors=0。追加hydrogen仍在途，未写成已核。转移上下文新增类型/用途/来源组织恢复校验。结构仍100文档/293源/0错误。

## 当前构建

T02收尾追加反例：`operations-variant-final-20261117-010710-927522700.log` errors=0，覆盖新运输定义/实际grain交付、半边伙伴档拒绝、直接中断伙伴自主唤醒、合法在途目标变化可恢复且到场拒绝。`capabilities-operation-final-20261117-010604-965599800.log`、`smoke-features-20261117-010409-895802400.log`均errors=0；真实`operations-ui-final-20261117-010557-460283800.log` errors=[]，已观察生成截图。结构审计100文档/276源/0错误；不将这些短检查宣称百人闭环或性能验收。

Godot 4.7.2 stable（ed1daf0bf），GDScript，Windows release，D3D12 Forward+，1280×720。正式入口`scenes/main.tscn`。当前为P5试玩版加作业位置、合同/碰撞修复与纯二维斜视显示；根目录[启动.cmd](../../启动.cmd)选3运行`build/windows/act-p5/reol-act.exe`＋同目录pck，选1为最新源码战斗、选2为普通世界。

| 项目 | 当前值 |
|---|---|
| exe SHA256 | `3d19ee4a764e8bb153bfa7f811f98e0dfb0139c9e0c8bc6b76b93d3ed09185bf` |
| PCK SHA256 | `33623c5a59c15cfcab014b795877ad8190f1d551f4ae2eeff325a91d04f7d83a` |
| 战斗规则签名 | `ed0a331b1a1ed0796a88f58ccad86c0677bbf29b327e0cb977a99ed567f53c8e` |
| 决策签名 | `9bb014cebdfdb4196146e2288f25e0cc274e364e34cac2f28d26597fcf06e5cd` |
| 内容 | 40动作、24配置、7套Policy；原生Resource/Inspector制作 |
| 存档 | reol-world-14；默认`user://act-p5-quicksave-v14.reol` |

来源贡献/控制聚合、决策反馈与设施登记更新布局，不迁移format13及更早开发档；原档及备份保留，不覆盖。exe是相同Godot模板，游戏变更主要在PCK；只核exe哈希不足以识别游戏版本。生成物/日志/本机咨询不入库。运行和制作入口归[usage](../engineering/tooling/usage.md)。

## 固定斜俯视与原生二维显示

用户反馈开启整屏形变后，竖直贴图边缘周期性横移1px。此前坐标反解/奇偶对齐检查通过，只能证明映射正确，不能证明画面质量合格。本轮已删除透视shader、世界离屏纹理/二次合成、设置滑条与F7入口，世界直接由原生Camera2D绘制；旧偏好的view项被忽略，重新保存设置时清除。保留二维斜视测试素材、分部排序、可见精灵alpha选择、主角遮挡淡化和统一坐标转换。原有迷雾mask仍用独立SubViewport。实现归[显示架构](../engineering/architecture.md#纯二维显示)，素材合同归[assets](../../assets/README.md)。

真实nearest、linear及2倍渲染对比见`logs/view-sampling/comparison.png`；最近邻的微斜线产生台阶，线性过滤柔化描边，超采样增加渲染面积也不能恢复原来的竖直几何。双顾问完整返回，原件留`.local/advisor/view-sampling-20261116/round-1/`，均建议按当前像素美术与制作范围撤除。采纳该取舍及原生过滤、stretch/震动输入、迷雾与测量RID复核建议；不把局部精灵缩放不可行或精确性能倍数当作普遍结论。普通非整数缩放的像素宽度差异不等同于本次横向台阶。

| 验证 | 本机证据 |
|---|---|
| 原生显示与实际像素 | `native-view-final-20261116-180521-627253700.log`，VIEW_UI_SMOKE errors=0；根视口直绘、分部/alpha选择、四种窗口含奇数尺寸、三档缩放、震动不改瞄准、真实光标/暂停平移/迷雾与旧偏好清理；离中心竖边逐行核对同一像素列，截图`logs/view-ui/native-*.png`已观察 |
| 移动与控制 | `native-movement_ui_smoke-20261116-180615-624780100.log`、`native-control_ui_smoke-20261116-180619-851367200.log`均errors=0；贴墙三连、单格通行、显示脚点、自由镜头瞄准与原生改键/窗口/UI缩放；`native-control-20261116-180625-803610600.log`另核F7不再保留占用 |
| 普通交互、施工、P4 | `native-ui_smoke-20261116-180624-469727800.log`、`native-work_positions_ui_smoke-20261116-180631-420477500.log`、`native-action_combinations_ui_smoke-20261116-180635-288353200.log`均errors=0；真键鼠选择、物资/续建、组合技能/召唤/光环/器物及文件恢复 |
| 当前独立包 | `export-20261116-180811-303649100.log`成功；`native-pack-restore-20261116-180852-82788600.log`从实际PCK恢复原源码的施工/来源状态/器物样本并推进，完整持久状态相同。World、身体/动作定义、format14和两项目录签名未改 |

最新release只测一个512人、1×、60FPS、两worker、迷雾、3秒预热＋5秒采样的framework-combat-v1窗口：`logs/native-final-512.json/.log/.cpu.json`及截图。目标机i5-13600KF/RTX3060、D3D12、1280×720；帧p99 16.836ms、采样步均8.038ms/p99 17.633ms、GPU均0.456ms/p99 1.803ms、主线程process均3.231ms、实速0.99991×，405次交付/57次命中、无脚本/引擎错误、零过载、木材守恒。已撤除额外世界合成pass，单窗结果只排查明显回归，不宣称精确提速或密弹容量；测量在提交前，JSON记录`8f1739f`加dirty，包哈希同本页当前构建。

## 贴墙移动与地面脚点修复

用户试玩报告贴墙平砍后卡死、家具南侧一格通道观感异常。本轮修正直接移动的校验/采用落点不一致，地图正边界格索引，以及显示脚点向下半格的偏移。仍使用原0.35/0.9半尺寸地面身体和完整建筑占地，没有人物逐节点物理、缩墙或第二调度器。静态物品/未开工蓝图先画，身体与实体景物共用脚点排序，成品屋顶最后画。细节见[移动精度](../engineering/simulation-pacing.md)、[素材坐标](../../assets/README.md#坐标占地与接地点)。

| 验证 | 本机证据 |
|---|---|
| 原问题与修复对照 | `movement-diagonal-before-20261116-124125-169412900.log`固定种子1500组产生55个非法终点；同探针修复后`movement-diagonal-fixed-20261116-124334-413780700.log`为0；原边界索引异常保留在`movement-before-valid-20261116-124107-314580600.log` |
| 移动专题 | `ground-fixed-movement-20261116-124540-641937400.log`，MOVEMENT_SMOKE errors=0；每次提交/分段合法、立即退开、微小重叠有限恢复/不穿整墙、两种身体的地图边缘、真实平砍与中途恢复、家具南侧一格通道 |
| 相关原检查 | `ground-fixed-{control,melee}-20261116-124540-*`、`smoke-{kernel,features}-20261116-124732-*`、`ground-work-positions-20261116-124732-755451800.log`、`ground-abilities-20261116-124732-756807400.log`均errors=0；没有扩大为全库矩阵 |
| 真实GUI | `ground-movement-order-ui-20261116-125005-886262700.log`，MOVEMENT_UI_SMOKE errors=0；原生鼠标斜向三连后键盘走过通道，检查GPU脚点与物品/蓝图/家具/身体顺序；截图`logs/movement-ui/`已观察。原普通UI和ACT GUI分别为`ground-ui-20261116-125034-68688100.log`、`ground-act_ui-20261116-125041-430977200.log`，均通过 |
| 最新成品 | `export-20261116-125117-982174300.log`成功；`ground-source-20261116-125137-316131600.log`和实际PCK的`ground-pack-20261116-125139-3370300.log`对复合施工/状态/器物候选恢复并推进，完整状态相同。format14及两项目录签名保持，旧存档逻辑坐标不迁移 |

该次二维基线release只测一个512人、1×、60FPS、两worker、迷雾、3秒预热＋5秒采样的framework-combat-v1窗口：`logs/ground-final-512.json/.log/.cpu.json`，全窗步均7.671ms、样本步p99 14.992ms、帧p99 16.692ms、实速1.00010×、405次交付/56次命中、无脚本/引擎错误、零过载、木材守恒。仍为i5-13600KF/RTX3060/D3D12/1280×720；这只排查本次修改的明显回归，不据单窗宣称提速或密弹极限。测量在提交前，JSON记录`77a8c5e`加dirty，包哈希为`59fd41ff843faf4c2eefeee5ffc89cac27b8cf186a4bb455db45c85cbfeaf8f5`。

顾问静态核查原件留`.local/advisor/movement-20261116/`；采纳已验证落点直接采用、标量边界、小范围旧重叠恢复和地面脚点对齐，补核地面物品层次。保留原净空查询和有限二分裁剪，没有为未测得的瓶颈重写解析扫掠器；World已在结构提交时校验/清理受影响旧路线，未采纳在每个人身上再存一份地形版本的建议。顾问对未附shader/交接入口的假设不列为已确认缺陷。首次新增家具测试误按单格估计多格桌子的范围，改用实际单格箱后验证，原失败日志保留。

## 本轮框架合同交付

两个并行审查的同一批发现已归并为一份问题账和主计划，9项确认缺陷与1项光环规则缺口已处理。当前代码沿原owner修正设施装配/删除、空间准入、执行反馈、缓冲就绪、候选采用、来源/原因、独立控制与标签压制、表现通知。详细规则只维护在[公共行动](../../design/systems/action_effect_framework.md)、[单位决策](../../design/systems/unit_decision_framework.md)及[空间与施工](../../design/systems/construction_and_space/places.md)，编号与关闭条件见[问题清单](issues.md)。

本轮双顾问Hydrogen/Argon完整返回，原件留`.local/advisor/framework-contracts-20261115/`，属于修复前附件的静态建议，不是本机运行验证；实际取舍归[研究](../../design/research/action_editor_references.md#9-来源贡献驱散与框架合同维护)。未引入第二调度器、通用事件广播、全图NPC知识或任意脚本沙盒。

| 验证 | 最终证据与范围 |
|---|---|
| 来源/贡献/控制 | `logs/effect-ownership-final-20261115-234915-210327900.log`，EFFECT_OWNERSHIP_SMOKE errors=0；普通驱散保留来源贡献、压制/恢复、同刻DOT、来源/受体死亡、缺槽/坏档均有实际反例 |
| 时序/器物 | `logs/contracts-action-boundaries-ready-20261115-234908-337605800.log`，ACTION_TIMING_SMOKE errors=0；真实命中缓冲等待CD及截止边界、NPC恢复、收集不提前提交、较早/同刻/较晚死亡和接回落点 |
| 决策反馈 | `logs/feedback-commitment-memory-20261115-233957-512526000.log`及`feedback-decisions-final-20261115-234111-700915300.log`均errors=0；不可达近目标换选、即时/异步原因、个人观察/期限、手动绕过及承诺/中途恢复 |
| 设施生命周期 | `logs/facility-cultivation-final-20261115-234911-622289300.log`，FACILITY_LIFECYCLE_SMOKE errors=0；开局/地区/施工箱空间、拆空登记/存读、纯放置、盆栽双向关系与12类坏档拒载 |
| 原核心和相关专题 | `contracts-final-kernel-20261115-234926-160767200.log`、`contracts-final-decisions-20261115-234926-162640100.log`、`contracts-final-action_domains-20261115-234926-162567700.log`、`contracts-final-framework-20261115-235011-628793800.log`、`contracts-final-control-20261115-235011-636685700.log`均errors=0；features/sight为`smoke-{features,sight}-20261115-235011-*`；原melee/abilities及`ownership-final-{action_reactions,action_spatial,action_combinations}_smoke-20261115-234704-*`亦通过 |
| 真实GUI与文件 | `contracts-final-outcome_ui-20261115-235048-517330700.log`、`contracts-final-ui_session-20261115-235053-22562700.log`、`contracts-final-work_positions_ui-20261115-235056-567990700.log`、`decisions-focus-fix-20261115-235519-661204700.log`均errors=0；覆盖真实破盾、取放反馈、施工续建、暂停文件恢复、策略与原生输入。截图沿原目录，已实际观察 |
| 完整组合GUI | `contracts-combinations-ui-complete-20261116-000145-883542000.log`，ACTION_COMBINATIONS_UI_SMOKE errors=0；血刃三连/怒气E/盾/C、远程控制/瞬移、分裂/传播/序列、狼/图腾/光环/双器物、4次文件恢复及陈旧选择。靶子由合法手动命令暂停自主政策，不改变HP/技能数值；NPC挑战另由P5 GUI核验 |
| 导出与源码等价 | `export-20261115-235941-258357300.log`成功；`contracts-source-fixture-20261115-235744-705363100.log`构造施工/来源状态/压制/stun/失败记忆/器物，Godot工具读取实际PCK后的`contracts-pack-restore-20261115-235953-524318200.log`恢复并推进至1601ms，完整持久状态一致，CONTRACTS_PACK_RESTORE errors=0 |

源码规则/专题保留15秒上限。完整组合GUI因原生窗口/弹出菜单同步及多次文件交付超过15秒，最终在单次20秒上限内完整通过；没有修改默认kernel限时。前期失败/超时日志保留：首次feature误用RefCounted模块为--script后改用正式suite；器物测试将连续几何终点误当整数毫秒落点后按实际时刻修正；GUI先确认原生窗口焦点与popup Window ID，再保持原生输入/实际结果断言。旧P4靶子任其执行P5三连会中断范例演示，故通过已有手动交接隔离技能检查，不改生产AI。失败不算作通过。

该次合同交付成品只测一次512人、1×、60FPS、3秒预热＋5秒采样，`logs/contracts-final-512.json/.log/.cpu.json`记录：全窗步均7.961ms、样本步p99 14.760ms、帧p99 16.739ms、实速0.99991×，405次交付/57次命中，零过载、木材守恒、无脚本/引擎错误；峰值14弹/4状态。i5-13600KF/RTX3060、D3D12/1280×720、迷雾、两worker，仍为同World的framework-combat-v1。开局箱碰撞及失败选项修正改变了工作负载，不作纯算法提速百分比；这不证明长局或极密弹上限。测量在提交前进行，JSON仍记旧HEAD加dirty，当时包的PCK哈希为`afc3dee9db3947865f96db4e247229f2fffdb80a469a081c5b332deb707694f7`。

结构/链接审计与最终差异空白检查通过，新脚本UID已导入；生成物不入库。本轮没有仍未处理的上述确认缺陷，未检验的主观手感、正式音画、完整平衡和密弹长局仍保留为产品验证范围。

## 前次作业位置与审查交付（历史）

作业位置的配置、旋转和施工状态合同见[空间与施工](../../design/systems/construction_and_space/places.md#作业位置与在制外观)。本格、完整占地四邻和指定工位共用接近/到场校验；灶台已有单侧烹饪工位。已开工蓝图取得实体阻挡，中断、等待、存读与续建沿原行动和库存。16种模块在现有静物批次中拼接施工架，未新增逐对象节点或第二份占地原状态。

审查结合本地源码/隔离反例及世界、战斗、会话的双顾问意见；作业位置另由顾问与独立代理复核。顾问指出的多人排队施工失效已实测修复，另修复未开工多格蓝图的大身体角点站位遗漏。没有把静态建议直接当作事实。当时遗留的确认问题已纳入本轮合同整改并逐项关闭，完整触发与当前处理归[问题清单](issues.md)；历史检查不替代当前验证。

| 本轮修复范围 | 结果 |
|---|---|
| 世界/生活 | 战术接管清理旧路线游标，普通世界正常存档恢复；成熟树检查实际身体半径；生活跳过已知满箱/未成熟植物；新手动指令清旧协作，忙碌协助不落入无关工作；需求不抢断单次手动工作或社会伙伴；自建蓝图保留制作者记忆；定身不妨碍已到位操作 |
| 战斗机制 | 光环退出不漏删多个状态；大弹体/器物不漏静态受体；反击弹不排除攻击者；追踪跳过已穿过目标；嵌套状态反应在同一有界因果波内处理；零前摇直接交付进入正确接触阶段；失视放弃后续序列，保留已承诺动作 |
| 界面/会话 | 空菜单不锁输入、背包快捷键可关闭、平移可退出跟随、窄屏抽屉可见；目标可见性与是否已查看详情分开；切换选择/epoch清旧面板；地板可拆；菜单读档恢复进入前暂停状态 |
| 作业与施工 | 四向工位/盆栽宿主/大身体净空、占地等待不耗工时、开工阻挡不提前围合、中断和恢复不重复材料/劳动；多人施工不重新开启成品或污染正常存档 |

| 验证 | 本机证据 |
|---|---|
| 最终核心/作业 | `smoke-kernel-20261115-232302-371277100.log`，KERNEL_SMOKE errors=0；`work-positions-final-20261115-232158-933296500.log`，WORK_POSITIONS_SMOKE errors=0，含等待中/施工中恢复、多人竞争、大身体角点和寻路预算反例 |
| 决策/生活/跨域 | `work-final-decisions-20261115-231921-240994300.log`、`work-livelihood-20261115-230803-580151600.log`、`work-domains-20261115-231056-777000200.log`均完整退出、errors=0；features为`smoke-features-20261115-230803-591821900.log` |
| 相关战斗与框架 | `work-final-action_reactions-20261115-231750-316838200.log`、`work-final-action_spatial-20261115-231756-680192600.log`、`work-final-action_resources-20261115-231802-16873100.log`及同前缀的control/framework/action_foundation检查，均errors=0；未自动串成长局矩阵 |
| 真实GUI/磁盘 | `work-final-work_positions-ui-20261115-231829-121538900.log`、`work-final-ui_session-ui-20261115-231833-145389200.log`、`work-final-decisions-ui-20261115-231836-144608100.log`、`work-final-ui-ui-20261115-231843-446489900.log`均通过；施工架/金色工位/完成后详情截图`logs/work-positions-ui/`已实际观察 |
| 导出与恢复 | `export-20261115-232258-177923700.log`完成；`work-source-fixture-20261115-232321-375074500.log`从施工中生成候选，`work-pack-restore-20261115-232322-645719500.log`以Godot工具读取实际PCK、恢复并推进，完整持久状态与源码一致，WORK_PACK_RESTORE errors=0；release真实运行另见下方短窗 |
| 结构 | `check_structure.py --audit-code`核94份当前文档、229个Godot源文件、15个注册类，0错误；新脚本UID已导入，最终diff无空白错误 |

源包恢复探针先误用不允许路径覆盖的release模板`--main-pack`，明确失败并保留`work-pack-restore-20261115-232118-182733700.log`；后改为Godot工具显式载入实际PCK，不把失败算通过。新增竞争测试曾有错误变量/属性名，修正fixture后再通过，失败日志保留。

本轮成品只测一个512人、1×、60FPS限帧、3秒预热＋5秒采样窗口，条件沿P5的`framework-combat-v1`、迷雾、RTX3060/D3D12/1280×720、两worker。`logs/work-final-512.json/.log/.cpu.json`记录：全窗步均7.993ms、步p99 15.903ms、帧p99 16.702ms、实速0.9999×，406次交付/57次命中，零过载、无脚本/引擎错误、木材守恒。峰值14弹/4状态；没有密弹极限或纯算法提速结论。测量在提交前完成，JSON的Git字段为旧HEAD＋dirty，包哈希与上表一致。

## P5实施与验证

以下为原P5交付时的历史有效检查；当前包的更新证据在上节。

共同Decisions接入原生活/工作、战斗、逃离及临时身体跟随；策略模板和个体参数/任务分开，保存待唤醒与持续自主输入。原host/run提交实际后果；发现威胁不先停工，手动明确交接，有限序列允许原合法取消。轻敌闪步三连、重敌承诺/收招和射手拉距共用执行器。

两轮双顾问均完整返回，原件在`.local/advisor/p5-implementation-20261115/stage-1/`与`stage-2/`；代码取舍归[研究](../../design/research/action_editor_references.md#84-p5实施复核)。按实际反例修复退避早醒、旧run/序列、buffer失效、手动/合作抢权、目标消失失醒、需求原因合并丢失、远处旧设施线索、移动/跟随交接及恢复校验。顾问不替代运行证据。

| 验证 | 结果与本机证据 |
|---|---|
| P5规则/恢复 | `p5-decisions-final-20261115-214152-62338800.log`，约8秒完整退出，DECISIONS_SMOKE errors=0。覆盖策略隔离、采集—威胁—重选、合法取消、序列中途恢复/失败/替换、手动、需求/失效目标、陈旧认识、buffer/跟随、坏候选拒载，详见[tests](../../tests/README.md) |
| 原核心/相关专题 | `smoke-kernel-20261115-214225-204690400.log`，KERNEL_SMOKE errors=0；features/sight/control分别为`smoke-features-20261115-214225-206210700.log`、`smoke-sight-20261115-214254-296888900.log`、`p5-control-20261115-214225-187397700.log`，均完整退出。ACT为`p5-act-20261115-213633-353163200.log` |
| P4相关执行 | MELEE、SPATIAL、ABILITIES最终检查均完整退出、errors=0：`p5-melee-final-20261115-214530-944672800.log`、`p5-spatial-final-20261115-214530-984891100.log`、`p5-abilities-final-20261115-214530-944118800.log`。未把其他无关专题自动串成长矩阵 |
| P5真实GUI | `p5-decisions-ui-final-20261115-214324-197734800.log`，DECISIONS_UI_SMOKE errors=0。原生练习切换、三类敌人出招、交战中实际文件存读、任务/参数保留、F12 decisions和读取后闪步/移动/出招通过；截图`logs/decisions-ui/`已观察 |
| 原ACT/生活GUI | `p5-act-ui-final-20261115-213736-509279300.log`，ACT_UI_SMOKE errors=0；`p5-life-ui-20261115-213038-470796600.log`，UI_SMOKE errors为空，覆盖普通取放、施工/取消、换装/卸下、人物/背包/迷雾界面；截图沿原目录 |
| 原生Inspector | `p5-authoring-20261115-213023-105014300.log`，COMBAT_AUTHORING_EDITOR errors=0。Policy/Library/规则引用及评分范例可编辑，坏距离字段提示有效；`logs/decisions-authoring-editor.png`已观察。第三方插件退出连接提示不当作游戏错误 |
| 导出包恢复 | `export-20261115-214413-827156200.log`完成；`p5-source-fixture-20261115-214346-408258000.log`生成同一P5混战/在途fixture，源码与PCK分别恢复并推进到1601ms，`p5-pack-restore-final-20261115-214418-862917500.log`完整持久状态一致，P5_PACK_RESTORE errors=0 |
| 结构/工具 | `check_structure.py --audit-code`为93份当前文档、224个Godot源文件、15个注册类，0错误；Python tool_smoke通过。新Resource与UID已导入；最终提交前再核diff和结构 |

过程中的失败保留，未作为通过计数：首次metrics重名/同步work交接见2105段；早期新测试的父helper清接触及只看瞬时移动字段见2107段，随后修正fixture/观察合同。原生Inspector曾等待后台窗口不产生的`frame_post_draw`而超时，日志`p5-authoring-20261115-212357-71911400.log`、212602与212714段；改为显式force_draw后完整退出，未放宽时间上限。

GUI失败`p5-decisions-ui-20261115-212318-460585800.log`显示攻击实际启动后立刻被打断；`p5-decisions-ui-final-20261115-214254-283248300.log`是在硬直中请求被合法拒绝。测试改为核启动事实并先闪步拉开，未修改战斗准入迁就测试。原ACT GUI在`p5-act-ui-20261115-213719-761847800.log`将合法buffer误当立即启动，改为等待真实启动/CD，后续通过。最终陈旧线索测试隔离原人物已知候选并在选择边界核意图，后续不可达由原导航反馈，不能将地图寻路失败说成查询隐藏库存。

首次源码/PCK探针误用不存在的`World.Scenarios`已修正；之后全状态对比差异仅在恢复会重建的`environment.revision`和`perception.next_ms`。最终比较两端分别恢复同一候选后的完整状态，不以源码未恢复世界与恢复世界的缓存版本差异冒充游戏结果不同；原失败日志`p5-source-fixture-20261115-213806-424182500.log`、`p5-pack-restore-20261115-213825-479112000.log`及213841段保留。

## P5相关性能短窗

i5-13600KF/RTX3060，D3D12，1280×720，玩家迷雾，1×，60FPS限帧，3秒预热＋5秒采样。仍为同World的持续星焰动作/耐久三敌与后台生活；P5敌人/生活选择已改变，**不与旧P4窗直接作纯算法提速百分比**。24人串行、512人两页/两worker，真实图形串行测量。

| 人数 | 全窗步均 | 步p99 | 帧p99 | 实际世界流速 | 交付/命中 |
|---|---|---|---|---|---|
| 24 | 1.174ms | 3.139ms | 16.878ms | 1.0001× | 23/69 |
| 512 | 8.517ms | 14.097ms | 16.867ms | 1.0001× | 409/59 |

证据`logs/p5-final-{24,512}.json/.log/.cpu.json/.png`。两窗无脚本/引擎错误、无死亡、木料守恒、零过载；5秒内协调求值324/1528次，累计46.668/414.056ms。它包含生活候选等嵌套成本，不是单个规则解释器耗时。早一版P5的`logs/p5-release-*`因后续因果修复重导出后复测，各人数共两次，未挑最佳窗。

这些短窗说明当前选定负载仍有可玩余量，不证明密弹极限、所有倍率、长局、主观手感或目标16GB整机。世界512²、近场60Hz和现有慢域精度保持，没有为P5降世界精度或新增LOD。

## 基础框架优化交付

以下为整理前`fe4fdcf`优化的有效短窗，不是本轮重新测量。实现与原生/自研取舍见[研究](../../design/research/large_simulation_optimization.md#godot原生能力与本轮实施取舍)。地图512²、60Hz和现有生活/环境/植物精度保持；索引仍完整重建，没有每格人数截断、流场或LOD。

同i5-13600KF/RTX3060/D3D12/1280×720/迷雾/1×60FPS限帧，3秒预热＋5秒采样。`framework-combat-v1`为同World中的星焰连发/焰种/控制与耐久三敌、普通后台生活；24人一页串行，512人两页自动两worker。前后每档各一次最终窗，中间更好值不取代最终值。

| 人数 | 模拟步均：前→最终 | 步p99：前→最终 | 帧p99：前→最终 | 世界流速：前→最终 |
|---|---|---|---|---|
| 24 | 1.161→0.752ms | 5.394→2.236ms | 16.742→16.709ms | 1.0001×→1.0001× |
| 512 | 9.182→8.341ms | 15.884→14.533ms | 16.859→16.720ms | 1.0001×→0.9967× |

证据为`logs/framework-{before,final}-{24,512}.json/.log/.cpu.json/.png`。步均使用全窗累计差，分位数用样本窗，不强行统一；各窗无错误、资源守恒、零过载。512人索引累计787.874→658.091ms，full发布301→62，但总发布194.554→200.232ms，**没有512人总发布成本下降结论**。主线程process均24人为0.864→0.642ms，512人为3.060→2.586ms。

步均约降35%/9%仅是这些短窗观察，不保证所有玩法。中间512人窗7.94ms、最终8.34ms，说明单窗波动；峰值仅观察到10弹/4状态，不证明密弹容量或设备延迟。命中/交付窗口端点有差异，规则等价另验。`logs/framework-final-equivalence.log`对24/512人各360个固定16/17ms步核对逐步outcomes/motion/move_scales与最终持久状态一致。

实际P4普通24人血刃无操作短窗`logs/framework-final-normal.json`约0.9999×、帧p99 16.812ms、步均0.503ms、主线程process均0.524ms、零过载。不能据此宣称持续施法/全部场景锁帧。

## 历史数值与限制

[performance.json](performance.json)保留02958cc、旧20Hz的capacity-v1样本，供同负载/同条件对照，不被ACT或本轮短窗覆盖。旧900人ACT高密交战曾约0.748×，属于当时特定版本/负载，不当作当前容量断言。更早各阶段构建/失败与日志路径见[整理前基线](https://github.com/fewnfds/reol/blob/bd1971c/docs/status/baseline.md)。

- 正式后撤/侧移/三连素材、主观混音、完整敌人花型、成长平衡、长局、极密弹幕和目标16GB/RTX3060整机没有由这些工程检查验收。
- 普通主场景在Godot 4.7.2 headless的Population着色器路径仍有已复现的`custom_samplers`错误；规则脚本与真实D3D12运行正常。本轮不把普通场景headless启动算通过，也不为此改动正常渲染。
- 满帧率不等于世界倍率达成，历史好窗不覆盖移动/探索/拆建尖峰。新增功能沿开发循环做相关检查，有对应瓶颈才再测性能。

# 当前构建与验证

更新：2026-11-17。能力归[FEATURES](features.md)，状态归属归[架构](../engineering/architecture.md)，阶段归[主计划](../plans/foundation-priorities.md)。本页保存当前证据，完整历史由Git追溯。

## 跨步调度与后台规划

2026-11-17，沿原World/Runner实施，日常纯选择进入有限后台任务、普通观察分片，保一个事实写入者与关键提交顺序。实现合同归[执行方式](../engineering/execution-batches.md#跨步服务与后台提案)，阶段咨询/取舍归[主计划](../plans/foundation-priorities.md#调度与计算依赖审查)。下节保留修前诊断，不能将其“未实施”状态沿用为当前停点。

同机真实release对照：i5-13600KF、RTX3060、D3D12、1280×720、60FPS，3秒运行预热＋10秒采样，原生F9加载同一2760000ms普通百人存档，固定镜头/迷雾，100人全活；用户原档在finally恢复。不是编辑器/headless性能，也不是合成战斗压力场景。

| 条件 | 步均ms | 步p99 / 最大ms | 画面p99 / 最大ms | 实际世界倍率 | 交付 / 移动格 / 活动均值 |
|---|---|---|---|---|---|
| 修前宗门包 | 6.538 | 29.365 / 39.685 | 16.758 / 16.989 | 1.00007× | 3 / 1185.62 / 0.25849 |
| 当前包，默认有限后台 | 4.419 | 8.107 / 12.479 | 16.712 / 16.756 | 0.99997× | 2 / 1173.69 / 0.26231 |
| 同核心workers0串行对照，小修前 | 5.908 | 16.484 / 23.381 | 16.963 / 17.073 | 0.99997× | 3 / 1244.68 / 0.27666 |

原始JSON为`logs/scheduling-before-package-reviewed-mature.json`、`scheduling-final-package-async-reviewed-final-mature.json`、`scheduling-final-package-serial-reviewed-mature.json`。串行对照早于最后的重复提案/元数据/观察前驱及取消生命周期修订，纯选择核心相同；本机另保中间包数据，不用较好的一窗替换最终包。不同计算完成时间会改变后续选择，本表是相同起点/条件的实际成本及活动量比较，不是锁步工作量完全相同或固定硬件外收益保证。

当前窗完成取水1、休养7，修前1/6；移动及活动均值相近，未靠NPC停工/减员降低耗时。默认后台从本次加载后累计（含预热）启动340、完成339，真实worker ID不等于身体页worker统计；100人一页的`workers=0`字段只表示身体页无并行，不代表没有后台规划。普通完整扫描159次，末ready54/运行1，最大等待3467世界毫秒、最长服务片3510µs；软服务允许秒级等待，单片可超约3ms预算，不承诺50ms或硬截止。串行模式没有墙钟截断，不能仅比任务数推断后台失败。

最终包原生F5保存→退出→新进程F9读取通过：`logs/scheduling-final-package-async-reviewed-{save,load}-20261117-{191842,191857}.log`，两窗世界约1×、100人全活，原用户save/bak/tmp恢复。无源码运行目录仅复制exe/pck；实际导出日志`logs/export-20261117-191817-455466900.log`。当前路径仍是启动菜单3的`build/windows/sect-foundation/reol-sect.exe`＋同目录pck；exe SHA256 `3d19ee4a764e8bb153bfa7f811f98e0dfb0139c9e0c8bc6b76b93d3ed09185bf`，pck `2251d684897b028f3e144c86437db892841746a41da015fe204107e8749d7fd2`。生成包不入Git。

真实原生Game观察：`logs/scheduling-post-review-ui-20261117-192027-281407500.log`从同成熟检查点选38号，活动卡片显示“修行中·青灵竹#657”和12%真进度，截图`logs/scheduling-reviewed-selected-npc.png`已实际查看。12墙钟秒的采用/显示推进记录`logs/scheduling-reviewed-ui-timeline.json`：718次新Frame采用，最大观察间隔33.335ms；1435次render_ms增长，最大41.726ms（含最初启动等待），两者超过60ms均0。这里量的是主线程观察，不是每次owner发布完整时序，也不证明任意长局零卡顿。

最终相关短检查：`logs/scheduling-post-review-final-20261117-191729-132503100.log`约7.6秒、`smoke-kernel-20261117-191432-451881900.log`约7.9秒，均errors=0且保原15秒上限/650ms线程断言。取消修订后的`logs/scheduling-reviewed-decisions-20261117-191803-30305300.log`及`scheduling-reviewed-act-20261117-191813-41110900.log`通过。生活食物/边界/失败、knowledge_schedule/knowledge_boundaries相关检查也通过，日志为`scheduling-{food-final,agency-boundaries-final,agency-failures-final,knowledge-calendar,knowledge-boundaries}-20261117-*`；未据此宣布全库全绿。结构核100文档/417源/0错误。

kernel原预约缺key、cook/eat断言已在未改d127ec6隔离基线独立复现（`logs/scheduling-baseline-causality-cooking-20261117-184613-189383700.log`），随后按真实作业位置/劳动截止校正；同拍收获夹具隔离无关自主，核原预约释放与期末死亡顺序。512串/并行段只给其中一个courier现场认识及从现有世界转出的4木料，仍核真实交付/净空/守恒；不能将它描述为512人自治吞吐达标。规则夹具用有限service完成提案，不把“prepare一调用立即有选择”恢复成运行合同。

明确未解决的规模边界：512人全陌生development冷启动6模拟秒探针`logs/scheduling-observe-first-work-20261117-185240-314967700.log`仍0交付、ready841/最大等待6000ms（162规划、4完整扫描、32cargo，守恒成立）。本轮未追加其吞吐硬指标或长测；植物/整秒环境/部分路径与快照仍同步，后续应按实际热点处理。此前abilities聚合超时和其他旧意愿前提失败未重验收，不由本轮局部通过覆盖。

开工、三次阶段交流及最终review/整改复审双模型完整回答均已独立核查，原件在本机`.local/advisor/scheduling-implementation-20261117/`。最后两份答复未提出剩余必修项，要求的原act/decisions与重导复验均已完成；顾问原答不入库，也不作为本机运行证据。

最终review实际补出两项反例：`scheduling-arrival-counterexample-20261117-191208-111247500.log`复现未完串行提案到达后留下孤儿job；现统一取消出口成对退役任务/预留，串行及信号量挂起后台两模式均恢复观察/真实进食。`scheduling-ignore-stable-goals-counterexample-20261117-191641-447133600.log`仅撤保债逻辑后复现受支持ignore策略丢失忙host的需求review；修后实际吃饭。该夹具只替换合法策略数据，当前stock resident自卫；初期误传不可用response个体参数的失败不当缺陷证据。未采顾问“所有尖峰已消除/输出完全等价”的扩大结论，不将低端线程抢占的猜测当作本机事实。


## 调度与计算依赖审查

本节是实施前的历史诊断：2026-11-17只读核查main `97c60b5`，当时未改生产代码/存档/导出包。用户要求判断周期轮询与“必须算完才发布”的结构缺口。当前已有50ms分层/配额和事件唤醒，但日常到期评价、完整普通观察、新路径等仍在同步调用链，演进及当前状态见[实施取舍](../plans/foundation-priorities.md#调度与计算依赖审查)。上一轮成熟GUI短窗通过只覆盖该窗口的集中观察削峰，不能据此断言其他同步慢域已解决。

本次无画面、workers=0、正常100人，新开及真实2760000ms检查点各推进12模拟秒（720个60Hz外步），用现有owner微秒累计计数器作差，未覆盖生产方法：

| 样本 | 最慢一步ms | 该步决策/观察/环境ms | 该步实际生活选择次数 |
|---|---|---|---|
| 新开局 | 118.532 | 95.484 / 0 / 0 | 9 |
| 成熟检查点 | 127.514 | 123.819 / 2.898 / 0 | 4 |

原件`logs/scheduling-audit-{fresh,mature}.json`、`scheduling-audit-fresh-20261117-173456-571228900.log`、`scheduling-audit-mature-20261117-173407-328718300.log`。完整12秒分别834/478次Decisions evaluation与788/475次生活选择，不是每人每帧重建计划；未到期wake表成员不能算作正在重规划。最慢样本不是整秒环境峰，决策是本次新抓到的串行热点；不能把它倒推成前两个release孤立长帧的唯一成因。

为收窄原因，成熟同起点6模拟秒，以继承后调用super的诊断包装计数，结果`logs/scheduling-audit-life-{detail,preempt}.json`与`scheduling-audit-life-detail-20261117-173651-114313700.log`、`scheduling-audit-life-preempt-20261117-173819-171907900.log`。两次均236次choose，其中60次唤醒原因是`space_needed`，让位wake请求82次并由原actor槽合并；现有小范围刺激进入完整生活选择。第二次236次`should_preempt`中234次开始时原gate已空，仍构造认识/自身视图并做抢占评价，空host这部分累计730.699ms；证明重复计算存在，不能直接当作成品优化收益。已有每人128查询/1000ms预算是计数，不是可抢占的墙钟时间片。

同6秒237次institution_review预约；源码`Decisions.wake`对延迟的该类预约也立即置`life_dirty`，因此未来审查可提前污染其他唤醒的抢占判断。未单独统计每次dirty的全部因果，不能把234次全部归给同一来源。新开/成熟12秒各仅12次环境更新，最大5.074/4.957ms；当前探针不支持“整秒环境是主热点”的推断，也不代表可永远忽略其扩展成本。

成熟样本另一步at=2770033ms总耗时66.327ms，其中`observe_usec=62.616ms`、一次观察、`decisions_usec=0.357ms`、无生活选择/环境更新。`effects_usec=65.643ms`是World完成提交区间的外层计时，包含嵌套观察，不是纯粒子特效且不能与观察相加。源码`world.gd`的EXPLORE抵达直接完整observe/think，`service_positions.gd`让位也使用该模式；证实普通pulse配额未覆盖所有完整观察入口，但本探针未记录这次抵达的actor/意图，不能把该62.616ms全部归为让位。认识条数已有128上限，不能将成熟局成本写成无限记忆增长。

这些是headless/source定点诊断；独立release前一轮同成熟短窗模拟步最大37.853ms、实际约1倍，条件不同，不能把118/128ms称为当前成品每帧耗时。两次细计时绝对成本也有差异，不推算固定加速倍数；本轮未重跑图形倍率/长局矩阵。新诊断、源码选段和咨询输入留`.local/scheduling-audit-20261117/`及`.local/advisor/scheduling-audit-20261117/`。

诊断时顾问两轮各询双模型：首轮hydrogen完整、argon返回503；第二轮两份完整，三份完整原答均已审阅。公开来源归[主计划](../plans/foundation-priorities.md#公开参考)；实施阶段咨询与当前采用/拒绝另见本页顶部和主计划，原答不是代码/性能事实的替代。

## 宗门试玩诊断

本节保存修前诊断，修复结果见[下一节](#宗门试玩修复)，U01～U06状态归[问题清单](issues.md#宗门试玩整改)。基线为main `51515226892de3951244add989a304cb6a545452`，Godot 4.7.2。用户入口为选3当前宗门release，后续代码定点复现使用同main的正常百人装配及真实`logs/t13-mature-checkpoint.bin`（2760000ms）。未写入用户默认存档/偏好；诊断文件、脚本与顾问原件在忽略目录，不能把下述定点探针当成用户原会话完整复现。

`logs/playtest-review-cases.json`与`playtest-review-events-and-crowding-verified-20261117-153533-870194100.log`：正常100人开局，仅把请求者移到对象旁以隔离路径因素，目标仍保留实际自主行为。向2号请教炊事50ms返回`teacher_does_not_know`，向已掌握并公开炊事的8号50ms返回`not_interested`，两者UI日志均为“行动：条件未满足”。成功从餐箱进食在1000ms产生`status_added`和`action_ended(reason=completed)`，也各误报一次“行动：条件未满足”，随后才显示“进食完成”。这证实合法拒绝与成功事件假失败并存，不推断用户当时全部失败均是同一原因。

同成熟快照中，72/76/89/90/98号在(129.5,162.5)，邻近公告案1759(129.5,163.5)，均无活动/动作/预约且地形可站；另有1201、2317公告案旁的同点闲置，以及10号与正在practice的38号同点。`logs/playtest-review-idle-timeline.json`、`playtest-review-idle-timeline-20261117-154525-105341900.log`以原类继续12模拟秒：部分角色继续赶路/休养，72/76号在原点又读公告后闲置，10/49/99号本窗没有活动。不能据静止快照认定全员永久卡死；同一服务终点和结束后缺少让位是真实缺口。

`logs/playtest-review-ui-and-presentation-gap-final-20261117-153705-619875100.log`正常退出0：真实Game加载隔离诊断存档，选中灵竹657处正在practice的38号。raw有phase/operation/target/due_ms，普通SubjectView仍有活动，选择卡片只显示外观/位置/伪填`视距0.0`，作业进度控件隐藏。截图`logs/playtest-review-selected-npc.png`已实看。初次探针错误调用不存在的`runner.stop()`，失败日志保留；改为原`runner.close()`后完成，未改生产逻辑。

性能使用原60Hz外步及既有微秒计数器的单步增量，无业务改动；headless源码各跑12模拟秒，源类/方法计时类分开。下表为实际单步样本，不将不同运行条件的绝对耗时直接比为优化比例：

| 样本 | 世界时刻 | 本步耗时 / 观察耗时 | 事实 |
|---|---|---|---|
| 成熟、原始类 | 2772000ms | 444.654 / 440.658ms | 29次观察，环境3.002ms；不是覆盖方法的探针单独制造尖峰 |
| 成熟、轻量方法计时 | 2772000ms | 407.828 / 404.182ms | 2024次store，494次新目标满容量写入；store合计279.811ms，保护集494次合计93.295ms（嵌套成本不可相加） |
| 全新开局、轻量方法计时 | 6000 / 11000ms | 245.103 / 306.684ms；观察240.935 / 302.154ms | 分别67/79次观察；全12秒无新目标满容量写入，量化扎堆先于淘汰压力成立 |

原件`logs/playtest-review-perf-{mature-plain,mature,fresh}.json`，日志分别为`playtest-review-mature-original-counters-20261117-153747-532831200.log`、`playtest-review-mature-timeline-20261117-153318-105338100.log`、`playtest-review-fresh-timeline-20261117-153806-205502200.log`。非整秒也有独立规划长尾；不能宣称消除观察尖峰就解决所有成本，亦无GPU或“GDScript GC停止世界”的定位证据。

上述实际Game的12墙钟秒GUI窗另记录`logs/playtest-review-ui-timeline.json`：采到617次发布，11次发布间隔>60ms、最大166.655ms；render_ms实际增长有10次间隔>60ms、最大149.995ms。该源码窗口约120FPS，区别于既有60FPS限制的release样本，不能把headless/GUI/source/release数字混作同一基线。规律性停顿与整秒观察相符，主线程持续重绘并不能保证人物连续移动。

此前release成熟短窗的约60FPS、平均0.9967×、simstep p99 68.593ms/最大130.978ms只证明所测平均吞吐与重绘，不证明没有周期停顿。T12c/T13既有GUI/三日供养通过也不覆盖此次误攻、卡片活动、终结日志和静止重叠体验。原证据保留，适用范围按此收紧。

## 宗门试玩修复

2026-11-17，基于main `35a0053`实施R01～R05，正常百人和能力练习仍共用原World/Combat。改动按原行动、认识、空间及展示owner落地，无新执行后端/持久队列；格式保持32。普通宗门默认/读档回日常，WASD两态共用，生活操作回日常；切态/工具/失焦/加载清未提交连续输入，已成立招式照原承诺完成。选中NPC显示可见活动/对象及真实连续作业进度，公开任职沿原社会视图，不读取私人目的。终结历史提交当时保存对象/双方角色/结果与原因，后续改名或近期结果淘汰仍可读；未知内部事件不再冒充失败。

服务站位由现有身体和在途目标派生；初次作业与采木抵达重验，被后来者占住时改走同目标其他合法位置。全满明确`target_busy`沿原拒绝反馈/退避重试，几何封死仍`no_operation_place`，没有新增永久队列。散落物品并发取放与人物参与合同保留。非玩家/非手动/无活动的自主闲人可实际让出服务位，普通随机探索避开工位；跨格边缘按身体距离判阻位，施工完整占地也可唤醒闲人，人物接触点核身体可站与路径可达。让位只搜附近四圈直达空点，封闭密室可能找不到，不宣称全员运动碰撞、绕障疏散或编队。

普通观察从整秒批量改为50ms边界的确定性due/身份配额，百人每边界最多2人；全部存活身体可惰性登记，不靠seed副作用。去掉规划入口同步整场观察，保到达/接触/结果即时反馈。满128先判准入再revision/复制；单次观察共享派生保护集，宿主占用者消失、候选拒入及淘汰依赖均失效，仍保本人已取得的个人床/职责与传承线索。

相关规则检查均errors=0：`logs/playtest-final-{control_smoke,subject_view_smoke,personal_places_smoke}-20261117-171418-*.log`；`playtest-reviewed-activities-20261117-172341-35994000.log`、`playtest-reviewed-work-positions-20261117-172341-25266900.log`、`playtest-institution_access_smoke-review-20261117-170115-388966900.log`、`playtest-knowledge_smoke-boundary-20261117-170244-977160000.log`、`playtest-knowledge_boundaries_smoke-boundary-20261117-170244-980733100.log`、`playtest-clearance-contact-complete-20261117-172101-945815100.log`、`playtest-schedule-dependencies-20261117-170443-439580600.log`。权限检查夹具原先把两名手动工人放在同一单侧灶位，现明确让离任手动人腾空，权限/公料/劳动接续断言未削弱；认识反例隔离其明确时间证据与新增独立观察机会，来源/传播/结果断言未放宽。

真实GUI `playtest-ui-alias-final-20261117-171806-389429500.log`覆盖正常100人默认日常、鼠标选择/WASD/右键菜单、Tab出招/持键切回、附近交互、工具/失焦、会话屏障及实际文件存读，含旧`continue_build`适配入口也回日常；`playtest-teaching-ui-started-20261117-170922-241210700.log`核NPC自愿邀课、玩家主动参加、实际开课双方角色/进度、暂停保存与恢复完成；均errors=0。截图`logs/sect-playtest-ui/`、`logs/teaching-ui/shared-lesson.png`已观察。成熟检查点真实Game选38号，卡片“修行中 · 青灵竹 #657”与真进度、无伪视距，截图`logs/playtest-final-reviewed-selected-npc.png`已观察。

同一2760秒成熟检查点、相同约120FPS源码GUI、12墙钟秒最终采样 `playtest-reviewed-mature-ui-20261117-172128-396855100.log`与`playtest-final-reviewed-ui-timeline.json`：634次发布，>60ms间隔0次、最大58.352ms；render_ms实际增长1308次，>60ms间隔0次、最大58.402ms。修前对应窗口发布11次/render10次，最大166.655/149.995ms；首次修订中间窗仍有一次75ms发布长尾，原日志保留。这里只说明所测正常成熟负载的规律停顿已削减，不推算精确提升比例或任意负载保证。

当前独立release由`logs/export-20261117-172356-939845500.log`生成，exe/pck已复制至无源码的`.local/playtest-final-package/`运行验证。收尾空间反例前的候选包实际Win32 F5保存→完全退出→F9读取成功；最终包再以原生F9、普通format32适配器载入同一2760秒成熟检查点成功。用户默认存档及bak/tmp原样恢复。D3D12/RTX3060/1280×720、60FPS限制、3秒预热+10秒窗口；前四行为收尾前候选，第五行为当前包：

| 独立release窗口 | 实际倍率 | 帧p95 / p99 / 最大ms | 模拟步均 / p99 / 最大ms |
|---|---|---|---|
| 正常新局/实际保存 | 1.0000× | 16.692 / 16.755 / 16.854 | 5.436 / 26.115 / 42.550 |
| 完全重启/实际读取 | 1.0017× | 16.739 / 16.933 / 17.126 | 5.673 / 31.706 / 45.643 |
| 成熟实际读取 | 1.0010× | 16.801 / 17.255 / 122.090 | 6.646 / 28.566 / 36.347 |
| 成熟同条件复核 | 0.9995× | 16.856 / 17.328 / 73.563 | 6.716 / 28.723 / 36.051 |
| 最终包成熟实际读取 | 1.0001× | 16.692 / 16.710 / 16.966 | 6.575 / 30.215 / 37.853 |

原件为`logs/playtest-final-package-{save,load,mature,mature-recheck,reviewed-mature}.json`及同名前缀日志（save171042、load171058、mature171310、recheck171446、reviewed-mature172415）。最终成品截图`logs/settlement-ui/playtest-final-standalone-reviewed-mature.png`已观察。前两个成熟release窗口仍出现孤立长帧，最终短窗未出现不代表消除；未定位为同一周期观察峰值，没有用平均FPS将其隐藏。本轮不追加低配/万人/三日验收。

构建SHA256：exe `3d19ee4a764e8bb153bfa7f811f98e0dfb0139c9e0c8bc6b76b93d3ed09185bf`；pck `3878287d4359ac71e58404d9b363864720a824cfc401a6342b2418442ae5deb1`。当前包沿`build/windows/sect-foundation/`，旧P5包/格式14/旧用户档保留。源码、成品、GUI、headless成本条件分开记录。

收尾实现及修订后最终双顾问答复分别位于`.local/advisor/playtest-repair-20261117/{implementation-review,final-review}/`，四份完整答复均已通读并独立核查。采纳加载UI重入屏障、日常命令退出瞄准、到场占位复核、新身体首次观察登记、批内保护失效、身份名称与进度时源统一；最终再补跨格身体阻位、接触点身体/路径校验、施工占地闲人唤醒，完成对应反例。拒绝“commit后才knowledge.outcome”（原end_run已先刷新）、“EventText无arrived/action_started分支”（完整源码有）、“after_action不检查manual”（函数自身检查）的推断。保护集依赖按完整Livelihood核查：当前任务等身份已直接入集，仅个人分配和职责宿主占用者依赖subjects；两类均已失效处理，不因片段推断改成每对象重建。全满临时拒绝/原退避与有限让位为本轮明确取舍，不采无条件推动忙工/玩家、永久重排队或全景认识快照。顾问未运行本机，关闭依据仍是实际源码和验证。

额外回归中，原35a0053隔离工作树的`livelihood_smoke`同样在远距求助返回`refused_busy`，`decision_feedback_smoke`同样未满足施工承诺夹具的同意前提；均未为测试改成NPC无条件服从，两项未通过。`settlement_opening_smoke`并发及单独复核均15秒超时（`playtest-opening-isolated-20261117-171627-260718400.log`）；正常装配、真实自主运行/恢复仍另由GUI/成品与个人床检查证明。当时kernel/abilities聚合15秒超时未被试玩专题覆盖；kernel当前状态见本页顶部跨步调度证据，abilities仍未重新验收。

## 宗门共享基座交付

T12c已完成开工/收尾双顾问与整改复核。`logs/t12c-final-normal-gui-20261117-125250-150492700.log`、`t12c-final-native-cooperation-20261117-125307-799726900.log`、`t12c-final-incoming-request-20261117-125344-54728900.log`均errors=0：正常100人main、公共身份/职责/个人床、本人/他人隐私边界、5秒实际运行与文件存读、1280×720/125%滚动界面、真实采木8→付料1→当面求助→同门自主完工→当面结清，以及玩家收到请求、延期中保存恢复再接受。截图`logs/settlement-ui/normal-collaboration-{select,accepted,fulfilled}.png`、`settlement-normal-{character,restored}.png`已实际查看。

共有State使用Godot原生`duplicate(true)`，并用实际类型/嵌套/packed隔离及世界恢复核验；不宣称固定提速。告示读取与直接观察分别按内容修订/时效计算，职责、教学意愿与唤醒共用判断，避免反复读取未变化告示。普通观察沿SubjectView白名单；成员身份来自Institutions.memberships，人物不被当作机构资产。`t12c-latest-visibility-owner-boundary-20261117-125004-866379600.log`核离场旧线索、异步选择、共享组织与另一组织隐私、当前身体可见性和旧Frame隔离，`t13-publication-framework-final-20261117-130058-235835800.log`核原可靠结果发布，均errors=0。

T12b个人设施遗忘已实际定位：旧连续运行中个别居民的个人床被128条认识淘汰，精力最终归零；旧运行在3240000ms主动停止，未通过。修正只保护已获得位置且非传闻的明确个人分配，不新增位置/容量或补回遗忘。`t12b-personal-places-all-residents-20261117-130129-959234900.log`核全部99人的初始床认识、有界周转/撤权/传闻/失效/公共反例及真实自主休养和恢复，errors=0。`t12b-checkpoint-acquired-place-audit-20261117-130047-687247000.log`实读原120秒起点和修正续跑1320秒检查点，二者全部99人均有受保护个人床；未往旧快照注入认识。

正常三游戏日窗口`logs/t12b-protected-places-cycle-20261117-124837-785324100.log`已完整到3600000ms、正常退出、errors=0；从真实普通开局120秒检查点续跑，保留最初审计历史，617/1650秒实际候选恢复，期间无补料/补认识/持续注单或强制劳动。共48播种、80照料、214采收、71烹饪、270进食、1921休养、648实践，另有真实16学习/4传授，四院均有完整源耗/职责/成长消费者。粮初48＋自然224＝末82＋消耗190；餐初128＋71×3＝末71＋消耗270；水初0＋自然344＝末193＋消耗151。来源灵气初8000＋自然57552＝末752＋耗64800，本人实际增灵38880；五项逐窗与终态审计通过。这里的粮总量包含真实植株未采产物，并非全在粮仓。

`logs/t12b-final-energy-and-source-audit-20261117-133723-839508500.log`在同一最终文件上用最新测试直接恢复、不再推进，核99人全活/终饱食>1800/终精力及各人每秒采样最低精力>0、分院工作流和最终候选恢复，errors=0。`t12b-final-personal-place-audit-20261117-134353-701031800.log`独立恢复直接核全部99人个人床仍已知、缺失0，97人当前有128条认识、99人都有体征采样；末饱食最低6999、精力最低7476。1秒采样最低饱食为61号5725（末8457）；最低精力为82号1260（末9084），不是用平均库存掩盖个体失败。还直接核自然水344、井内水192、末来源灵气752与本人灵气38880；分院常规物品统计的差额2粮/1水在灶台2313的工序39中，全World核账包含该work_stock。手动玩家由玩家负责维持，不列入99名自主居民验收。该窗口验证本地重复运行，不证明全年、低配或所有灾害均能自动恢复。

T13正常整合反例`logs/t13-normal-disruption-real-consumption-20261117-125851-595796300.log` errors=0：正常百人自主开锅后，作业者4死亡，原过程1保留公料与实际劳动，真实文件恢复后由5自主接完，55200ms前有人真实进食；未强制接手或改变耗时。初次失败测试错误地要求在餐箱尚充足时仍必须送餐，诊断证实原锅已完成且就地食用，改为核真实供养去向，未改变产品规则。不将死亡后规范责任仍保留误判成复活或自动继任；完整继任仍在范围外。

当前release导出`logs/export-20261117-125738-228058900.log`生成`build/windows/sect-foundation/reol-sect.exe`＋pck。复制两文件至无源码临时目录，以实际Win32 F5保存、完全退出再启动F9读取，`logs/t13-package-{save,load}-20261117-{130021,130036}.log`均成功，epoch提升，原用户档/备份保留。两次D3D12/RTX3060/1280×720、60FPS限制、3秒预热+10秒短窗，实际1.000×，帧时p95约16.69ms、步均约4.10/4.14ms。另以普通format32存档适配器载入同一真实2760秒长测检查点，独立release原生F9读取成功：`logs/t13-package-mature-20261117-132610.log`、`t13-package-mature.json`的10秒窗实际0.997×，帧时p95/p99为16.69/16.96ms、步均4.81ms、步p99/最大68.59/130.98ms；截图`logs/settlement-ui/standalone-mature.png`已实看。当时后台逻辑长测仍在运行，短窗不能证明满速、低配、全年或更大人口。外部`--script`在release未按开发探针运行而30秒退出超时的尝试保留，未作为成功证据。最终实际证据的双顾问答复已完整核查，T12b/T13按既定边界完成；采用/拒绝意见归主计划。

本轮相关短检查、正常GUI/文件、实际中断恢复与独立包通过；既有`python tools/godot.py test`（`logs/smoke-kernel-20261117-124228-85909000.log`）及`abilities_smoke.gd`（`t13-original-barrage-restoration-20261117-130732-274453600.log`）仍各15秒超时，均为未通过。kernel定点停在512人初始工作循环，没有据此声称发布链或弹幕功能已证实损坏；未放宽默认退出与原650ms断言，不宣称全库全绿。

T12a正常宗门装配已完成开工、收尾与整改复核双顾问独立核查。原生Resource一次性装配进入同一main/Runner/World，开发赠物/固定老师/木材与敌人留在开发入口；正常100人（玩家1＋99自主）、四院食宿/田务与成员协作使用原owner。源码现format32/`user://sect-quicksave-v32.reol`，旧31档和独立P5旧包保留；制作入口归[宗门生活](../../design/systems/sect_life.md#当前正常开局的制作入口)。

最终`logs/t12a-final-cold-activation-reviewed-20261117-114016-467578100.log`实际核100人初始/20秒恢复后续跑至25秒、正常无木材源、缺床/假角色/自师承/重复方法/空名/重复灵植/墙内库存、堵灶/封屋/封灵植、同组箱服务隔离、占位探索与环境采样、熟识/授课及性情Resource隔离、新增/复用身体源与能力、首次观察/错峰激活，errors=0。曾真实复现`logs/t12a-navigation-deferred-counterexample-20261117-113700-410729300.log`：预算延后被误当路径成立；现一次性装配逐项以原普通导航额度核验，延后不通过，不改运行中预算。初期新增反例引用未声明Terrain、给类型字典整体赋无类型字典的脚本错误已修，日志保留。

最终原生D3D12 `logs/t12a-final-native-activation-reviewed-20261117-114116-890236100.log`从正常main直接开100人，无夹具读档，人物修行页、实际5秒运行、文件保存/加载及100人/无赠物通过，errors=0；`logs/cultivation-ui/settlement-normal-{start,restored}.png`已实际查看。原ACT `t12a-original-act-consumer-20261117-113424-356277000.log`、有限灵源`t12a-original-qi-sources-20261117-113841-560930700.log`均errors=0。原kernel `smoke-kernel-20261117-113352-167355300.log`仍15秒超时，没有放宽退出或旧计时断言，不能说全库通过。

正常首次持续长测`logs/t12a-normal-first-full-source-cycle-20261117-111729-379442400.log`在900墙钟秒超时，**未通过**。最后完整快照为1200游戏秒：32播种、8锅、98进食、546休养、264实践及真实教学，初48粮被种植/8锅消耗，尚54餐/192水/0粮，无自产粮；自主居民末饱食最坏6964、精力最坏2284。617秒实际候选恢复后继续，诊断耗时从恢复点重计，不能当全程性能。此运行冻结于最终冷启动/公开方法整改前，且光照有效期限制首成熟；它只提供T12b竞争与成本线索，不是百人持续供养、正式平衡或图形性能证明。该段是最终冷启动前的历史失败证据，不能覆盖当前T12b/T12c/T13已完成的独立证据。

T11c持续修持已接原resource目的、共同Query/提交与自然来源，开工/设计/收尾及整改复核双答均已完整独立核查。`logs/t11c-reviewed-final-agency-20261117-110044-803115500.log`实际核精通后2940/2990/2999补到3000停止、真实伤害后两次木愈相隔至少500ms并再补、全部实际灵植生成/耗源核账、空源改用第二种灵植、离场空源恢复后再到场、满灵未精通仍复查、未引介/低温饱不乱练、来源移除零收益、手动中断存读不被接管而恢复自主再练一次；errors=0。`t11c-final-sources-reviewed-schema-20261117-110109-918267400.log`核400ms积分、满源余数、成熟跨界、未开智无果灵植可观察、阶段/容量/余数坏档与共同实践准入，errors=0。

`logs/t11c-advisor-refinement-final-20261117-105859-618373000.log`实际核小饱食缺口自炊保留公粮水、无取还往复、普通技艺不因认识灵植停止探索、外部临时指派实践后回归本人自疗目的、建筑qi/人物qi_carry坏档拒绝，以及Growth不替Nature套个人容量；errors=0。原共同操作与教学回归为`t11c-reviewed-shared-{operations,teaching}-20261117-110044-{810121400,803131600}.log`，原食物/有界目的检查为`t11c-original-{food,boundaries}-20261117-105020-{460718400,460425800}.log`，均errors=0。不会把一个脚本不存在的误命令当成旧回归失败。

最终原生D3D12 Game `logs/t11c-final-native-reviewed-controller-20261117-110109-917740100.log`加载NPC实际修行中状态、查看修行页、真实文件保存/再读后由其完成补灵并停止，满灵精通玩家在新灵植的共用按钮禁用；errors=0。截图`logs/cultivation-ui/qi-{practicing,full-stopped,source-player}.png`已实际查看。初期GUI夹具忘记读档会关闭抽屉/重置选择、点Tab漏Canvas变换，已修夹具；小缺口公料夹具最初漏eat授权与服务，只做完未吃，已按真实组织合同补齐。早期源码解析重名、首次观察错误读取未公开band、2999被过滤的失败均留原日志，未改代价/速度/权限迁就检查。上述均非正常百人/图形性能证明。

`11c-refinement/`两份完整答复已核查：`logs/t11c-final-partner-controller-audit-20261117-110806-262760500.log`实际核外部实践完成至自主自疗间隔至少500ms、主方取消后自主伙伴解绑并唤醒、手动controller不被生活入口添加空唤醒，errors=0。顾问所谓主方擦action使伙伴无法恢复不成立：Society.interrupt使用传入的原action直接unbind并after_action，不走猜测的嵌套end_run；未复制partner_resume到第二状态。外部活动旧Decisions.track_host/ended已有即时execution唤醒，真实修正是共同知识刷新与after_action节流，不能将早期“永久漏醒”推测固化为已复现事实。未采纳无代谢免费修持、死株5秒拒档、过滤所有充足源复查：当前操作有代谢资格、战斗死亡立即移除、低频复查还承担有因失败重试。少量60秒空复查与需求年龄加成留实际百人负载再评估。

T11b已完成开工/收尾及整改复核双顾问核查。`logs/t11b-delivery-and-scope-final-20261117-103140-155956300.log`实际核自主双畦种植、公井实际耗水、稳定宿主跨株授权、公私隔离、同仓出种入粮、单畦/末畦删除、满仓护田、撤职退料、药圃、空源恢复与受阻改做他畦；另核12畦/4规划点下空井和已拒绝满井均不饿死熟粮采收、枯株清理/预付续播/双人共管、鲜明细空闲不巡检、缺料闲暇与真实田务的教学竞争、原株删除后持物/历史恢复、仓满暂持不塞餐箱且腾空后归还。无SCRIPT ERROR，errors=0。原职责与教学同意最终检查分别为`t11b-final-old-duties-20261117-101949-796783300.log`、`t11b-final-teaching-consent-20261117-101949-796748900.log`，errors=0；原栽培合同此前通过。

`logs/t11b-source-cycle-first.log`为同World连续3实际游戏日、8主体（手动玩家与7NPC）、6空田、有限6初种/12过渡餐、井仓灶餐箱与案牍/床位的机制夹具；未缩生长周期，250ms调用内部仍保持原运动与到期边界。第1日+17秒实际候选恢复后继续。完成播种6、取水19、照料12、采收36、归库39、做饭7、进食21、休养126；实际消耗20粮/19水/21餐，与全World初实物及全部自然/井源累计量核账一致，7NPC全活、末饱食均9800。末公库22粮、餐箱6餐。约43秒墙钟仅为这份逻辑夹具运行时间，不是图形帧时、正常百人装配或全年稳态证明；玩家未接管自主，末饱食800，不把手动玩家漏吃说成NPC供养达标。

原生D3D12 Game最终`logs/t11b-reviewed-native-20261117-103140-158775900.log`实际加载自主播种中状态，正常人物页显示活动/任职，保存再读后NPC自己完成播种且未占玩家宿主；errors=0，截图`logs/cultivation-ui/autonomous-field-{role,completed}.png`已实际查看。首次GUI真实揭露人物页按单点库存职责读取田务，已按分型修复；最初测试未防未开工action无started_ms，以及误用handler当操作ID、双田路程窗太短的失败保留，未改游戏成本/速度迁就测试。三昼夜整改后复核`t11b-reviewed-source-cycle-20261117-102418-50522900.log`再次核全部真实源/配方/消耗，errors=0，逻辑墙钟42451ms；不冒充图形或百人证明。暂持反例初期曾把已播1种的源库存写死9，改用拦截时实际源库存加实际归还5；保留归还量、服务仓隔离及恢复断言。

这是T10时期的历史整理段；T11a～c、T12a/c及当前宗门包已在本页上方更新，旧P5包仍保留format14，当前宗门源码/包使用format32。


T11a已完成：开工`11a-start/`与收尾`11a-finish/`双答均已完整核查，相关整改与独立验证完成。采用整畦占用检查/统一锚点、非植物提交安全拒绝、私有栽培权属的共同前置判断，以及过湿单独档位并拒绝无效浇水；稳定宿主派生授权归已开工咨询的T11b，不临时把新植物ID注入所有任职。

独立证据：`logs/t11a-final-contract.log`、`t11a-source-purpose-final.log`、`t11a-advisor-refinement.log`、`t11a-cultivation-reviewed.log`核真实取消/中途恢复、种子/水/受托实物、幼苗观察、占用与权限、成熟跨界/满株余数、非法时钟/宿主/签名拒档，及多格非锚点规范化、整畦异物、屋面蓝图分层、过湿照料拒绝。新增宗门井水显式cultivate用途实际浇公田、单有用途无水源资格拒绝、满背包不创建空受托；未将两个权限合并。`t11a-source-final.log`沿原World跨3实际游戏日，未缩内容周期；无人照料2日后水1/100并停长，真实产1粮；补水/采收后第3日累计产3粮，实际新井累计28水。普通开局另有原井，2日两井各24水，总增48；按全部真实源计数核账，不把另一口井漏计为造物。此为单畦来源合同，不验收百人供养或帧时。

`logs/t11a-native-refinement.log`为真实D3D12 Game：鼠标逐格点击2×2田畦4格、原生栽种按钮、进行中实际文件保存/读取、实际照料耗1水、满水禁用与原因。`logs/cultivation-ui/{sowing,watered-crop}.png`已实看；田畦用程序原创土垄地面图，避免放大花盆挡苗。依原原生显示管线，不新增三维。

相关消费者`logs/t11a-operations-first.log`、`t11a-custody.log`、`t11a-access.log`、`t11a-growth.log`、`t11a-teaching.log`、`t11a-domains.log`、`t11a-activities.log`、`t11a-matters.log`、`t11a-facility-reviewed.log`通过且无脚本异常。最初growth夹具仍按16ms期待教学开始，按T10已定50ms运动完成边界改等100ms；初次批量更新成熟夹具误写表达式已修复。既有设施检查真实复现拆除操作定义漏`landmark`（且`source`同类漏登），补定义后原受控移除/登记/文件恢复通过，不新增移除后端。旧kernel计时问题仍未关闭，未宣称全库全绿。

T10本机验证：`teaching-final-core.log`、`teaching-agency-final.log`、`teaching-obligations-final.log`、`teaching-busy-real-contact.log`、`teaching-partial-understanding.log`、`teaching-moving-final.log`、`teaching-manual-fixed.log`、`teaching-known-dead-fixed.log`、`teaching-borrowed-study-retention.log`、`teaching-student-host-witness.log`、`teaching-real-contact-discovery.log`、`teaching-dormant-duty.log`、`teaching-search-opportunity.log`及`teaching-duplicate-need.log`均errors=0，覆盖教/学对称、真实自修/实践/再传、低悟性多课、有限汇合、远距途中接触、双手动、目击死亡、本人意愿/无视觉拒教、岗位空闲窗口、重复事项与唯一结果/严格恢复。早期复现日志有错误，未用于验收；最终判据须核exit与SCRIPT ERROR，不能只看errors计数。

相关原消费者`teaching-final-activities.log`、`teaching-growth-regression.log`、`teaching-final-learning.log`、`teaching-matters-final.log`、`teaching-final-social.log`、`teaching-knowledge-final.log`、`teaching-livelihood-narrow-fixture.log`及`teaching-request-budget-final.log`均errors=0。满记忆的真实已送达请求先纳本人目标线索保留，再接受联系人凭据，修正收到后立即遗忘；不扩大容量。旧请求夹具已补真实接触距离、无无关旧背景目标与新的accepted_share理由，保持实际受理/保物/控制权断言。

原生D3D12 Game `teaching-native-final.log`为errors=0：正常鼠标“请教”加入自主老师的邀请→共同授业→开工实际文件存读→学习200/实践0，角色与进度截图`logs/teaching-ui/shared-lesson.png`、`player-learned.png`已实际查看。该四人流程不代表百人源耗/季节供养或性能验收。开工/收尾及两轮整改复核双答均已完整核查，采用与拒绝归主计划。

T09d-1内核验证：`logs/social-state-delivery-expiry.log`、`logs/social-state-obligations-first.log`、`logs/social-state-versions-history.log`、`logs/social-state-directional-capacity.log`及`logs/social-state-cooldown-capacity.log`均errors=0。覆盖无新线索相识、未接触零送达、明确拒绝/延期、跨入口施工冷却、时间零/惰性过期/坏档、真实劳动履行/第三方满足、死亡保规范责任与远方认知隔离、修订/份额别名拒绝、历史压缩、同一发起者50名受理者及64联系人预算、拒绝容量恢复。T09d-1开工/收尾及整改复核双答均已完整核查、有关整改完成；追加`social-review-strict-history-final.log`、`social-review-construction-after-audit.log`、`social-review-removed-after-audit.log`、`social-review-proposals.log`与`social-review-origins.log`均errors=0，核跨事项施工排他/改单、无主地其他未分配提案不阻止合法求助、请求接受时刻与Share起源、取消原因和坏档。`social-review-real-archives-and-self-source.log`、`social-review-delayed-labor-after-death.log`、`social-review-lifecycle-final.log`与`social-review-capacity-final.log`同样errors=0，核真实闭合历史压缩、工位自产自取来源、死者生前劳动由接手者完成后合法结算。有关原事项/请求反例仍通过。

T10末次反例与复核：`teaching-refinement-before.log`真实复现运动片内合流后结课越距、手动互补资格漏检、旧锚点失效的借书保留、已知死亡正式责任仍探索及学生host重复事项结案消息。整改后`teaching-final-refinement.log`与`t10-final-native.log`对应规则/原生操作均通过，无SCRIPT ERROR；现场等待者离开按out_of_reach结束原run，不重置汇合期限。`t10-final-{teaching_smoke,teaching_meeting_smoke,teaching_consent_smoke,teaching_agency_smoke,teaching_obligations_smoke,knowledge_boundaries_smoke}.log`及`t10-reviewed-{activities_smoke,society_followup_smoke}.log`通过；低悟性、借书、学生host见证、双手动四模式最终复跑通过。结构审计100文档/378源/0错误。借来的书入门后即不再因实践目的扣留；真实取书/入门/实践/授业与恢复仍通过。以上仍不代表百人或性能验收。

T09d-2已接原正常接触与本人判断，开工/收尾双答均完整核查，有关整改已完成。`social-judgment-real-cooperation.log`、`social-judgment-remote-completion.log`、`social-judgment-needs-budget-manual.log`、`social-judgment-exchanges-and-recovery.log`、`social-judgment-personal-experience-influence.log`及`social-judgment-existing-obligations.log`均errors=0：真实送达/受理后实际施工，现场受益与远方完成分开，后来看见墙不猜谁建，普通拒绝不记怨、移动/恢复不清请求冷却，满预算保未决，玩家/手动收到请求不夺控制，交流水位/坏档/远方死亡与真实三次交谈影响同一个请求判断。第一次提取窄授权函数漏迁一个调用产生编译错误，已修原调用并复跑，不能引用该次失败日志为证据。`social-judgment-existing-knowledge-migrated.log`、`social-judgment-existing-pause-final.log`、`social-judgment-existing-personal-plans.log`、`social-judgment-real-final.log`与`social-judgment-needs-final.log`均errors=0。旧知识夹具改为实际到场、先过拒绝冷却、明确空闲的求助对象，仍保未知/传播上限与寻路失败断言；旧暂停夹具同样明确空闲，保真实份额恢复与续作。一次追加facts用点号新增键产生StringName，触发严格结果校验，已改显式字符串键并复跑；未将错误退出0当通过。`social-judgment-scope-and-recipe-time.log`、`social-judgment-defer-once.log`、`social-judgment-real-trade-and-learning.log`、`social-judgment-real-memory-capacity.log`、`social-judgment-prepaid-no-helper-wood.log`和`social-judgment-recipe-estimate-consumer.log`同样errors=0，核无全组织权的窄授权预估零污染、非成员拒绝、配方批次/期限、单次有因延期后接受或拒绝、真实交易及学习的不对称受益、25次真实新交谈后的容量/重要支持保留，以及无木料帮手使用蓝图原预付材料。挂起/延期后主动寻人和正常回应UI的后续证据见下文T09d-3/-4，不据此宣布百人自治完成。

T09d-3/-4实施与整改证据：`social-followup-player-first.log`、`social-followup-defer-final-calendar.log`、`social-followup-hidden-open.log`、`social-followup-late-first.log`、`social-followup-clock.log`、`social-followup-seek-first.log`、`social-followup-cancellations.log`、`social-followup-budget.log`、`social-followup-absence.log`及`social-followup-release.log`均errors=0，覆盖显式玩家回应/在途坏输入、延期进食后实际回应施工及中途恢复、未知第三方完工不广播、跨响应窗口的履行消息、时钟退避、自主求助、本人/第三方撤案、预算和失踪/死亡/释责。`social-followup-manual-participant-final.log`、`social-followup-partial-budget.log`、`social-followup-known-corpse.log`、`social-followup-resident-busy-owner-fixed.log`、`social-followup-single-allocation.log`及`social-followup-long-work-calendar.log`补自由手动伙伴恢复、111/115/127余量重唤醒、本地死者认识、接触中保留复评、单目标不重复求助与长工序到期实际答复；仍保材料和工时。原`institution_duties_smoke`复评回归通过。`social-followup-history.log`实际保留32条送达/拒绝历史后，第33条仍实际回应、配送并可恢复。最新`social-followup-integrated-matters.log`与`social-followup-integrated-p5.log`原组织生产/采集用途及P5回归均errors=0，无SCRIPT ERROR。

T09d最终整改：`social-followup-need-budget.log`、`social-followup-player-participation.log`、`social-followup-reply-scope-preserved.log`、`social-followup-unseen-reviewed.log`、`social-followup-local-knowledge-reviewed.log`、`social-followup-unbound-strict-reviewed.log`及`social-followup-defer-reviewed.log`均errors=0，核96以上预算时不吞紧急重评、玩家目标/单人伪接触拒载、逐请求退避可恢复且不串扰、16个真实已受托失联跟进+满目的目录仍实际答复容量拒绝、无预注入对端认识的接触线索/非自主短暂离场保复评，以及延期恢复。首版满目的夹具误期望继续接受，实际正确答复refused_capacity，已保“实际到场回答”并修期望，未改容量规则。`social-followup-contact-knowledge-regression.log`原认识检查通过；原活动夹具把“手动但空闲”误当忙方，已给予真实REST宿主并保原拒绝/物资不变断言，结果`social-followup-participation-regression-fixed.log` errors=0；最后`social-followup-p5-final-reviewed.log`原P5亦errors=0。

T09d正常GUI：`social-followup-native-reviewed.log`为最终真实D3D12 Game，原生“人物→约定”延期→回应途中实际文件存读→重开抽屉→显式接受，errors=0；`logs/society-ui/{incoming-request,delivered-deferral,accepted-player-request}.png`已实看。最初GUI夹具漏读档后重开抽屉，已按真实输入补上；调度反例先复现长劳动采用操作擦复评及111～127余量睡死后才修复，不把失败日志当通过。开工/收尾与整改最终复核原件归`.local/advisor/sect-implementation-20261117/09d-final/`；最终双答均已完整核查，整改验证通过。以上不验收百人净供养、多人课堂或性能，旧kernel计时问题仍未关闭。

T09b开工/收尾双顾问已核查并完成相关整改。`matters-review-final-core.log`、`matters-review-final-obligations.log`、`matters-review-reserved-harvest.log`、`matters-review-historical-quota.log`、`matters-review-source-reentry.log`及`matters-review-indexed-history.log`均errors=0，覆盖部分多人/冻结条款/恢复、真实托付/生产/植物配送、配方归属、跨箱声明用途拒绝、原库往返与重放、释放后下调总额、采木实际HARVEST预约恢复/撤权/完成重入、临时帮手取消探索与512事项/4096份额历史压缩。`matters-review-existing-access.log`原范围任职/服务检查errors=0。

`matters-native-reviewed.log`真实D3D12 Game原生协作→选择助手→接受责任→实际保存/加载→原地完工，errors=0；当前`logs/institution-ui/completed-formal-help.png`已实看。首次施工反例误期望180000ms内容劳动在12秒结束，已明确3000ms夹具；首次GUI点透明脚边无命令，改点可见躯干，未改拾取规则。

原消费者`matters-knowledge-boundaries.log`、`matters-feedback-consumer.log`、`matters-original-livelihood.log`、`matters-activity-recovery.log`及`matters-decisions-reviewed.log`均errors=0。旧feedback与decisions的消失地点夹具中老师后来随身已有饭，实际合法先吃自己的饭、远处库存记忆未变；只在这两个反例清随身饭后保持原断言。未强迫全图扫描或放宽规则。T09c收尾已完成：顾问双答均完整返回并逐条核查；职责Resource、现场告示、有限个人读案、受理、真实办理/回报、受阻释责、旧案现场结案和原生GUI/中途存读已接同一World。

T09c独立证据：`logs/duties-repeat-supply-and-restore.log`、`logs/channels-local-information-and-water-reviewed.log`、`logs/duties-shortage-and-unreported-absence.log`、`logs/channels-canonical-terms-reviewed.log`、`logs/channels-race-replacement-capacity-reviewed.log`、`logs/duties-remote-reinspection-first.log`、`logs/channels-race-capacity-dual-purpose-reviewed.log`、`logs/channels-native-final.log`及`logs/duties-final-shortage-absence.log`均errors=0。新增覆盖旧缓存争抢后的现场刷新、来源/目标/条款篡改拒载、来源耗尽与删除后的实地复检、撤职换桌旧案结案、告示容量复用、在制工位不误报、双用途材料与饥饿抢占、有限个人记忆保护、原生查阅→受理→领物→存读中途配送→回报→撤回告示。`logs/channels-native-final.log`为真实D3D12窗口；已实看`logs/institution-ui/read-duty-post.png`与`logs/institution-ui/reported-duty-delivery.png`。顾问未运行本机，以上均为本机独立证据。

T09c边界：当时未包含联系回应；后续T09d已扩实际寻人和当面答复。自动继任、复杂排课仍后置，教学、真实供养与百人装配按T10～T12实施。旧kernel间歇计时失败仍公开保留，未以本项通过掩盖。

T09a实际链路：`institution-scoped-npc-result-20261117-044046-977544000.log`及收尾`institution-review-completion.log`均errors=0；范围炊事者按原Planner领2粮1水烹饪3饭，撤职停工保锅/换人续作，专床不预占却限制实际休养。收尾追加私产寄放的item规划过滤、养护不能收割/拔除/播种、坏嵌套成员/float身份/未知组织安全拒载、直接死体消费拒绝，单范围拔除保真实completed且恢复合法。起初新测试错期待2饭，核原Resource为3饭后修正断言，未改配方。

T09a原生GUI/文件：`institution-native-selected-item-20261117-044359-327948500.log` errors=0，真实Game、原生选用途领2粮/背包受托量、专床按钮禁用及存读；`logs/institution-ui/assigned-bed.png`已实看。`institution-review-reentry.log`与`institution-review-custody.log`均errors=0，原未知退料箱/私人书/竞争目的及保管反例仍通过。双顾问没有运行本机；采用与拒绝归主计划，不把建议当测量。尚未验收百人循环或画面性能；旧kernel计时失败仍未关闭。

T08实际链路：`agency-food-provenance-final-20261117-041916-665049400.log`、`agency-learning-reviewed-20261117-041831-631963300.log`、`agency-boundaries-restoration-20261117-040714-140914500.log`、`agency-public-busy-persistence-20261117-041818-286732600.log`均errors=0。缺料精确拿2粮1水后开锅，手动中断/存读沿原锅续作；拒教后取书/读书/实践；倾向差异与严重需要抢占；公料先退还再按用途领取，设施短忙不退料重领。目标及采用方法不复制原run游标、物资或锅内进度。

T08追加收尾：`agency-refinement-material-probe-20261117-043243-916861800.log` errors=0，真实未观测退料箱→观察→归库、组织箱内私人书→取回→学习、无水时两目的不反复退领粮。首次新夹具把初始化已有transfers算入本次，已改为场景计数差、保留实际物量/学习断言。`agency-refinement-food-20261117-043300-285419000.log`、`agency-refinement-goals-20261117-043300-286717300.log`、`agency-refinement-custody-20261117-043108-938732700.log`和`agency-refinement-feedback-20261117-043153-34079700.log`均errors=0。

T08整改后`agency-known-rights-regression-20261117-042349-624384600.log` errors=0，真实认识/传播原消费者回归；公开容器库存保留可知权属，人物私有库存不外泄。`agency-production-process-group-20261117-040613-501402700.log`、`agency-production-source-short-20261117-040906-866639100.log`及`agency-production-invalid-state-20261117-040934-962010100.log`分别通过原生产断言；原聚合超过15秒，未扩大上限或写成聚合全绿。

T08原生GUI：`agency-native-private-diagnostics-20261117-042325-232398100.log` errors=0，D3D12真实Game文件进入/存读/人物页与修行页原生点击，F12原生输入`decisions`显示选择目标诊断，普通页不透私有动机，继续运行后NPC实际读书有理解进展；`logs/agency-ui/learning-purpose.png`已实看。规模短样本100人、5008ms模拟/wall813ms、239次选择、规划506612μs/121次观察204595μs、单人预算最大64、候选valid=true；不同活动窗不能算纯算法百分比，也不是净供养或GUI帧率验收。旧kernel间歇计时失败仍未关闭。

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

T05追加双答已完整返回并核查；后续随T06补尸体转移后身体库存摘要同步、优先自有同类装备、HUD药水/营造/交易沿可用私产量。不存在“hydrogen仍在途”的未决咨询。

T06规则：`production-lifecycle-variant-20261117-025428-343005500.log` errors=0，实际熟手半程后生手空手接续、途中恢复结果一致、旧run及排队续作不能重开/重产、备料/静置/早收/原工人死亡后换人收药、开工费用与成品空间拒绝、中途塞满保留原物和末量子劳动、腾空续作、拆除在制锅保权回收、有限水源枯竭/真实回补/满源不积攒未来产量、坏原料/阶段/贡献/关联拒载，以及同机制配方Resource变体由原World执行。`custody-wip-20261117-025344-984848200.log` errors=0，公料领6粮3水：第一锅完工，第二锅已投后中断/恢复，原人撤权不能续，乙接手原锅、余2粮1水退库原责任闭合。

相关共同消费者：`operations-production-stations-20261117-025150-999259800.log`、`stations-production-20261117-025410-804108900.log`、`growth-production-receipts-20261117-024636-955261100.log`均errors=0。旧夹具揭露灶台默认工位误约束取饭，已限定为加工工位、保留四向旋转及其他操作位置断言；工艺证据曾用整数字典键违反facts合同，已改有界人员数组及总量摘要，没有放宽共同结果校验。

T06原生GUI：`production-native-ui-complete-20261117-025737-309228000.log` errors=0，真实D3D12窗口从普通Game文件进入，原生按钮请教煎药、备料→静置释放人、实际保存/加载后重新选择原锅、到期收一份药、汲取真实井中一份水且背包增加/井耗尽；`logs/production-ui/passive-batch.png`、`collected-potion.png`已实看。新增操作暴露详情按钮被工具栏遮挡，改为原生滚动详情。此前界面断言分别错配显示文案、未按原合同在载入后重新选择、把空字典缺键误当负库存，逐项核真实命令/物量后修正；不是跳过鼠标或放宽生产规则。此结果不代表百人自主供养或成熟界面交付。

T06收尾双答均完整返回、通读整改。`production-reviewed-boundaries-20261117-030819-881494100.log`及`production-final-contract-20261117-031559-480867400.log` errors=0，补非整秒完工水源合法保存与坏源状态、溢出贡献/空过程/坏时刻安全拒绝、死者不新获实践、128压缩保近期劳动人。`production-public-passive-20261117-031006-90008600.log`、`production-precursor-permission-20261117-031517-880295700.log` errors=0，覆盖公料静置原人死亡/无权者拒绝、收药中断及堵塞、真实炉体+在制物保权拆除并还库闭责、回收组饱和拒拆不损物、跨在途等待者中断接手/完工不重开、撤权时停止记工及中立设施内他人私料保护。`production-source-consumption-20261117-030119-164899500.log`另走真实井水→烹饪→进食。

UI整改后`production-ui-reviewed-hints-20261117-031006-89986900.log` errors=0，静置禁用原因与成熟待收提示由原生详情消费；原工位GUI`stations-ui-production-20261117-030546-55073200.log`通过。`smoke-features-20261117-031038-556896100.log`、`smoke-equipment-20261117-031041-800431400.log`通过；结构100文档/307源/0错误（含尚未接完的T07代码），不替代其运行验证。kernel旧计时问题仍未关闭。

T07认识专题：`knowledge-final-provenance-20261117-034848-587300900.log` errors=0，覆盖真实交谈改变生活选址并实际进食、特定教师拒绝/新教学证据、有限跳数/来源升级、本人私有信息不外泄、异地/远方死亡与删除历史恢复、坏来源/时刻/旧known拒载。`knowledge-final-admission-20261117-034252-900373700.log` errors=0，覆盖盲学/拒绝后取消、独立教学来源、异地反证、远不可达求助退避、尸体可见但不进战斗、旅行中观察、满128条高优认识时新无地点教师及施工承诺仍合法准入和恢复。

T07原消费者：`knowledge-final-feedback-20261117-033459-153261800.log`、`knowledge-final-activities-20261117-033756-211486000.log`、`knowledge-final-livelihood-20261117-034055-659850500.log`均errors=0。原decisions聚合超过15秒，未放宽watchdog/断言；原函数分组`knowledge-final-decision-policy-20261117-034358-913707900.log`及`knowledge-final-decision-lifecycle-20261117-034433-198371600.log`均errors=0，不写成聚合一次全绿。`knowledge-existing-native-ui-20261117-032601-868741600.log` errors=0，真实原生请教/煎药/静置、实际文件存读、收取/汲水。

T07规模边界：`knowledge-100-final-scope-20261117-033422-865862800.log`普通World100人、5秒模拟、wall1016ms，124次观察累计159ms，3509条主体认识、每人最多70，恢复valid=true；仅为短headless样本，不是GUI帧率或百人持续供养验收。旧kernel计时问题仍未关闭。最后整理进一步只检查可见旧址反证、不重复刷新已查主体，未把顾问推测百分比写成性能收益。

## 当前构建

T02收尾追加反例：`operations-variant-final-20261117-010710-927522700.log` errors=0，覆盖新运输定义/实际grain交付、半边伙伴档拒绝、直接中断伙伴自主唤醒、合法在途目标变化可恢复且到场拒绝。`capabilities-operation-final-20261117-010604-965599800.log`、`smoke-features-20261117-010409-895802400.log`均errors=0；真实`operations-ui-final-20261117-010557-460283800.log` errors=[]，已观察生成截图。结构审计100文档/276源/0错误；不将这些短检查宣称百人闭环或性能验收。

Godot 4.7.2 stable（ed1daf0bf），GDScript，Windows release，D3D12 Forward+，1280×720。正式入口`scenes/main.tscn`。当前源码与宗门包是P5决策基座上的百人宗门试玩，加作业位置、合同/碰撞修复与纯二维斜视显示；根目录[启动.cmd](../../启动.cmd)选1源码战斗、2源码百人宗门、3运行`build/windows/sect-foundation/reol-sect.exe`＋同目录pck、4编辑器、5旧P5战斗包。

| 项目 | 当前值 |
|---|---|
| 当前宗门 exe SHA256 | `3d19ee4a764e8bb153bfa7f811f98e0dfb0139c9e0c8bc6b76b93d3ed09185bf` |
| 当前宗门 PCK SHA256 | `6126d5772cce6f2ecac9843dd1256854ac8333966055c7d0ea0e2b2613c86b53` |
| 旧P5战斗包 exe / PCK | `3d19ee4a764e8bb153bfa7f811f98e0dfb0139c9e0c8bc6b76b93d3ed09185bf` / `33623c5a59c15cfcab014b795877ad8190f1d551f4ae2eeff325a91d04f7d83a` |
| 战斗规则签名 | `ed0a331b1a1ed0796a88f58ccad86c0677bbf29b327e0cb977a99ed567f53c8e` |
| 当前决策签名 | `4021c209c5572312ccad01b0d93b115fd18af9aaa20be5a5d228f4c1be4ba40e` |
| 旧P5包决策签名 | `9bb014cebdfdb4196146e2288f25e0cc274e364e34cac2f28d26597fcf06e5cd` |
| 战斗内容 | 40动作、24配置、7套Policy；原生Resource/Inspector制作 |
| 当前源码/宗门包存档 | `reol-world-32`；默认`user://sect-quicksave-v32.reol` |
| 旧P5战斗包存档 | `reol-world-14`；默认`user://act-p5-quicksave-v14.reol` |

当前宗门采用format32，不迁移此前开发格式；旧文件及备份保留，不覆盖。旧P5独立包继续使用其format14及独立默认文件。两包使用同一Godot模板但不同PCK；只核exe哈希不足以识别游戏版本。生成物/日志/本机咨询不入库。运行和制作入口归[usage](../engineering/tooling/usage.md)。

## 固定斜俯视与原生二维显示

用户反馈开启整屏形变后，竖直贴图边缘周期性横移1px。此前坐标反解/奇偶对齐检查通过，只能证明映射正确，不能证明画面质量合格。本轮已删除透视shader、世界离屏纹理/二次合成、设置滑条与F7入口，世界直接由原生Camera2D绘制；旧偏好的view项被忽略，重新保存设置时清除。保留二维斜视测试素材、分部排序、可见精灵alpha选择、主角遮挡淡化和统一坐标转换。原有迷雾mask仍用独立SubViewport。实现归[显示架构](../engineering/architecture.md#纯二维显示)，素材合同归[assets](../../assets/README.md)。

真实nearest、linear及2倍渲染对比见`logs/view-sampling/comparison.png`；最近邻的微斜线产生台阶，线性过滤柔化描边，超采样增加渲染面积也不能恢复原来的竖直几何。双顾问完整返回，原件留`.local/advisor/view-sampling-20261116/round-1/`，均建议按当前像素美术与制作范围撤除。采纳该取舍及原生过滤、stretch/震动输入、迷雾与测量RID复核建议；不把局部精灵缩放不可行或精确性能倍数当作普遍结论。普通非整数缩放的像素宽度差异不等同于本次横向台阶。

| 验证 | 本机证据 |
|---|---|
| 原生显示与实际像素 | `native-view-final-20261116-180521-627253700.log`，VIEW_UI_SMOKE errors=0；根视口直绘、分部/alpha选择、四种窗口含奇数尺寸、三档缩放、震动不改瞄准、真实光标/暂停平移/迷雾与旧偏好清理；离中心竖边逐行核对同一像素列，截图`logs/view-ui/native-*.png`已观察 |
| 移动与控制 | `native-movement_ui_smoke-20261116-180615-624780100.log`、`native-control_ui_smoke-20261116-180619-851367200.log`均errors=0；贴墙三连、单格通行、显示脚点、自由镜头瞄准与原生改键/窗口/UI缩放；`native-control-20261116-180625-803610600.log`另核F7不再保留占用 |
| 普通交互、施工、P4 | `native-ui_smoke-20261116-180624-469727800.log`、`native-work_positions_ui_smoke-20261116-180631-420477500.log`、`native-action_combinations_ui_smoke-20261116-180635-288353200.log`均errors=0；真键鼠选择、物资/续建、组合技能/召唤/光环/器物及文件恢复 |
| 当时独立包 | `export-20261116-180811-303649100.log`成功；`native-pack-restore-20261116-180852-82788600.log`从实际PCK恢复原源码的施工/来源状态/器物样本并推进，完整持久状态相同。当次World、身体/动作定义、format14和两项目录签名未改 |

最新release只测一个512人、1×、60FPS、两worker、迷雾、3秒预热＋5秒采样的framework-combat-v1窗口：`logs/native-final-512.json/.log/.cpu.json`及截图。目标机i5-13600KF/RTX3060、D3D12、1280×720；帧p99 16.836ms、采样步均8.038ms/p99 17.633ms、GPU均0.456ms/p99 1.803ms、主线程process均3.231ms、实速0.99991×，405次交付/57次命中、无脚本/引擎错误、零过载、木材守恒。已撤除额外世界合成pass，单窗结果只排查明显回归，不宣称精确提速或密弹容量；测量在提交前，JSON记录`8f1739f`加dirty，包哈希同本页当前构建。

## 贴墙移动与地面脚点修复

用户试玩报告贴墙平砍后卡死、家具南侧一格通道观感异常。本轮修正直接移动的校验/采用落点不一致，地图正边界格索引，以及显示脚点向下半格的偏移。仍使用原0.35/0.9半尺寸地面身体和完整建筑占地，没有人物逐节点物理、缩墙或第二调度器。静态物品/未开工蓝图先画，身体与实体景物共用脚点排序，成品屋顶最后画。细节见[移动精度](../engineering/simulation-pacing.md)、[素材坐标](../../assets/README.md#坐标占地与接地点)。

| 验证 | 本机证据 |
|---|---|
| 原问题与修复对照 | `movement-diagonal-before-20261116-124125-169412900.log`固定种子1500组产生55个非法终点；同探针修复后`movement-diagonal-fixed-20261116-124334-413780700.log`为0；原边界索引异常保留在`movement-before-valid-20261116-124107-314580600.log` |
| 移动专题 | `ground-fixed-movement-20261116-124540-641937400.log`，MOVEMENT_SMOKE errors=0；每次提交/分段合法、立即退开、微小重叠有限恢复/不穿整墙、两种身体的地图边缘、真实平砍与中途恢复、家具南侧一格通道 |
| 相关原检查 | `ground-fixed-{control,melee}-20261116-124540-*`、`smoke-{kernel,features}-20261116-124732-*`、`ground-work-positions-20261116-124732-755451800.log`、`ground-abilities-20261116-124732-756807400.log`均errors=0；没有扩大为全库矩阵 |
| 真实GUI | `ground-movement-order-ui-20261116-125005-886262700.log`，MOVEMENT_UI_SMOKE errors=0；原生鼠标斜向三连后键盘走过通道，检查GPU脚点与物品/蓝图/家具/身体顺序；截图`logs/movement-ui/`已观察。原普通UI和ACT GUI分别为`ground-ui-20261116-125034-68688100.log`、`ground-act_ui-20261116-125041-430977200.log`，均通过 |
| 当时成品 | `export-20261116-125117-982174300.log`成功；`ground-source-20261116-125137-316131600.log`和实际PCK的`ground-pack-20261116-125139-3370300.log`对复合施工/状态/器物候选恢复并推进，完整状态相同。当次format14及两项目录签名保持，旧存档逻辑坐标不迁移 |

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

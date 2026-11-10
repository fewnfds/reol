# 验证基线历史分卷 05

> 历史资料：保留原日期与结果，不是现行指令或任务；当前信息查[项目记忆地图](../../../README.md)。归档于2026-11-11。

> 历史记录：下文的版本、权限、下一步和 CI 状态只描述记录时，不代表现状。当前证据见[基线](../../../status/baseline.md)。

### B0b 开发地表事务/画笔候选

首轮5组617断言通过后，补欠算/本地闪身拒绝、真实帧余数和派生引用恢复断言；最终分两进程运行5组**628断言、0失败**，无引擎错误：`logs/terrain-editor-final-ui.json`（2组256）、`logs/terrain-editor-final-rules.json`（3组372）。覆盖完整原子拒绝、未来路线/斜角、多个原active域/魂请求/服务、真实大型占地、接触范围、旧区间同步、同会话与候选替换后的工具失效、编辑后在途存读/整段分段未来、施工/私人交换原流程和持续重画积压。未跑本机全套，完整回归待本包最终SHA；普通启动无工具，`--world-editor`+F8才开放。

地图预检复用原解析器，不复制全图或序列化/恢复全世界，不扫描历史事件。私人交换active_jobs及施工material_cell引用是可重建索引、不新增写档状态。施工现有格式仍无条件校验保留项目的材料坐标，首包保守保护终态零库存坐标和完整已注册场地；这是当前实现限制，不是永久世界法则。笔触最多256格；未实现冲突笔触自动取消/绕路或玩家付费改造。

原生Compatibility真实输入：F8打开、实际画布点击3×3水面，人物仍在原行旅途中；写进程退出后另起新进程由原加载器恢复，完整联合摘要均为`a29289068b2f85f1c649b54f393393caea825fe39f1e4c6153fcab587d3aaff3`。1600×900截图`logs/terrain_editor_write.png`已观察；脚本[terrain_editor_capture](https://github.com/fewnfds/reol/blob/8c3deaa972f932e999167b61ea6b166b928cfe5f/tools/qa/terrain_editor_capture.gd)，证据`logs/terrain-editor-native-write.json`、`logs/terrain-editor-native-read.json`。最终写/读6.678/6.389秒、峰值工作集443588608/427433984B。首次真实点击暴露OS鼠标查询与排队点击坐标不一致，改为事件坐标经overlay/camera转换；QA按根viewport缩放送原生坐标，没有绕过GUI直接调用笔触冒充点击通过。截图隐藏其他HUD/迷雾只为查看编辑布局，不写角色知识。

有限活世界编辑压力：[terrain_edits benchmark](https://github.com/fewnfds/reol/blob/8c3deaa972f932e999167b61ea6b166b928cfe5f/tests/benchmarks/terrain_edits.gd)，同机i5-13600KF/20逻辑核/34104020992B内存、Godot4.7.2 debug无头，512图/双聚落12人；1/16/256格各交替修改30次，p50为0.146/0.783/9.581ms，p95为0.195/0.814/10.766ms，p99为0.529/0.832/10.856ms。完整进程5.218秒、峰值工作集385884160B，受30秒/1GiB限制，`logs/terrain-edit-benchmark.json`含原始样本/硬件。计时含原守卫和地图信号提交，不含渲染帧/大量人口/环境源/远区长时容量；30样本不足以证明稳定尾延迟，不能外推大世界规模。

B0b原生审查`e4360f16b68ffc47a026766b80953d56916ad88f`发现：普通取环和向野外原槽放回也要求无遮挡；仅保护draw仍会允许编辑堵住这些原任务。窄修复按原active器物的参与者/目标与放回目的地保守保护接触范围；真实原取环/还环冲突笔触整笔拒绝，原过程仍完成，66断言0失败，`logs/terrain-contact-final.json`（11.913秒、峰值工作集403968000B）。审查器隔离APPDATA的511项定向通过另含系统根证书错误，完整test因sandbox的user://写拒绝连锁失败后停止，**不是完整验收证据**；日志`logs/test-20261104-211111.log`，未把它归为产品缺陷。完整回归仍核目标SHA CI，不重复启动整套或整包审查。

B0b修复提交检查点核对[CI 41831613258](https://github.com/fewnfds/reol/actions/runs/41831613258)完整SHA`3a2b021d632f963a09c0ce796b971f9beef03167`为completed/failure。`--log-failed`只显示一条健康迁移错误，完整godot-logs artifact还含3条投影断言：**188组通过、4断言失败/18389断言**。完整证据`logs/ci/41831613258-artifacts/check-test-20261104-124419.log`；不要把网页/步骤截断输出当完整失败列表。原因均为新根46空terrain_overrides与旧格式的测试接缝：临时v28投影先证明空再移除；真实v41/v2先明确断言新增覆盖为空，再对除该字段以外的全部原字段作原有严格比较。原fixture字节及产品校验不改。定向健康128项0失败（`logs/health-terrain-final.json`，28.580秒）、v41迁移86项0失败（`logs/terrain-migration-exchange-final.json`，6.628秒）、v2身份迁移21项0失败（`logs/terrain-migration-identity-final.json`，6.426秒）。新SHA仍待完整CI，不重复本机全套。

### B1a 结构查询/通知/墙形候选

当前未改根46或原施工格式；只读投影原工程和固定工作间，墙形/视野通知均由原物理状态推导。两组有界定向通过：`logs/structure-regression-rules.json`含房间/休息、实际主场景、热拓扑/真实结构结热、迷雾/地表呈现及两组新结构测试，770项0失败、12.520秒、峰值工作集444035072B；`logs/structure-regression-binding.json`含值事房/历史v34与新旧平面/丘陵装配，95项0失败、20.577秒、峰值424554496B。两进程均受30秒/1GiB限制，无引擎错误/泄漏；不是完整回归或海量结构容量。

初次把10组放进单个30秒样本达到超时，且真实主场景发现`set_sight_obstacle_provider`发未类型空数组导致信号参数转换错误。已改显式`Array[Vector2i]`并补真实重绑用例，拆成上述有界两组复验；初次日志`logs/structure-regression.json`留作失败证据，不把超时算通过。墙形查询优化后新结构两组146项复验通过，`logs/structure-focus-final.json`，2.350秒、峰值220258304B。

原生两进程实际建六墙一门，七笔原transfer/consume凭据共耗22木料，工时/搬运均由原共同时间执行。写进程退出后全新主场景普通加载，完整联合摘要一致：`6447fdc23369127726e3d833f9eac2e992397c4a8bd2336ca7c4c68f73b1c87f`。旧域信号已断、新域/视线来源已重绑；原地开门/关门各一次自动视野更新，身体/焦点未移动，目标可见→不可见且保留探索。之后真实走到东侧观察转角/端头。截图`logs/structure_write_closed.png`、`structure_read_open.png`和`structure_read_corner.png`已观察；[QA脚本](https://github.com/fewnfds/reol/blob/8c3deaa972f932e999167b61ea6b166b928cfe5f/tools/qa/structure_capture.gd)，原记录`logs/structure_write.json`、`structure_read.json`。最终写14.640秒/峰值478674944B，读8.705秒/峰值474640384B，均Compatibility原生渲染、30秒/1GiB限制，无引擎错误。首次QA静态依赖早于autoload已改延后加载，失败仅是QA启动方式，不是产品运行失败。

实测35格×30批墙形查询：同机i5-13600KF/20逻辑核、34104020992B内存、RTX5060Ti、Godot4.7.2 debug，原完整组件投影p95/p99为5.189/5.356ms。改读原ground索引和固定墙/门布尔连接后为0.499/0.543ms，完整快照查询前后不变；原始样本在上述read报告及`logs/structure_read_before_optimization.json`。只证明当前双地12人/7工程的读查询成本，不是帧时或任意规模结构容量。本包原生审查/对应SHA完整回归仍接续。

B1a提交准备时一次发现[CI 41838689908](https://github.com/fewnfds/reol/actions/runs/41838689908)，完整SHA`62c1aa7589e272d1770a75e90aa3e29fc439d9d6`仍in_progress。已登记run，留到下次真实提交时用`tools/ci.py status`核对；不因本地定向通过或旧CI绿色当其通过。

B1a原提交`3118a54ceab3f0e676c55e678d9b8bcb1503e02a`的一次Sol/custom原生静态审查完成，日志`logs/reviews/<SHA>.explicit-sol.log`，未跑引擎/测试/CI。三项P2均修复：首次探索推迟到真实墙体来源装配后；施工订阅视野更新刷新画面及面板；绘制邻接先按可见性过滤，诊断全知查询不变。定向186项0失败、10.756秒/峰值390119424B（`logs/structure-review-focus.json`），包含实际三种身份开局、真实墙后不误探索、既存探索存读不清除及隐藏邻墙变化不改可见mask。原生无手工重绘补偿的读档/暂停门开关格标记通过，截图已复查，8.697秒/峰值483741696B（`logs/structure-native-review-read.json`）；普通旧QA档完整摘要仍一致。窄修复不重复整包审查，最终SHA完整回归待CI。

本次真实修复提交检查点`tools/ci.py status`核上条62c1aa7为completed/success；该终态只覆盖原B0及A0，不把后续B1a当已绿。

### B1b 在途首段与施工清场候选

真实复现：另一人在玩家走到床的首段开始100ms后关门，原实现会关门/取消走路，整段与10ms细分结果不同；未集成日志`logs/motion-clearance-before-integration.json`为111项中7失败，是有效产品复现。修复沿原活动索引和身体保护当前首段及对角两侧，不改变同毫秒结算顺序。新墙/关门受阻后保留已做工时、原材料、行走与预约，不发物理变化；清场后原材料续工只付剩余时间。低床/屋面控制含runtime额外首段来源，不因运动旁格误拒。

当前根46/域格式不变。最终新规则组195项0失败、2.450秒/峰值226504704B（`logs/motion-clearance-final.json`），含真实门/休息及独立恢复整段-分片相同、真实斜向施工与保留材料续工、合法连续道路顶点/对角旁格拒建，以及各原活动域/兽身读同一首段。runtime真实travel_to/越格未到心/后续格释放、候选隔离与普通在途存读、真实玩家斜向门旁冲突62项0失败、3.357秒/峰值394420224B（`logs/motion-clearance-runtime-final.json`）。未配置服务的初版查询测试曾Nil提前返回，不以exit0冒称通过，已改真实服务fixture；初版失败日志保留。

既有结构/房间/兽身/查询/通知回归414项通过（`logs/motion-clearance-regression-rules.json`），既有真实施工/兽身runtime最终62项通过（`logs/motion-clearance-regression-runtime-final.json`）；施工的旧测试格(37,34)正是实际运粮path，保护新规则正确拒建，测试改非道路格(37,35)并明确断言不在路上，保留全部原成本/存读/候选隔离/拆回断言。此处不是放宽产品清场或修改历史fixture。兽身替换旧不完整扫描后另78项通过，13.182秒/峰值430469120B（`logs/motion-clearance-large-final.json`）。各有界样本30秒/1GiB，无引擎错误；不把重复交叉检查相加称全套。

原生普通读取既有真实施工档再开关门/行走通过，画面复查，8.694秒/峰值479141888B（`logs/motion-clearance-native-read.json`）。本包尚无完整停开新增冲突的联合出口或规模承载证据，不据当前12人/七工程外推。已提交推送`fced5e7e3bcd910b3df08aff9e146db7a93a128e`，一次Sol/custom原生静态审查无可操作问题（`logs/reviews/<SHA>.explicit-sol.log`），审查未启动引擎/测试/CI；完整CI尚未查找，按下一实际提交检查点继续。

B1b提交检查点已一次查得[CI 41844868992](https://github.com/fewnfds/reol/actions/runs/41844868992)，完整SHA`0644e4e1c3b6793f0530f00e03f5dab44dc29a4a`仍in_progress，留待下次真实提交，不等待/轮询。

### A1 大型身体查询候选

原`SimEntityQuery`新增`{kind:"large_body",id}`，只读原身体/域时刻与footprint，区分连续像素范围和原保守格扫掠，不新增持久状态或改写根46。导入通过；原实体查询+新大型身体查询两组180项0失败，无引擎错误/泄漏，3.204秒/峰值222244864B，30秒/1GiB限制（`logs/large-body-query-focus.json`）。覆盖真实add_body与同名不同kind、原时间运动、独立在途恢复/分片一致、积压/旧源时刻、返回值脱离、源/绑定/当前步损坏拒绝；不把只读查询当通用生成器或海量物种容量。普通画面未改。已提交推送`245f565715e4b7f29ea49680b61ff66c8fd073df`，一次Sol/custom静态审查无可操作缺陷（`logs/reviews/<SHA>.explicit-sol.log`），未自行跑引擎/测试/CI；最终SHA完整回归待CI。

此实际提交检查点一次核到0644e4e的[CI 41844868992](https://github.com/fewnfds/reol/actions/runs/41844868992)为completed/cancelled，不能当通过；一次发现fced5e7的[CI 41847852498](https://github.com/fewnfds/reol/actions/runs/41847852498)仍in_progress，完整SHA`fced5e7e3bcd910b3df08aff9e146db7a93a128e`，留到下次实际提交检查。未手动取消run、启动等待器或以取消掩盖已失败日志。

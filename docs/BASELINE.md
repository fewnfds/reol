# 构建、兼容与验证基线

核对：2026-11-05。本页只维护“哪个版本有什么证据”，不管理Goal或下一任务；授权/停点见[HANDOFF](HANDOFF.md)，可玩范围见[FEATURES](FEATURES.md)。当前是M2系统原型，完整游戏及45–60分钟切片未验收。

## 已验代码基线

| 版本/工作包 | 证据 | 适用边界 |
|---|---|---|
| `73b765cf533006ca4c90149b55b8f937554dc584` C1a-1共享背景及前序修复 | [CI 41859915825](https://github.com/fewnfds/reol/actions/runs/41859915825) completed/success，C1a-2审查修复实际提交准备核对完整SHA | 覆盖C1a-1与前序A/B/C0及金额包；不覆盖C1a-2固定参考 |
| `62c1aa7589e272d1770a75e90aa3e29fc439d9d6` 地表编辑/活接触及历史投影修复 | [CI 41838689908](https://github.com/fewnfds/reol/actions/runs/41838689908) completed/success，B1a修复提交准备时核对完整SHA | 覆盖此前A0/B0代码；不覆盖后来的B1a及其修复 |
| `945891cc977a60ecb9a499574b33784da9f5cca1` 首屏/会话引用修复 | [CI 41766949005](https://github.com/fewnfds/reol/actions/runs/41766949005) completed/success，2026-11-04通过`tools/ci.py`终态缓存核对完整SHA | 当前游戏稳定起点；四套定向266断言和原生截图见[首屏QA](qa/20261104_world_view_continuity.md) |
| `a29314667f6a743fd3177b0a5190c810c2b6650b` 私人器物交换 | [CI 41762510648](https://github.com/fewnfds/reol/actions/runs/41762510648)：180组、17180断言、0失败，CHECK PASSED | 一环固定报价的有限样本，非通用市场；[QA](qa/20261104_private_exchange.md) |
| `0804c70c385306c592df1d06b39aa0a8c357ff5a` 引物包与旧档断言修正 | [CI 41755190941](https://github.com/fewnfds/reol/actions/runs/41755190941)：175组、16695断言、0失败，CHECK PASSED | 后来的修复不可沿用此绿色；[QA](qa/20261104_drawing_ring.md) |

更早通过/失败、修复与日志原文见[整理前基线](archive/documentation_consolidation_20261104/docs/BASELINE.md)及[QA索引](qa/README.md)。只认具体SHA和验证范围；旧失败数量不作为当前失败，旧成功也不覆盖新代码。

## 当前采用的环境

- Godot当前安装/验证及CI采用 **4.7.2稳定版**，未来跟进最新稳定版，不自动采用dev/RC。
- GDScript、Windows本机、GitHub Linux无头检查；正式Windows独立包未验收。
- AI工具的版本、认证连接与配置归属见[套件实装](AI-TOOLKIT-SETUP.md)，不在本页重复维护第二份清单。

## 存档格式

| 层 | 当前格式 | 说明 |
|---|---|---|
| 联合根schema | 49 | 48固定参考热场、49固定冷热器物；当前工作包最终SHA完整回归待验 |
| 区域/村落 | 41 / 7 | 热状态/定义3、环境3、土地资源4、药草生态状态2 |
| 器物/私人交换 | 8 / 1 | 8新增真实器物储能/开关，7成功warmed的heat_amount继续严格互核；私人交换格式不改 |
| 内容输入 | 37份ContentDB文档的version1包 | 旧档绑定固定v42兼容输入，当前存档携独立内容与装配输入；部分新局规则仍直接读盘 |

其他域版本以对应schema常量和真实fixture为准，不在多个文档手工抄整张版本表。`tests/fixtures/`保持只读，目录说明见[fixture索引](../tests/fixtures/README.md)。旧档迁移不补造过去的知识、实物、交易或动作；现代缺域/混版不能借旧版兼容清空历史。

A0a的根43与隔离争环稿曾用的根43不是可互换格式。争环稿留原分支，不能直接拿其存档喂新引擎；兼容方案须在未来整合前明确。

## 当前候选：待对应SHA完整回归

恢复世界引擎后集中修复旧CI缺陷：课程的方法集合不再依赖内容字典键顺序，仍严格拒绝缺项/多项/重复/替换，原课程历史顺序不改，新课程稳定排序。其余为测试接缝：显式选墙而非菜单首项、修改真实内容包而非只改运行policy、合成地图显式独立工厂、更新旅程校验参数及单/双域装配断言。原历史fixture未改写。

本机定向：施工/交割2组79断言0失败（`logs/recovery-construction-exchange.log`）；存读9组首跑1048断言中2条旧单域装配断言失败，其余通过，修正后仅复验受影响组并加装配组，3组503断言0失败（`logs/recovery-session-recheck.log`，首跑`logs/recovery-session-target.log`）。覆盖真实v35/v36/v39继续、课堂集合损坏、在途交割、墙体通行、候选隔离及单/双域入口；最终SHA完整回归仍待CI，不把定向相加冒称全套通过。

恢复包`306157af5b4d5c396cb6ca2f36a70d0b7709da94`已推送，原生Sol审查无可操作缺陷；日志`logs/reviews/<SHA>.explicit-sol.log`。B0b提交检查点核对[CI 41829419102](https://github.com/fewnfds/reol/actions/runs/41829419102)，完整SHA同306157a，终态completed/cancelled，不能当通过。B0a完整SHA`3a2b021d632f963a09c0ce796b971f9beef03167`已审查无可操作缺陷并推送；同检查点一次发现[CI 41831613258](https://github.com/fewnfds/reol/actions/runs/41831613258)为in_progress，留到下次实际提交核结果，不启用等待器。

### B0a 地表草稿/存读候选

导入通过；最终4组283断言0失败（`logs/terrain-final-focus.log`），覆盖批量原子拒绝/JSON整值/复制隔离/还原基底、水邻与缓存、旧植被擦除/区块卸载/静止视线、真实联合和独立聚落存读。初次呈现测试选的离开位置仍在保留半径内，改为真正离开；初次存档断言混用JSON浮点与内存整数，改为规范值比较；没有放宽产品校验。flat跨图和装配组另在`logs/terrain-snapshot-focus.log`通过，最终新修改仍待对应SHA CI全回归。

实际两进程：写入35格水/岩开局后进程退出，另起普通新局通过原加载器恢复；完整联合摘要同为`4854ebad04be86e6008dd8b9a5568825086686ad641e6d623986af66523a823f`。写进程6.695秒，最终1600×900读档/截图进程7.569秒、峰值工作集414003200B；截图`logs/terrain_native_read.png`已观察，QA隐藏界面/迷雾以检查布局，不写玩家知识。日志`logs/terrain_native_write_result.json`、`logs/terrain_read_final.json`；脚本[terrain_visual_capture](../tools/qa/terrain_visual_capture.gd)。首次QA脚本过早静态引用GameClock导致编译超时，改为autoload完成后动态加载；实际存读另暴露了数组成员检测不等价于整值版本比较，已恢复显式版本比较并由JSON存读覆盖。

地表批量压力：同机i5-13600KF/20逻辑核/34104020992B内存、Godot4.7.2 debug无头，512图seed42；256/4096/32768格分别反复修改10次，提交p50为0.972/18.412/168.884ms，p95与p99均为1.145/20.273/172.199ms（10样本尾部分位等于最大值，非稳定尾延迟）。最大组序列化58.589ms/348289B；完整子进程2.474秒、峰值工作集130514944B，受30秒/1GiB预算。脚本[terrain_overrides benchmark](../tests/benchmarks/terrain_overrides.gd)，原记录`logs/terrain_benchmark_final.json`含硬件/样本。此为纯地图提交成本，不是渲染帧时、人口/环境/远区容量；大画笔需继续按事务和预算拆分，不能宣称32768格能在一帧内编辑。

| 范围 | 已有证据 | 尚未覆盖 |
|---|---|---|
| A0a/A0b内容与装配输入、恢复工厂 | 导入通过；最新9组747断言/0失败，含无活区域装配、A/B/A规则、真实旧档/在途/地图/健康回归，`logs/a0b-focused-fixed-20261104-184057.log` | 当前工作区没有完整回归/对应CI；首次A0b定向因旧几何fixture缺完整装配定义失败，保留断言、修正fixture与兼容查询后复验通过 |
| `tools/world_benchmark.py`监督器 | Windows上8项Python工具测试通过，含超时、OS内存限额、遗留后代清理与进程号保护 | Linux真实进程组回归待CI；Linux限额为逐进程地址空间，清理不覆盖主动脱离组的后代；游戏基准不等于监督器测试 |
| 原型无头性能基线 | 双聚落12人、8192自然格、5游戏分钟，总进程6.688秒，峰值工作集390901760B，采样峰值私有371150848B | 固定512地图；没有人口扩容、渲染、存读或大地图压力结论 |
| A1只读实体位置查询 | 定向76断言/0失败，`logs/entity-query-focused-fixed-20261104-185759.log` | 限人物/雀身/独特器物；无生成、权限/认知过滤、地面数量物或任意容器；首轮失败是测试临时夹具释放导航回调，持有夹具后通过，未改产品行动门禁 |
| A0b2a描述驱动底图工厂 | 7组843断言/0失败，`logs/map-descriptor-focused-20261104-190734.log`；包含原512×512逐格独立oracle、八向静态通行、旧档和完全无活world/map的候选恢复；原v34实际加载/渲染1280×720已观察，`logs/map_descriptor_native_result.json`、`logs/world_map_native_1280.png` | 只接受冻结旧v1，尚无新平面生成器/可变尺寸；合成地图由宿主显式注入，不从存档执行代码 |
| A0b2b新平面生成器/普通新局 | 两份真实种子新局、flat/旧丘陵交叉加载、旧oracle、人物/雀/残识/旧档定向通过；首轮9组982断言有一条旧测试误把新地图亲和当旧地图预期，修正该预期后对应组141断言/0失败：`logs/flat-world-focused-20261104-192116.log`、`logs/flat-publication-focused-20261104-192444.log` | 根45候选；新生成器只512，seed 1..2147473647；未实现尺寸编辑、运行地表改造或通用开局编辑器 |

性能报告：`logs/benchmarks/world_1793784730208624500.json`。场景装配3632.846ms、自然查询186.696ms；分钟推进只有5个样本，p95约506.616ms，不能叫帧时或稳态容量。该早期报告未含后来新增的CPU型号/物理内存字段，不倒填硬件。压力预算与递增场景只在[执行页](plans/world_engine_execution.md)维护。

更新监督器后的递增查询：i5-13600KF/20逻辑核、34104020992B物理内存、Godot4.7.2 debug无头；同一512地图/双聚落12人，每次另推进5游戏分钟。8192/65536/262144格查询分别190.447/1519.103/6169.286ms，总进程6.688/7.998/12.630秒，峰值工作集391430144/391643136/391409664B，查询后缓存均4096格。最大组256格批次p95/p99为6.445/8.369ms，**不是渲染帧时**；每档仅一次，初始化约3.6秒，分钟样本仅5条，未验人口/地图尺寸/多年推演容量。报告后缀`1793789332648927600`、`1793789350231123800`、`1793789377542823200`，位于`logs/benchmarks/world_<后缀>.json`。

`055e2d70927c9a1bd8d6cf0c06aab25eaf814f1b`原生Sol审查指出旧内容仍会被当前开局配置拒绝；A0b改为存档自己的装配输入并新增完整会话回归，不忽略该缺陷。现代缺装配/内容包或配置错配必须拒绝；旧1–43按显式版本迁移，历史fixture不改写。

`8056e5537a8daa4c4ed8371e7c11ab1f9119fb14`的原生Sol审查指出双地运行适配应强制存在服务域，以及已接受的不同居民名单需要重绑home视图。后续修复在提交前拒绝缺服务、对照原身体名单增删显示节点并更新主场景选择列表；不把重建画面当新生成身体。4组定向179断言/0失败（含真实新增居民开局→原开局、雀/残识接续），日志`logs/restore-review-fixes-focused-20261104-185827.log`；修复后原生画面复验通过，`logs/a0b_review_fixes_visual.json`。最终SHA完整回归待CI。

`e3972ef6ad31ca9e773e0dd44d3881d783eeff5a`及`3419c961cd9df52370337b509bf730e0b06240c7`均已完成原生Sol审查，无可操作缺陷；日志位于`logs/reviews/`。GitHub两次服务器错误后恢复，已推送到3419c96；Python工具全套56项通过（含故意失败/超时的包装器样例）。

2026-11-04文档提交检查点通过`tools/ci.py status`核对[CI 41819385359](https://github.com/fewnfds/reol/actions/runs/41819385359)，完整SHA为`3419c961cd9df52370337b509bf730e0b06240c7`，终态**completed/failure**。一次下载失败步骤日志至本机`logs/ci/41819385359.failed.log`：导入退出0，测试退出1，`Results: 177 passed, 28 failed`、17362断言。首个真实失败为`normal loader restores actual original lesson and paid preparation: expected 0, got 30`，后续含普通旧档继续、墙体通行及联合快照断言；根因尚未定位，不能直接归因为历史兼容或忽略失败。此次只登记证据，开发暂停未修改游戏；恢复时集中分析相应路径。后续本地`cadb14f`尚未推送/完整验收，不能把前SHA失败数当作它的实测结果。

新平面普通开局与同档正常存读后原生Compatibility渲染1280×720已观察，进程6.384秒；证据`logs/flat_world_native_result.json`、`logs/flat_world_native.png`。该画面确认原墙门/桌柜/具名人物沿新地图装配，不是独立测试平面；它不证明新候选完整CI或大世界容量。

新flat种子20261104另测8192自然格/双地12人/5分钟：场景装配3325.209ms，自然查询179.035ms，256格批次p95/p99为5.843/6.019ms；缓存4096。分钟样本仍仅5条，p95为437.602ms；布局和seed与旧样本不同，不能归因成某项优化的净收益。报告`logs/benchmarks/world_1793791805095268300.json`。

实际渲染：Godot AI当前无连接会话，改用受限原生Compatibility进程，旧v42在途交割→44保存→释放并重建场景，完整事实和会话地图一致。另执行两个独立进程：写档进程退出后，新进程读取44档，完整联合快照摘要一致；1280×720截图已观察。写/读总进程分别5.450/6.657秒、峰值工作集390897664/414732288B；只作为该固定旧档停开验证，非容量/帧时。证据`logs/a0b_visual_result.json`、`logs/a0b_process_restart_result.json`、`logs/a0b_process_restarted.png`。临时捕获脚本的autoload过早引用问题已通过延迟加载修正，未改产品代码绕过。

内容包只隔离编辑输入副本，不强制公开定义只读；时钟、移动、工作间、对练等部分规则仍直接读盘。候选配置/人物/地点/底图已不借活区域；平面新局可选受限seed，但尺寸仍512、运行视图仍限双地。完整开局编辑、多区呈现与通用生成未完成，不能称A0全部完成或完整世界编辑器。

### B0b 开发地表事务/画笔候选

首轮5组617断言通过后，补欠算/本地闪身拒绝、真实帧余数和派生引用恢复断言；最终分两进程运行5组**628断言、0失败**，无引擎错误：`logs/terrain-editor-final-ui.json`（2组256）、`logs/terrain-editor-final-rules.json`（3组372）。覆盖完整原子拒绝、未来路线/斜角、多个原active域/魂请求/服务、真实大型占地、接触范围、旧区间同步、同会话与候选替换后的工具失效、编辑后在途存读/整段分段未来、施工/私人交换原流程和持续重画积压。未跑本机全套，完整回归待本包最终SHA；普通启动无工具，`--world-editor`+F8才开放。

地图预检复用原解析器，不复制全图或序列化/恢复全世界，不扫描历史事件。私人交换active_jobs及施工material_cell引用是可重建索引、不新增写档状态。施工现有格式仍无条件校验保留项目的材料坐标，首包保守保护终态零库存坐标和完整已注册场地；这是当前实现限制，不是永久世界法则。笔触最多256格；未实现冲突笔触自动取消/绕路或玩家付费改造。

原生Compatibility真实输入：F8打开、实际画布点击3×3水面，人物仍在原行旅途中；写进程退出后另起新进程由原加载器恢复，完整联合摘要均为`a29289068b2f85f1c649b54f393393caea825fe39f1e4c6153fcab587d3aaff3`。1600×900截图`logs/terrain_editor_write.png`已观察；脚本[terrain_editor_capture](../tools/qa/terrain_editor_capture.gd)，证据`logs/terrain-editor-native-write.json`、`logs/terrain-editor-native-read.json`。最终写/读6.678/6.389秒、峰值工作集443588608/427433984B。首次真实点击暴露OS鼠标查询与排队点击坐标不一致，改为事件坐标经overlay/camera转换；QA按根viewport缩放送原生坐标，没有绕过GUI直接调用笔触冒充点击通过。截图隐藏其他HUD/迷雾只为查看编辑布局，不写角色知识。

有限活世界编辑压力：[terrain_edits benchmark](../tests/benchmarks/terrain_edits.gd)，同机i5-13600KF/20逻辑核/34104020992B内存、Godot4.7.2 debug无头，512图/双聚落12人；1/16/256格各交替修改30次，p50为0.146/0.783/9.581ms，p95为0.195/0.814/10.766ms，p99为0.529/0.832/10.856ms。完整进程5.218秒、峰值工作集385884160B，受30秒/1GiB限制，`logs/terrain-edit-benchmark.json`含原始样本/硬件。计时含原守卫和地图信号提交，不含渲染帧/大量人口/环境源/远区长时容量；30样本不足以证明稳定尾延迟，不能外推大世界规模。

B0b原生审查`e4360f16b68ffc47a026766b80953d56916ad88f`发现：普通取环和向野外原槽放回也要求无遮挡；仅保护draw仍会允许编辑堵住这些原任务。窄修复按原active器物的参与者/目标与放回目的地保守保护接触范围；真实原取环/还环冲突笔触整笔拒绝，原过程仍完成，66断言0失败，`logs/terrain-contact-final.json`（11.913秒、峰值工作集403968000B）。审查器隔离APPDATA的511项定向通过另含系统根证书错误，完整test因sandbox的user://写拒绝连锁失败后停止，**不是完整验收证据**；日志`logs/test-20261104-211111.log`，未把它归为产品缺陷。完整回归仍核目标SHA CI，不重复启动整套或整包审查。

B0b修复提交检查点核对[CI 41831613258](https://github.com/fewnfds/reol/actions/runs/41831613258)完整SHA`3a2b021d632f963a09c0ce796b971f9beef03167`为completed/failure。`--log-failed`只显示一条健康迁移错误，完整godot-logs artifact还含3条投影断言：**188组通过、4断言失败/18389断言**。完整证据`logs/ci/41831613258-artifacts/check-test-20261104-124419.log`；不要把网页/步骤截断输出当完整失败列表。原因均为新根46空terrain_overrides与旧格式的测试接缝：临时v28投影先证明空再移除；真实v41/v2先明确断言新增覆盖为空，再对除该字段以外的全部原字段作原有严格比较。原fixture字节及产品校验不改。定向健康128项0失败（`logs/health-terrain-final.json`，28.580秒）、v41迁移86项0失败（`logs/terrain-migration-exchange-final.json`，6.628秒）、v2身份迁移21项0失败（`logs/terrain-migration-identity-final.json`，6.426秒）。新SHA仍待完整CI，不重复本机全套。

### B1a 结构查询/通知/墙形候选

当前未改根46或原施工格式；只读投影原工程和固定工作间，墙形/视野通知均由原物理状态推导。两组有界定向通过：`logs/structure-regression-rules.json`含房间/休息、实际主场景、热拓扑/真实结构结热、迷雾/地表呈现及两组新结构测试，770项0失败、12.520秒、峰值工作集444035072B；`logs/structure-regression-binding.json`含值事房/历史v34与新旧平面/丘陵装配，95项0失败、20.577秒、峰值424554496B。两进程均受30秒/1GiB限制，无引擎错误/泄漏；不是完整回归或海量结构容量。

初次把10组放进单个30秒样本达到超时，且真实主场景发现`set_sight_obstacle_provider`发未类型空数组导致信号参数转换错误。已改显式`Array[Vector2i]`并补真实重绑用例，拆成上述有界两组复验；初次日志`logs/structure-regression.json`留作失败证据，不把超时算通过。墙形查询优化后新结构两组146项复验通过，`logs/structure-focus-final.json`，2.350秒、峰值220258304B。

原生两进程实际建六墙一门，七笔原transfer/consume凭据共耗22木料，工时/搬运均由原共同时间执行。写进程退出后全新主场景普通加载，完整联合摘要一致：`6447fdc23369127726e3d833f9eac2e992397c4a8bd2336ca7c4c68f73b1c87f`。旧域信号已断、新域/视线来源已重绑；原地开门/关门各一次自动视野更新，身体/焦点未移动，目标可见→不可见且保留探索。之后真实走到东侧观察转角/端头。截图`logs/structure_write_closed.png`、`structure_read_open.png`和`structure_read_corner.png`已观察；[QA脚本](../tools/qa/structure_capture.gd)，原记录`logs/structure_write.json`、`structure_read.json`。最终写14.640秒/峰值478674944B，读8.705秒/峰值474640384B，均Compatibility原生渲染、30秒/1GiB限制，无引擎错误。首次QA静态依赖早于autoload已改延后加载，失败仅是QA启动方式，不是产品运行失败。

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

### C0 热投影结果接缝候选

纯投影由整数/-1变显式supported值或失败原因；未知未来的local_conditions省略heat_tenths，并保留heat_supported=false/heat_reason，药草采样和候选先验成功位再用数值。原冻结流/积分/材料成本/样本、正余热规则与根46格式不变，不宣称已支持冷源/负能量/稀疏回收。

四组有界样本全部通过，无引擎错误/泄漏：核心热/环境318项，3.809秒/峰值274391040B（`logs/heat-projection-core.json`）；实际温石/NPC穿衣/预测与药草采样186项，4.009秒/峰值222208000B（`logs/heat-projection-integration.json`）；热迁移/真实在途联合档379项，13.677秒/峰值441237504B（`logs/heat-projection-thermal-archive.json`）；真实药草历史档22项，24.048秒/峰值420782080B（`logs/heat-projection-herb-archive.json`）。各30秒/1GiB。首尝把三档组放一个样本超30秒，拆为后两样本完成，不改超时上限或产品断言；首日志`logs/heat-projection-archive.json`保留。覆盖同段历史/未来/下一边界/MAX_COUNT、空流跨年、七类失败无value、查询不改状态或几何计数，以及普通加载原进行中过程。定向不是对应SHA完整回归，画面未改，本包原生审查/CI接续。

C0提交准备时核fced5e7的[CI 41847852498](https://github.com/fewnfds/reol/actions/runs/41847852498)为completed/cancelled；一次发现245f565的[CI 41849297707](https://github.com/fewnfds/reol/actions/runs/41849297707)同完整SHA仍in_progress。不等待/轮询，不将取消当成功。

C0已提交推送`8df8b1afe43ded86b06ecfbd498f2f00ad35d255`，一次Sol/custom原生静态审查无可操作发现（`logs/reviews/<SHA>.explicit-sol.log`），未自行跑引擎/测试/CI；该SHA完整CI尚未查找，留到下次真实代码提交检查点。后续热场升级规格是待实施候选，不把设计当验收。

### C1a-0 来源金额及提交检查点

原成功释热事件携明确金额，原热收据严格匹配该金额，失败/取消/容量拒绝不产生来源金额、不多扣charge；候选提前初始化同一原热域供器物验证，后续沿原结构/来源恢复热账。写根47/区域39/器物7，热场状态和定义仍v1，37份内容与digest不改，热物理仍是正余热。

所有定向样本受30秒/1GiB上限，无引擎错误/泄漏；数量只描述各组，不相加冒称完整回归：

| 组 | 断言/结果 | 进程时间 / 峰值工作集 | 原始日志 |
|---|---|---|---|
| 真实来源及原热规则 | 256 / 0失败 | 2.348秒 / 220291072B | `logs/heat-amount-source.json` |
| 金额迁移及独立候选 | 96 / 0失败 | 7.180秒 / 430202880B | `logs/heat-amount-migration.json` |
| 原热历史迁移 | 345 / 0失败 | 7.285秒 / 411734016B | `logs/heat-amount-old.json` |
| 真实未完成温石档 | 34 / 0失败 | 8.947秒 / 430161920B | `logs/heat-amount-archive.json` |
| v41真实档 | 86 / 0失败 | 6.883秒 / 434012160B | `logs/heat-amount-private.json` |
| 内容包和装配 | 191 / 0失败 | 7.740秒 / 435462144B | `logs/heat-amount-content.json` |
| 地表联合/单村存读 | 119 / 0失败 | 9.953秒 / 432320512B | `logs/heat-amount-terrain.json` |
| 平面/历史地图来回加载 | 28 / 0失败 | 8.390秒 / 428105728B | `logs/heat-amount-flat.json` |
| 施工热拓扑CI修复 | 38 / 0失败 | 1.494秒 / 205795328B | `logs/heat-amount-topology.json` |
| 缺席世界与事后问路CI修复 | 8 / 0失败 | 21.923秒 / 415105024B | `logs/heat-amount-ci-field_absence.json` |
| 原新局实际问路与重启CI修复 | 14 / 0失败 | 12.916秒 / 411303936B | `logs/heat-amount-ci-field_runtime.json` |

### C1a-1 共享气候背景与精确边界前置

`SimClimateRules.background_at/background_for_region` 统一人物与植物的区域、天气相位和毫秒温度投影；`next_background_boundary_ms` 合并日曲线、季曲线和保存 `epoch_ms` 锚定的天气相位候选，`SimWeather.next_phase_boundary_ms` 不改变原分钟湿润调度。当前热物理、存档版本47/39/7与内容包均不变，固定参考能量仍未接入。

| 组 | 断言/结果 | 进程时间 / 峰值工作集 | 原始日志 |
|---|---|---|---|
| 边界/周期/负斜率/非整分epoch | 644 / 0失败 | 1.504秒 / 206839808B | `logs/climate-rules.json` |
| 人物真实环境与衣物 | 160 / 0失败 | 3.772秒 / 277131264B | `logs/climate-environment.json` |
| 植物真实天气与温度 | 48 / 0失败 | 2.561秒 / 222502912B | `logs/climate-herbs.json` |
| 热场与环境集成回归 | 234 / 0失败 | 8.856秒 / 417406976B | `logs/climate-integration.json` |
| 独立人物/药草/内容候选恢复 | 175 / 0失败 | 1.908秒 / 222220288B | `logs/climate-background.json` |

同机4.7.2 debug无头、30秒/1GiB边界查询基线（不是模拟吞吐或渲染帧时）：128/512/4096组各30次，p95分别1.546/6.085/50.458ms，p99分别1.720/6.087/51.542ms，峰值工作集197730304B，记录于`logs/climate-query-benchmark.json`。曲线候选为确定性边界，即使日/季分量同刻抵消也会保留候选；后续热场必须在边界结旧段再冻结，不可按查询重复重算。

C1a-1代码已提交推送`4fba563c1f7cae3f95d6b65bb74be06866d402cd`，Godot UID元数据补包`a9cadcce3b13cee2ea2c9a0d26554daf4b2e8dec`。一次Sol/custom静态原生审查无可操作发现，日志`logs/reviews/<代码SHA>.explicit-sol.log`，未自行跑引擎/测试/CI。元数据/证据接续检查点核C0的CI `41853073672` completed/failure，196组通过/2组失败、19246断言，失败日志`logs/ci-41853073672-failed.log`仍为上述已修复的两现场QA及12条热拓扑替身脚本错误；不作为新错误再次改产品。C1a-0 CI `41856798020`同完整SHA为completed/cancelled，不能当通过。C1a-1最终SHA完整回归未查询，下一次真实代码提交检查点接续，不主动等待。

新增迁移组明确区分真实v32进行中档与合成v43–46格式包；逐字段保持原内容digest、身体、原charge、热账/冻结流和历史样本，原fixture及候选不原地修改。进行中与已完成候选独立继续、任意分片完整状态相等。旧v6夹带金额、当前缺失/错误金额、收据缺失/冲突、坏digest/冻结流及混版均拒绝且不改活世界。另真实来源组用双倍pulse的独立内容包，恢复按绑定规则而非磁盘默认。原已有charge_baselines之外的完整温石历史扣费未新增审计，不能泛称全部资源历史已证明。

本次实际提交检查点核`245f565715e4b7f29ea49680b61ff66c8fd073df`的[CI 41849297707](https://github.com/fewnfds/reol/actions/runs/41849297707)为completed/failure：196组通过/2组失败、19191断言，另热拓扑替身触发12条脚本错误，失败日志一次下载至`logs/ci-41849297707-failed.log`。两失败是现场QA在老师被新墙遮挡时直接退出；修复为在本人可见、真实可通行邻格有界探索再当面询问，未放宽产品视线或赠送知识。热拓扑测试改用真实VillageSimulation并明确空道路/活动域，保留原施工成本/门屋面断言。两现场组及拓扑组分别复验通过；首次合并两现场组触及30秒预算（`logs/heat-amount-ci-field.json`），按组拆分完成，没有提高上限。后续最终SHA完整回归接续，不能拿本机定向称已修复全部CI。

同检查点一次发现C0 `8df8b1afe43ded86b06ecfbd498f2f00ad35d255`的[CI 41853073672](https://github.com/fewnfds/reol/actions/runs/41853073672)仍in_progress。已登记，留下一次真实提交再查；未等待/轮询/取消。C1a-0已提交推送`2eafa9960f531bab23159a6e44392eb439349f10`，一次原生Sol/custom静态审查无可操作发现，日志`logs/reviews/<SHA>.explicit-sol.log`；未自行跑测试/引擎/CI。对应SHA的完整回归尚未查询，不因此等待。

### C1a-2 固定参考、双向外界与有符号受体

当前写48/40/7，器物仍7，37份内容清单不变但显式转换热定义并重算digest。非负Q采用固定参考，源投入与背景底量/外界交换分账，室外变化不直接改Q；十秒与实际气候候选共同冻结。原身体/药草接受正负温差，未知未来只返回范围/定性说明。数值预检在身体/旅途前失败，保留世界目标及帧债务。仍为有限原温石脉冲、最多512活跃格，没有持续冷热石或回收。

下列主代理有界定向均通过，无引擎错误/泄漏，每进程30秒/1GiB，不相加冒称完整回归：

| 组 | 断言/结果 | 进程时间 / 峰值工作集 | 日志 |
|---|---|---|---|
| 热场规则/固定参考 | 269 / 0失败 | 1.805秒 / 214130688B | `logs/thermal-v2-pure.json` |
| 旧热只读验证器 | 63 / 0失败 | 1.601秒 / 213032960B | `logs/thermal-v2-legacy.json` |
| 独立旧/新候选导入 | 71 / 0失败 | 2.904秒 / 237445120B | `logs/thermal-v2-import.json` |
| 正负受体/预测 | 184 / 0失败 | 5.015秒 / 225505280B | `logs/thermal-v2-receivers.json` |
| 真实来源金额 | 98 / 0失败 | 2.255秒 / 223621120B | `logs/thermal-v2-source.json` |
| 金额历史迁移 | 134 / 0失败 | 7.987秒 / 434143232B | `logs/thermal-v2-amount.json` |
| 真实在途温石档 | 34 / 0失败 | 9.196秒 / 430096384B | `logs/thermal-v2-archive.json` |
| v1–v31原热迁移 | 345 / 0失败 | 10.162秒 / 442597376B | `logs/thermal-v2-history.json` |
| 真实药草档 | 22 / 0失败 | 24.506秒 / 425246720B | `logs/thermal-v2-herb_archive.json` |
| 地表联合/单村存读 | 120 / 0失败 | 10.606秒 / 443678720B | `logs/thermal-v2-terrain.json` |
| 平面/历史地图 | 30 / 0失败 | 8.849秒 / 435208192B | `logs/thermal-v2-flat.json` |
| 独立装配 | 51 / 0失败 | 2.050秒 / 224022528B | `logs/thermal-v2-assembly.json` |
| 真实数值耗尽/时间债务 | 52 / 0失败 | 3.821秒 / 383950848B | `logs/thermal-v2-budget.json` |

首次历史组62条失败来自空热迁移的旧`absolute`预期及环境2标签，改为保留可证明的`legacy_excess/legacy_limits`和环境3；独立村落正向样本改为真正无外域依赖的原在途村落。没有放宽产品验证或改写fixture。基准首跑恢复失败来自组件源直接比较JSON浮点坐标与整数数组，改为完整规范JSON记录比较；生产来源仍逐字段校验。

原生两个独立进程经普通旧档load、GameClock、save/load完成：797431ms未完成释热，840050ms原石charge4→3，实际25格和18°C局部偏差，900000ms保存，1201000ms晴转雨后仍守恒；完全退出再读取的保存摘要及完整未来摘要都与不中断一致。未来SHA256 `a97bc2b15bcdda76bafd3a1d4c4a6ea631b0fc212d7f9d54c9673620233a3689`。write/read分别7.029/6.575秒，峰值工作集434368512/435855360B（GPU私有提交峰值663826432/659173376B），受同30秒/1GiB限制；日志`logs/thermal-native-*-process.json`及`logs/thermal_write.json`、`thermal_read.json`，截图`logs/thermal_write_source_completed.png`、`thermal_read_fresh_process_loaded.png`、`thermal_read_future.png`已实看。左上数字明确是开发观察，非新增玩家全知UI。复现入口`tools/qa/thermal_capture.gd`。

热场组件压力（同i5-13600KF/20逻辑核/34104020992B内存，4.7.2 debug无头）：

| 实际活跃格 / 来源patch数 | 1秒推进p95 / p99 | JSON恢复p95（3次） | 峰值工作集 |
|---|---|---|---|
| 25 / 1 | 1.066 / 1.148ms | 2.269ms | 201416704B |
| 128 / 8 | 4.782 / 4.919ms | 10.338ms | 201146368B |
| 512 / 28 | 18.035 / 18.251ms | 39.456ms | 202022912B |

每规模40次推进、实际天气相界、完整分片相等及守恒；为保证所有格在测量时有可见偏差，组件脉冲为默认100倍，开阔无遮挡且没有身体/器物域/渲染。日志`logs/thermal-v2-25.json`、`-128.json`、`-512.json`，入口`tests/benchmarks/thermal_field.gd`；只证明该组件的有限负载，不是帧时、全世界或长期容量。512格边界重冻约18ms是后续优化热点，不作百万格承载承诺。

提交准备时一次发现前序完整SHA `73b765cf533006ca4c90149b55b8f937554dc584` 的CI `41859915825`为in_progress，留下一真实提交检查点，不等待/轮询。当前包完整本机check和一次原生静态审查接续，未以旧绿或定向代替。

## 工具工作包

`e19804e5f10caf3751ca5c780441b7d8d14f8654`配置生成器支持项目审查模型；20项Python测试通过。现有CI等待器9项离线测试通过。本地显式Sol/custom路由原生审查已完成，无可操作缺陷；日志与配置边界见[审查工作流](CODE-REVIEW-WORKFLOW.md)。它们不是游戏半成品的通过证据，远端状态以实际Git/对应run为准。

## 验收纪律

文档只做结构/链接/差异验证；代码按范围定向，最终游戏行为用对应SHA的完整`check`或CI。画面、声音、手感和性能另需实际证据。不要为文档整理启动引擎，不把测试数量、研究、设计或地图标签写成整款游戏完成。

### C1a-2 审查修复接续

原包提交`350a715e44ba12b43919cd491beeafffcd995678`，一次原生Sol/custom静态审查结束（397.611秒，`logs/reviews/<SHA>.explicit-sol.log`），未自行启动引擎/测试/CI。发现P1：数值失败后GameClock期望时间领先物理时间，普通保存曾返回成功但候选拒绝加载。窄修复为在当前写档合同不支持的时间差出现时，save_game在同步玩家/文件I/O之前明确返回ERR_BUSY，保留原主档/备份和积压，不虚构成功或清掉时间。63项定向通过，4.024秒/峰值391241728B（`logs/thermal-v2-budget-review.json`），含真实有效主档/备份、耗尽后立即拒绝、逐字节不变/无临时产物、原档普通读取恢复。这个受限版本尚不支持将未结算时刻写成可恢复联合档。

主代理为处理该P1主动终止先前完整本机check（130组已运行，38条旧热守恒/版本投影失败；`logs/check-test-20261105-001428.log`），无完整回归结论。保留已知错误记录，不当超时/环境故障或成功。随后逐一改真实迁移比较的显式格式投影和sumQ+loss=input+ambient_in，全部原fixture保持不动；后续完整回归交相应最终SHA CI，不再本机/CI重复全跑。公共投影本身用真实v34与篡改/深拷贝用例验证，不能删除旧事实或默认值凑绿。

此窄修复实际提交检查点核前序73b765c的CI41859915825为completed/success，只覆盖该旧SHA。C1a-2及修复的最终SHA仍待完整回归。

审查修复/旧预期最终定向（每组30秒/1GiB，无引擎错误；不相加称全套）：

| 组 | 断言/失败 | 时间 / 峰值工作集 | 日志 |
|---|---|---|---|
| building | 214 / 0 | 3.260秒 / 226578432B | `logs/migration-v2-building.json` |
| capability | 71 / 0 | 6.984秒 / 447401984B | `logs/migration-v2-capability.json` |
| conflict | 171 / 0 | 12.619秒 / 444268544B | `logs/migration-v2-conflict.json` |
| perception | 180 / 0 | 13.379秒 / 433684480B | `logs/migration-v2-perception.json` |
| drawing | 76 / 0 | 6.981秒 / 435818496B | `logs/migration-v2-drawing.json` |
| field | 40 / 0 | 6.230秒 / 437788672B | `logs/migration-v2-field.json` |
| herb_history | 430 / 0 | 9.860秒 / 411803648B | `logs/migration-v2-herb_history.json` |
| private | 88 / 0 | 8.201秒 / 438661120B | `logs/migration-v2-private.json` |
| loan | 106 / 0 | 10.870秒 / 442675200B | `logs/migration-v2-loan.json` |
| care | 230 / 0 | 22.494秒 / 450854912B | `logs/migration-v2-care.json` |
| history | 345 / 0 | 10.062秒 / 441991168B | `logs/migration-v2-history.json` |

### C1a-3 单次默认背景复用（审查及最终回归接续）

原默认生产路径与自定义Callable分别测量。只在每次冻结重建和边界查询内按地区复用共同climate/weather/epoch/at_ms，返回即释放；两个自定义Callable独立保持逐格调用。不改变字段/版本/物理规则，候选历史段仍用传入anchor/segment。

同机同工作量/100倍有限脉冲/真实天气相界/40次1秒推进，默认路径优化前后：

| 实际格数 | 推进p95 前→后 | 推进p99 前→后 | JSON恢复p95 前→后 |
|---|---|---|---|
| 25 | 1.115→0.715ms | 1.141→0.930ms | 2.328→1.589ms |
| 128 | 4.998→2.923ms | 5.160→3.469ms | 10.738→7.520ms |
| 512 | 19.051→11.255ms | 19.459→12.134ms | 42.287→33.529ms |

日志`logs/thermal-default-before-*.json`、`thermal-default-after-*.json`，每样本30秒/1GiB，分片与JSON恢复守恒都通过。这里只是组件单次配对测量，非渲染帧时或长期/大世界保证；源patch数25/128/512格分别1/8/28。原自定义模式保留，不能用其旧18.251ms当默认19.459ms基线。

定向纯热269、独立导入71、数值拒绝/保存保护63项通过（`logs/thermal-reuse-pure.json`、`-import.json`、`-budget.json`），分别1.795/2.806/3.909秒，峰值214499328/237170688/391041024B，无引擎错误。普通原生read在完全新进程读取先前保存并推进相界后完整摘要仍为`a97bc2b15bcdda76bafd3a1d4c4a6ea631b0fc212d7f9d54c9673620233a3689`，6.628秒/工作集436432896B/私有662740992B（`logs/thermal-reuse-native-read.json`），截图重新核对尺寸1600×900。真实逐格Callable/默认等价专项接续；最终SHA全回归与原生静态审查尚待。

C1a-2窄修复最终已提交推送`e62dee5`，未重复原包静态审查；当前尚未查询其CI，留下一次实际提交准备。

C1a-3实际提交准备一次查得C1a-2修复SHA `e62dee50361c56654db6ecb4ef1986e6c71aa87c` 的CI `41869387451`仍in_progress，登记后留下一次真实提交，不启动等待/轮询。自定义512格模式另实测p95/p99 18.287/19.698ms，守恒与分片通过（`logs/thermal-custom-after-512.json`），该路径按设计不做地区合并。

C1a-3默认/两个独立Callable及混合接入专项113项通过，1.596秒/峰值213270528B（`logs/thermal-reuse-query.json`），覆盖双气候边界、边界前后1ms、非零天气epoch、图外邻格fallback、历史冻流独立JSON恢复并续同未来、自定义同地区不同格底量与各格不同边界。测试不读取或构造缓存内部结构。

C1a-3性能代码提交`9438291bddd0b7d8b676a9b90e1340a2f0cee51e`，一次原生Sol/custom静态审查84.539秒结束，无可操作发现（`logs/reviews/<SHA>.explicit-sol.log`）；审查未运行引擎/测试/CI。导入与结构检查通过（`logs/import-20261105-005042.log`）。最终SHA完整回归仍待CI，下次真实提交集中核对，不主动等待。

### A1b-0 原容器归处与数量查询（审查/最终回归接续）

`SimStorageQuery`只读原village/avian账本及真实身体/地点/工程材料锚点，独特器物非野外位置查询复用；无新实体ID、库存、持久状态或版本。引用严格domain/region/container，数量增加item；报告来源时刻/stale与world backlog，数量含原可用/托管，不提供免费转移。自然虚拟资源、粗粒度货运/嵌套箱等首包明确不支持，不默认原点。

主代理顺序有界定向均通过（30秒/1GiB，无引擎错误），表中数量分别表示覆盖范围，不相加声称完整回归：

| 组 | 断言/失败 | 时间 / 峰值工作集 | 日志 |
|---|---|---|---|
| entity | 76 / 0 | 2.918秒 / 226783232B | `logs/storage-query-entity.json` |
| large | 104 / 0 | 2.211秒 / 223920128B | `logs/storage-query-large.json` |
| artifacts | 91 / 0 | 2.565秒 / 225116160B | `logs/storage-query-artifacts.json` |
| storage | 86 / 0 | 2.050秒 / 221671424B | `logs/storage-query-storage.json` |
| special | 59 / 0 | 3.166秒 / 227028992B | `logs/storage-query-special.json` |

覆盖实际native预约/取货/连续搬运/托管中断/独立JSON恢复后续送同一完整未来、双地同名仓库、陈旧远区/目标积压、不改原账本/输入与返回值隔离；原工程材料取料后仍归project容器、随原身体、中断落material_cell；真实鸟域投食求药/衔药飞行及独立恢复，原库存和高度保持。首次新增测试直接用Dictionary比较JSON托管数值int/float导致一条失败，已统一完整JSON规范值比较，产品账本未放宽。新runner原先引用未注册函数导致临时脚本解析失败，已改动态指定测试，正式runner同步注册。普通画面和玩家功能未改，纯规则定向不代替大世界或视觉性能。

本包doctor/导入通过（最终导入控制台`logs/storage-query-final-import-console.log`）。提交准备时核前序e62dee5的CI41869387451为completed/cancelled，非通过；一次发现前序完整SHA `2102ce8a23aac2222911ecad9e0f8c0945d4ca56` 的CI `41872018227`仍in_progress，登记留到下一真实提交，不等待/轮询。

A1b-0已提交`e5fd27e802137fb997ecc198fa8247e968397764`。主原生Sol/custom审查错误地递归启动另一审查后被主动中断，原日志`logs/reviews/<SHA>.explicit-sol.log`不算完成。恢复同一主审查会话`01a1a784-9f11-79e2-8bd1-93a71095e0c8`，显式固定Sol/custom，禁止再派审查或运行验证；114.306秒后正常退出、无可操作发现（`logs/reviews/<SHA>.resume-sol.log`及`.resume-final.txt`）。未修改代码或运行引擎/测试/CI。AGENTS及审查流程已补防递归职责；最终SHA完整回归待CI。证据补包提交检查点核前序2102ce8同run仍in_progress，不等待。

### A1b-1 器物归处的事务边界（定向通过，审查/最终回归接续）

`SimArtifactTransfers`是world持有的会话钩子，无新物品、位置、历史或写档字段；原位restore保留，独立候选隔离且不补发通知。原take/place/draw在完整原条件后可拒绝预检，实际移动并完成原记录/active释放后通知。私交割只在器物、钱、收据及工作终态全部完成后通知，预检前仍为原物/原钱/预约。已付时间/qi不回滚；draw引用目标剑，不把环当被搬物。守卫是受信任规则，传副本并拒绝相应操作重入，不是运行任意玩家脚本的沙箱。当前未接native/施工/鸟域的完整事务、持续热源/跨格或可搬箱。

主代理顺序有界定向（每组30秒/1GiB，无引擎错误/泄漏）通过：

| 组 | 断言/失败 | 时间 / 峰值工作集 | 日志 |
|---|---|---|---|
| 原器物 | 91 / 0 | 2.703秒 / 225001472B | `logs/artifact-transfer-original.json` |
| 取放/拒绝/重入 | 50 / 0 | 2.007秒 / 227815424B | `logs/artifact-transfer-stone.json` |
| 远引/在途独立恢复 | 31 / 0 | 3.771秒 / 228048896B | `logs/artifact-transfer-draw.json` |
| 私交割完整提交 | 25 / 0 | 2.814秒 / 227840000B | `logs/artifact-transfer-buy.json` |
| 私交割拒绝/释放 | 22 / 0 | 2.812秒 / 228335616B | `logs/artifact-transfer-reject.json` |

含守卫/监听载荷修改不改原物、false/非bool拒绝、取消/另一人begin重入拒绝、1ms未到期无通知、同刻重复结算不重发、同world恢复替换器物域后保留钩子、实际远引拒绝后继续并独立恢复同未来，以及交割回调看齐双钱包/收据/锁。原drawing整组曾触及30秒组件额度而有界停止，无断言/引擎错误输出，不当产品失败或通过；之后只跑上述相关窄组，未重跑整套。本包doctor、导入及结构检查通过（最终导入`logs/import-20261105-011913.log`），没有可见变更，不以headless证明视觉/性能。

实际提交准备核前序2102ce8的CI41872018227为completed/cancelled；一次按完整SHA发现已推送的审查证据补包`9753ed264d9c51a9793b880203bb82dfef39fc82`的CI `41875594099`仍in_progress，留下一真实提交检查，不轮询。该补包包含e5fd27e代码；完整回归仍待对应SHA。

A1b-1原包`c977827627c23490038354d90492b77d7542e5da`一次Sol/custom静态审查204.415秒结束（`logs/reviews/<SHA>.explicit-sol.log`），未运行引擎/测试/CI。两项P2均已窄修：完成监听取消后续动作时逐项核active仍存在；signal载荷的顶层及entity/from/to均make_read_only，监听者需先duplicate再改，避免修改污染后续监听者。API依据Godot官方4.7 Dictionary文档经Context7核对。新增第二监听者及真实双温石同刻取物、首回调取消后动作的回归；既有4组重验58/31/25/22项，加取消18项，最终154项0失败，无引擎错误/泄漏，分别1.897/3.761/2.805/2.802/2.001秒，峰值工作集228454400–229441536B，每组30秒/1GiB（`logs/artifact-transfer-final-{stone,draw,buy,reject,cancel}.json`）。取消专项临时runner先误拼函数名，30秒守卫停止后已纠正并成功，不计产品失败或通过。原91项证据仍为此前版本，完整回归交最终SHA CI，不重复整包模型审查。修复提交准备再次一次核前序9753ed2同run仍in_progress，留下一真实检查点。

窄修复代码已提交`4ef344ee7c3b9916beefbb6da206a0b7cd1211a0`，最终导入/结构检查通过（`logs/import-20261105-012815.log`，200当前文档/358脚本0错误）。C1b规格/证据补包提交检查点仅复用前序9753ed2的CI41875594099非终态缓存，未绕冷却或再查询远端；最终推送SHA完整回归仍待下一实际提交检查。

### C1b-0 共同转移预算与耗尽核（定向通过，审查/最终回归接续）

原热场的真实边界已接`field_span`，无流不凭空添加固定步。无状态`span`验原速率的独立旧出量/旧入容量，`freeze`分配1ms不足的尾量和竞争速率，不预支同段流入或流出腾出的空间；比例余数和补余按稳定边顺序，保守可前进、不承诺最大吞吐。整数大比例逐位计算，不先造出会溢出的乘积。当前根48/热2/器物7及现有源/账/历史样本均未变，尚无真实火石/寒石储量、持续源开关或玩家入口。

主代理顺序定向均受30秒/1GiB限制，无引擎错误/泄漏：

| 组 | 断言/失败 | 时间 / 峰值工作集 | 日志 |
|---|---|---|---|
| 新纯核/可信路径/真实边界 | 6846 / 0 | 2.147秒 / 213770240B | `logs/thermal-budget-kernel-final.json` |
| 原热规则 | 173 / 0 | 1.796秒 / 215478272B | `logs/thermal-budget-pure.json` |
| 固定参考/天气 | 96 / 0 | 1.598秒 / 213716992B | `logs/thermal-budget-absolute.json` |
| 默认/逐格背景 | 113 / 0 | 1.594秒 / 214175744B | `logs/thermal-budget-query.json` |
| 实际数值耗尽/保存保护 | 63 / 0 | 4.013秒 / 392790016B | `logs/thermal-budget-budget.json` |
| 只读旧热校验 | 63 / 0 | 1.599秒 / 214777856B | `logs/thermal-budget-legacy.json` |
| 独立旧候选导入 | 71 / 0 | 2.816秒 / 238465024B | `logs/thermal-budget-import.json` |

新测试含3375组通用小整数、3294组物理Q/余量可信路径与逐毫秒参照和通用路径对比，大于int64乘积的准确比例、JSON浮点整数/非法形状拒绝、排序与输入不变、同格冷热不净抵消、真实137ms注热/5500ms气候/10000ms步边界和5731ms段内独立恢复后不同分片同未来。它们证明预算核，不能替代真实持续器物或全世界完整回归。

同机i5-13600KF/20逻辑核/34104020992B内存、Godot4.7.2 debug无头，原[组件基准](../tests/benchmarks/thermal_field.gd)相同工作量默认背景测量：

| 实际热格 | 推进p95 / p99 | JSON恢复p95 | 峰值工作集 |
|---|---|---|---|
| 25 | 0.623 / 0.648ms | 1.595ms | 206073856B |
| 128 | 3.134 / 3.229ms | 8.276ms | 205733888B |
| 512 | 12.360 / 16.229ms | 35.283ms | 204627968B |

512格接入前同工作量p95/p99 11.236/11.460ms、恢复29.956ms；首版逐边深校验路径16.691/16.957ms、恢复41.295ms，已改为领域已校验数据的扁平聚合快速路径，仍保留对外严格`span`。每档仅一次、40次1秒调用和3次恢复；不是稳定尾延迟、渲染帧时、持续源或大世界容量。三档守恒/分片均过，512格前/后实际Q、源/外界账及128239B快照大小相同。日志`logs/thermal-budget-{25,128}.json`、`-before-512.json`、`-first-512.json`、`-fast-512.json`和`-hardware.json`。doctor/导入/结构通过，完整回归留对应SHA CI。

提交检查点核前序9753ed2的CI41875594099仍in_progress；一次发现完整已推SHA `be51808b69ebd91489b80231ae5a800f59a00324` 的CI `41877947985`为queued。均留下一实际提交，不等待/轮询；排队不是通过。

C1b-0代码提交`6a074a7eecf064e6f91d271e7e5d6ab346fa9f79`，一次Sol/custom原生静态审查137.132秒正常结束、无可操作发现（`logs/reviews/<SHA>.explicit-sol.log`），未自行运行引擎/测试/CI。接续页已由逐包历史压缩为当前状态，历史证据保留在本页及Git；结构检查200当前文档/360脚本0错误。接续补包准备时9753ed2同run复用非终态缓存、不绕18秒剩余冷却；be51808同run新核仍queued，均不等待。最终推送SHA完整回归待下一真实提交检查。

### C1b-1 真实固定冷热器物（当前候选）

根49/区域41/热3/器物8，普通开局三件原器物包含默认关闭的火石/寒石。本人真实研究、启用一分钟/1灵气、关闭一分钟/0灵气；固定地点启用中拒绝搬动，关闭后可取放再启用。原stored_q唯一持有，热域分源/吸收账、启停凭据、冻结终点和样本互核；同格冷热净抵消仍各耗真实储量/容量。移动源、补能、可搬容器、自动稀疏回收未接，不称完整环境引擎完成。

主代理顺序定向，每进程30秒/1GiB，最终日志无引擎错误：

| 范围 | 断言/失败 | 时间 / 峰值工作集 | 日志 |
|---|---|---|---|
| 实物学习/启停/搬动/再启用、独立制冷、1001Q尾量、在途启停取消与近远区、JSON同未来及篡改拒绝 | 244 / 0 | 2.656秒 / 226455552B | `logs/device-final-test_thermal_devices.json` |
| 真实旧根48保存及旧代码未来、完整字段/内容保留、普通load与4类损坏档原子拒绝 | 81 / 0 | 6.529秒 / 438620160B | `logs/device-v2-migration-formal.json` |
| 原热规则/器物/武器/受体/迁移/真实归档/结构/灵源8组 | 1348 / 0 | 单组2.009–10.262秒，最高431849472B | `logs/device-related-test_*.json`，具体用例最终记录为准 |
| v1独立候选导入 / 数值预算与积压 / 共同转移核 | 79 / 0、63 / 0、6846 / 0 | 2.901 / 4.113 / 2.150秒 | `logs/device-core-test_thermal_{import,budget,transfer_budget}.json` |

另验来源金额98、金额迁移134、固定参考96、只读旧热63、物品页46、寄魂页44、认识页9及原温石多用途89项均0失败。当前开局/格式的过期断言更新为声明对象数或操作前后数量不变，历史fixture不改；寄魂页只挑其确有课程的器物，但保留忙碌目标的原拒绝理由。首次恢复错误是JSON坐标类型比较与灵气基线漏认付费enable，已窄修；原账本验证未放宽。

真实旧来源：独立检出`c6061d56326a10b98dd04b75e98ba9344bba6ea6`，旧普通loader接v32真实进行中warm，旧时钟推进后普通writer在905173ms及957520ms写根48档；当前普通导入并继续到后者，完整规范结果SHA256为`6a5166a35cda63b58c0c4bbe8a32519ed96bc173266b0978078d0daec0c915ec`。原字节保存在新增[来源说明](../tests/fixtures/session_v48_thermal.md)及两份fixture，不改原v32。隔离旧checkout首次1GiB内导入出现WebP缓存错误，未算通过；仅对比源PNG字节相同后复用本机已有纹理缓存，干净重跑生成无错误（5.679秒/404762624B），同字节档再验证通过。临时验证脚本早期autoload加载时序错误已修为场景装配后延迟load，无产品绕过。

实际两个原生Compatibility进程：write经原器物面板学习/启用，段内173ms保存后退出；read原load_game恢复，再推进35秒，完整检查点及未来规范摘要均一致。1600×900截图`logs/thermal_devices_read_future.png`已观察，原迷雾/火寒石/人物与定性面板同屏，画面无后台能量泄漏。write6.831秒/410062848B，最终read6.982秒/430866432B，无引擎错误；`logs/device-native-write.json`、`logs/device-native-read-fixed.json`及`logs/thermal_devices_{write,read}.json`。首次QA直接比较JSON坐标Array导致只读断言失败，改用完整规范值比较；原产品与保存不变。

同机i5-13600KF/20逻辑核/34104020992B内存、Godot4.7.2 debug无头，[真实器物基准](../tests/benchmarks/thermal_devices.gd)双地区12人，各40次×1秒推进：

| 启用设备 | 实际热格 / 末尾流 | 推进p50 / p95 / p99 | 完整区域JSON恢复 | 进程峰值工作集 |
|---|---|---|---|---|
| 单火石 | 25 / 46 | 0.329 / 1.641 / 2.216ms | 16.052ms | 248156160B |
| 同格火石+寒石 | 25 / 2 | 0.253 / 1.414 / 1.455ms | 14.853ms | 248602624B |

静默对照零热格/零流，推进p95为0.229/0.226ms；40秒后火石均真实放出40000000Q，双设备寒石另吸入同额，守恒、独立恢复/分片未来一致。双设备较快来自同格净温差消去大部分邻边，不能外推多设备通常更快。每档仅一次，40样本/1次恢复，不是渲染帧时、16源、512活格持续源或多年容量。日志`logs/device-benchmark-{1,2}.json`。

本次实际提交准备核：9753ed2/run41875594099与be51808/run41877947985均completed/cancelled，不算通过；最新已推c6061d5/run41880145840为completed/failure，完整artifact显示211组通过、2断言失败/27402断言，均v33测试未显式投影固定参考/有符号受体格式。失败日志仅下载一次到`logs/ci/41880145840-artifacts/`，集中修旧预期，不能将该失败算成本包完整结果。最新候选完整回归仍留最终SHA CI，不本机再跑全套、不轮询。

上述CI旧预期已窄修：共享历史投影仅接受原空热v1→当前v3，先证明新账为零/设备账为空/无虚构边界，再恢复旧标签并保留完整旧身体、库存、生态和在途事实比较。最终灵源连续性848项/0失败（17.204秒/450772992B）、生态迁移441项/0失败（9.961秒/430661632B），`logs/device-ci-fix-test_*.json`；含伪造设备账/边界/热格不会被投影隐藏的断言。没有放宽产品候选或改写旧fixture。

当前热3组件512活格复测通过，40次推进p50/p95/p99为3.676/14.949/15.007ms，3次JSON恢复p95为31.065ms，快照128424B、峰值工作集209489920B；守恒及分片一致。来源仍为28次合成脉冲、开阔无屋顶几何，不能当512格持续器物或全世界容量。原诊断辅助函数漏传新增候选参数导致首次脚本解析失败，已只修基准的调用；最终`logs/device-field-512-current-fixed.json`无错误。当前完整导入5.725秒/1003188224B，在30秒/1GiB约束内无引擎错误（`logs/device-current-import.json`）；结构检查结果随最终提交记录。

代码提交`55a80682e7d6879fdd530e52c626f303f92ead64`已完成一次Sol/custom原生静态审查，225.235秒、退出0、无可操作发现；只读行为未改工作区，未运行引擎/测试/CI。日志`logs/reviews/<SHA>.explicit-sol.log`及`.summary.json`。最终结构200当前文档/364脚本0错误，暂存凭据/超大文件/缓存及第三方范围检查无发现；最终推送SHA完整CI仍待下一实际提交检查，不将审查无发现当动态回归通过。

### R0a 有限兼容入口清理（当前候选）

从`RegionalSimulation.restore`删除区域30–37的死转换链（原结果最多38，当前形状要求41），九个根档仍需的历史纯转换迁入`persistence/legacy_regional_upgrades.gd`，`SessionSaveSchema`按需调用。逐函数机械对比除显式限定原`RegionalSimulation._integer`外函数体不变；没有复制算法或保留旧运行入口wrapper。旧根导入/39、40专用热候选及旧地图支持未改，格式仍根49/区域41/热3/器物8，旧fixture/用户档不改写。依赖清点见[首包清单](plans/compatibility_retirement.md)，本包不声称整个旧迁移链已退役。

主代理doctor正常，导入5.722秒/1000693760B，无引擎错误，`logs/retirement-import.json`；以下验证顺序运行，各受30秒/1GiB限制，共6组494项0失败，无引擎错误：

| 范围 | 断言 | 时间 / 峰值工作集 |
|---|---|---|
| 真实区域30–37直接拒绝，完整输入/27域所有者/在途原搬运保持，当前41恢复及同未来 | 55 | 2.107秒 / 223911936B |
| 真实根34冲突/办事档、当前旧当前替换、旧未来与原子拒绝 | 171 | 12.635秒 / 446750720B |
| 真实根41在途研究/取物、空新域及混版拒绝 | 88 | 7.293秒 / 441401344B |
| 真实根48热段内与完整旧代码未来、逐字段及拒绝 | 81 | 6.437秒 / 439988224B |
| v1有限导入、独立村落在途、内容与坏候选 | 79 | 2.915秒 / 239099904B |
| 当前装配无活世界基线、A/B/A规则与完整独立候选 | 20 | 5.584秒 / 414908416B |

日志`logs/retirement-test_*.json`；本包无呈现改动，未重复旧画面验证。准备实际提交时以完整SHA发现前包`c3cf78be5cd71c71b2809939520a57548a1ddeca`的[CI 41887478073](https://github.com/fewnfds/reol/actions/runs/41887478073)为in_progress，登记后不等待/轮询。首次误以短SHA查找返回空，不作为未运行的证据，已纠正为完整SHA；这不是CI终态结果。当前候选完整回归留最终推送SHA CI。

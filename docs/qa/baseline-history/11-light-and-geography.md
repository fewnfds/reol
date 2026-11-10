# 验证基线历史分卷 11

> 历史记录：下文的版本、权限、下一步和 CI 状态只描述记录时，不代表现状。当前证据见[基线](../../status/baseline.md)。

### W2b-0 固定火石局部光与当前CI首错

2026-11-05，普通新局火石显式声明可选lighting，沿原唯一器物、个人study/enable/disable、固定归处和实际热冻结正出率推导局部光。没有第二余额/扣费、光时钟或光格储量；初始空场可证明无流，其余未结/脏几何/数值边界明确失败。索引只在freeze/restore按原flows重建且只读；按受光格不再扫描全热流。严格万分相对峰值、1–8格半径、整数平方距离衰减、supercover墙角不漏光、实际墙门/岩石遮挡、多源上限40000（尺度10000），每笔最多441格/128活跃放热引用。固定地点的库存owner时刻较旧不把静止地点变成旅行者；启用端口仍沿原热域验证。规则与普通可见观察/环境行/一个PointLight2D同源，纹理RGB最近采样、只含当前可见格；不扩Fog、NPC视力或植物用途。参数与Godot4.7引用见[实施合同](https://github.com/fewnfds/reol/blob/8c3deaa972f932e999167b61ea6b166b928cfe5f/docs/archive/specifications/world_engine_execution.md)。

无新根档/域状态格式：仍50/41/热3/器物8/climate2；ContentBundle v1的37路径不变，新开局内容digest随显式定义变。旧包缺lighting即没有此效果，不读现行磁盘补字段。真实`session_v49_thermal.json`经普通独立迁移仍enabled且保原已付热，定义仍无lighting、规则局部光为0、观察不改世界、fixture字节未改；最终档案/视图组459项0失败，3.355秒/396484608B（`logs/local_light_archive-runtime.json`）。

doctor正常；最终受限import 5.822秒/998862848B，无引擎错误（`logs/local_light_import-final.json`）。纯传播/实际源/原热器物491项、太阳和热迁移201项、视图/自然光481项、真房间结构229项分别3.355/9.600/3.759/3.556秒；自然观察/真实设备旧档237项10.720秒，均0失败，无ERROR/SCRIPT ERROR/FAIL。日志`logs/local_light_final_regression_{0..3}.json`及`local_light_integrated_final2_tests_2.json`。覆盖真实释热末1001Q的1ms/1Q/耗尽、真实关闭仍留余热、五个分别发行/启用的源叠加饱和、原动作/分片/独立JSON同未来、真实建门/开关/拆除、无支持不结算、不借外世界owner、隐藏/灵魂与只读查询。具体后续补项以相应定向日志为准，不累计重叠断言充当规模或完整回归。

早期失败全部保留：探针把安全整数与int64极值边界混淆已改用不溢出的长乘除；初始全空热几何未结时误报unknown已按原空场可证明无流处理；新测试动态load缺类型已补，门工地不可覆盖原生活设施的拒绝保留，通过明确开局布局在工地旁装配原固定地点重做真实建造；误写不存在定向名的进程不当通过。未削减断言、改写原fixture或恢复已删除旧小时着色器。

有界查询基准[local_light.gd](../../../tests/benchmarks/local_light.gd)：同机i5-13600KF/20逻辑核，Godot4.7.2 headless开发程序，每模式60次×441格；真实1/5个原器物同格、均25个热格，先静止未启用再真实个人学习/启用。明确测试开局容量9000000000Q，五源峰值各10000，一源峰值4000；不是同刻性能对照或倍率承诺。每次查询前后完整世界摘要不变：

| 实际源数/阶段 | mean / p50 / p95 / p99查询 | 完整进程 / 工作集峰值 |
|---|---|---|
| 1 / 未启用 | 0.1373 / 0.136 / 0.143 / 0.176ms | 同下 |
| 1 / 真实启用 | 0.5137 / 0.508 / 0.548 / 0.568ms | 2.047秒 / 243998720B |
| 5 / 未启用 | 0.1374 / 0.137 / 0.139 / 0.159ms | 同下 |
| 5 / 真实启用 | 1.5673 / 1.546 / 1.636 / 1.887ms | 2.349秒 / 244019200B |

日志`logs/local_light_benchmark_{1,5}.json`。p99是60样本最大值；不是渲染FPS、128源容量、不同源覆盖区域、移动源或多年世界验收。每个进程30秒/1GiB外部guard，未并发引擎。

[原生脚本](../../../tools/qa/local_light_capture.gd)在普通Main的零时刻为新开局独立候选显式选择经度180°（其余内容/钟表保持），因此民用08点对应当地太阳20点；没有跳过13小时世界或把旧档补新光。原普通路径到灶房、个人study/enable后，1600×900关/开截图逐图观察，夜间局部暖光、原全图天色与Fog界限成立；保存完全退出后另一个原生进程load重现暖光。图`logs/local_light_native_{off,on,restarted_on}.png`。D3D12 Forward+/RTX3060，write 7.029秒/工作集639864832B/采样私有峰981270528B；read 6.178秒/588529664B/922947584B，均外部限制内，无引擎错误。日志`local_light_native_{write,read}_guard.json`及报告。完整checkpoint SHA256 `c611697cf7268a8b7b1e80cb6bb1faa3396363cdafbc9236bdc9409321078fa8`，原进程与独立重启再12347ms未来均`a8bf5046537be417d8a9eb09e45fe4b14e849c3e6bdee8ccd5294c8ddf8fc039`；并非全帧像素/镜头位置一致或FPS验收。

本次真正提交检查：`a6d379fff0dc63b07990b55a36c222a642d55cf8` / [41906327002](https://github.com/fewnfds/reol/actions/runs/41906327002)为completed/failure，完整artifact已下载至`logs/ci/41906327002-artifacts/`，222组通过/1断言失败/29035断言，另有旧小时函数脚本错误和退出资源残留，不能称完整绿色。首错为鸟类环境行旧精确预期未含W1a天光，另一测试仍调已删除`_color_for_hour`，致其后的crowd测试没执行。现改为完整日历/天气/天光预期（仍排除人类冷暖）及实际赤道无倾角太阳06/18地平线两侧连续、12/0端点；41项0失败且无引擎错误，3.205秒/396681216B（`logs/local_light_ci_fixes_0.json`）。不恢复旧产品分支，不把runner误报PASS当成功。

同一检查点一次发现`2364b0fa62aaa4596c7d2f6422a27ac44bc2ce20` / [41908579492](https://github.com/fewnfds/reol/actions/runs/41908579492)仍in_progress，登记后继续，不等待/轮询。本包原生审查和最终SHA完整CI接续；没有本机重复完整回归，Goal继续active。

最终补核外世界owner拒绝、公开出流索引只读与真实旧档后，光传播/实际源/普通视图三组708项0失败，4.112秒/386416640B，无引擎错误（`logs/local_light_final_owner_tests.json`）。结构201当前文档/390脚本0错误、diff检查通过；本包普通原生审查接续。

代码`4d8f23d713da5cc9f6de0fa35691701b6fc8c4b1`已完成一次Sol/custom显式read-only原生审查，250.493秒/退出0，无可操作发现；核传播/原热流索引/唯一状态/恢复/视野投影，未运行引擎/测试/CI或修改文件。日志`logs/reviews/<SHA>.explicit-sol.log`及`.summary.json`。29文件暂存检查无凭据模式、第三方/缓存/输出、原fixture及超大资源，结构/diff通过；代码与本登记文档阶段推送，不推后查询CI或重复审查。最终推送SHA完整回归仍待验，Goal继续active。

### W1b 新局地理气温编译

2026-11-05，普通Main现在先从地理创建草稿编译原climate2的base/seasonal/daily曲线，经隔离完整内容包校验后发布地图/身体。单地图宏观纬度、海陆温差/滞后和经度日相是明确游戏近似；不是地球精确气候或太阳注热。温度、下一变化边界、全年保守包络、原热场、人物和植物都读同一保存曲线，没有额外隐式温度项或第二余额。年曲线最多25点、日曲线最多4点；日相按分钟量化（至多30秒），午夜整数结点有0.1°C级误差；不足4天年长明确无季温项。普通Main只接受原GameClock起点；坏草稿/包拒绝后可重试，接受后和入树后拒绝重配。合同/理论关系见[W1b](https://github.com/fewnfds/reol/blob/8c3deaa972f932e999167b61ea6b166b928cfe5f/docs/archive/specifications/world_engine_execution.md#w1b-新局地理气温编译实施合同)。

无新写档或迁移：根50/区域41/热3/器物8/climate2及37文档包保持。保存实际曲线/digest，恢复不调用编译器；真实旧49迁入、正常保存50和W2b既有原生50保旧曲线/热账/未来。纯模板load_all语义不改，未把所有旧档强行适配新气候。原fixture只读，无新历史解释器或旧档样本改写。

doctor正常；最终导入5.822秒/1004765184B工作集，0引擎错误。所有本机引擎顺序运行，各受30秒/1GiB外部guard；没有重复完整回归：

| 范围 | 断言/失败 | 完整进程/工作集峰值 | 原始日志 |
|---|---|---|---|
| 地理纯编译与真实Main内容/档案 | 2824 / 0 | 9.948秒 / 426344448B | `logs/geographic-rules-content.json` |
| 真实冷热新局受体与对冲器物/独立分片未来 | 67 / 0 | 2.151秒 / 226512896B | `logs/geographic-world.json` |
| 原内容发布/平面开局/独立世界恢复 | 191 / 0 | 17.559秒 / 442187776B | `logs/geographic-content-regression.json` |
| 原边界/包络/人物环境/草木/屋面天气 | 357 / 0 | 15.794秒 / 467017728B | `logs/geographic-environment-regression.json` |

覆盖南北反季、赤道/极区/零倾角、海陆幅度与滞后、经度不改年相、1/2/3/4/8784天闭合去重、坏profile/内容digest/钟表起点与输入不变；生成曲线边界前各分量不变、包络覆盖，允许同刻相消与重复天气相位。真实药草和人物分钟样本读取生成曲线，火石/寒石经个人真实学习/启用，各付原Q并守恒；跨生成日温最低点的整段和独立JSON恢复分片得到完整相同未来。两个真实Main在不同地理开局间加载同档，恢复原内容和完整未来；真实49沿原独立旧代码未来SHA通过。

同机i5-13600KF/20逻辑核、Godot4.7.2开发程序headless，有界[编译/查询基准](../../../tools/benchmark_geographic_climate.gd)30样本/两地区：纯编译mean/p95/p99=0.1754/0.217/0.309ms，含完整37文档两次校验的独立内容候选17.1162/17.922/18.985ms；每样本512次背景+下一边界组合查询5.2987/6.603/7.269ms。进程2.250秒/209522688B，日志`logs/geographic-benchmark.json`；不代表64地区、渲染FPS、长期模拟或大地图容量。

[原生脚本](../../../tools/qa/geographic_climate_capture.gd)在Main入树前配置赤道与北纬70°，同零时刻08点实际背景分别30.7°C与−12.4°C；1600×900图`logs/geographic_native_{warm,cold,cold_with_fire,restarted_cold}.png`逐张观察：普通环境行呈现闷热/严寒和倾斜日光，真实到场学习/启火后暖光可见。普通界面不显示上述开发数值，不伪造雪/植被群系。D3D12 Forward+/RTX3060，warm/write/read进程5.772/6.728/5.981秒，工作集588009472/603762688/590946304B、采样私有峰906526720/937885696/932556800B，均限额内且无引擎错误。日志`geographic-native-warm-final.json`、`geographic-native-{write,read}-process.json`。真实保存完全退出再由新进程加载，checkpoint SHA256=`19a866752364961f34fb00637fcf8c520cc50dd91cdeab57ecb299f5c6b1c3f4`，再12347ms完整未来均=`6e9d261d913c0ab96edbb39b7fbe35361f8b3e62e758630180076050e708103e`。镜头位置/非持久提示可不同，不宣称像素一致。

另以W2b既有原生50快照和此前已登记的checkpoint/未来SHA运行原`local_light_capture.gd -- read`，继续完全相同未来并保旧手写温度曲线；6.126秒/595738624B、无引擎错误，证据`logs/geographic-old50-native.json`。这是已存在本机原生档的停开验证，不冒称新增入库fixture。最初新QA入口过早静态引用含autoload的runtime导致GameClock编译错误，已改为入树后动态加载；首次warm因身份选择恢复时钟推进350ms，QA改为选择后明确暂停，最终零时刻重测通过。原失败日志保留，不当作产品通过或删门禁。

本次实际提交准备集中核`2364b0fa62aaa4596c7d2f6422a27ac44bc2ce20` / [41908579492](https://github.com/fewnfds/reol/actions/runs/41908579492)为completed/failure，artifact在`logs/ci/41908579492-artifacts/`：223组通过/1断言失败/29069断言，仍是W2b已经窄修的鸟类天光预期及已删小时函数调用，不新增修复或重跑全套；不能称绿色。仅一次发现前推送`12f4cf9b5d968e290c5e955601b0ea1ca1ff0388` / [41913715806](https://github.com/fewnfds/reol/actions/runs/41913715806)为in_progress，登记后不等/不轮询。当前包原生审查及最终SHA完整CI接续，定向和旧绿不替代最终回归，Goal继续active。

W1b代码`a08bc88cafd7d63872937925eb0148d0071c6368`一次Sol/custom显式read-only原生静态审查108.055秒、退出0，无可操作发现；核编译边界/周期、完整包/digest隔离、Main开局与唯一时钟起点、旧热/人体/草木事实保留。审查未运行引擎/测试/基准/CI、未改文件，不重复整包审查。实际日志`logs/reviews/<SHA>.explicit-sol.log`和`.explicit-sol.summary.json`。22文件暂存检查无凭据模式、第三方/原fixture/输出及超大资源，结构201当前文档/395脚本0错误、diff通过；代码与本纯文档登记合并推送，不在推后等待或查询CI，最终SHA完整回归仍待验。

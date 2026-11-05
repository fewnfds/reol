# 验证基线历史分卷 06

> 历史记录：下文的版本、权限、下一步和 CI 状态只描述记录时，不代表现状。当前证据见[基线](../../status/baseline.md)。

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

`e19804e5f10caf3751ca5c780441b7d8d14f8654`配置生成器支持项目审查模型；20项Python测试通过。现有CI等待器9项离线测试通过。本地显式Sol/custom路由原生审查已完成，无可操作缺陷；日志与配置边界见[审查工作流](../../engineering/workflow/code-review.md)。它们不是游戏半成品的通过证据，远端状态以实际Git/对应run为准。

## 验收纪律

文档只做结构/链接/差异验证；代码按范围定向，最终游戏行为用对应SHA的完整`check`或CI。画面、声音、手感和性能另需实际证据。不要为文档整理启动引擎，不把测试数量、研究、设计或地图标签写成整款游戏完成。

# 验证基线历史分卷 02

> 历史记录：下文的版本、权限、下一步和 CI 状态只描述记录时，不代表现状。当前证据见[基线](../../status/baseline.md)。

### C1c-1d：唯一Q压缩运行表示（提交前证据）

2026-11-05，`SimThermalCellStore`成为原热域的唯一Q所有者：细行与孤立5×5块的六轨道互斥，成员数1/4/4/4/8/4。原真实pulse、空间/默认气候/结构准入和逐成员分别入出率一致后才压缩；重冻重验，不合条件无损展开。偏心源、设备启用和结构事务沿原时间边界展开；查询不持第二份可写Q，诊断先付枚举预算。不改变真实源/外界账、全场最早边界、人物/植物响应或有限认识。仍写完整展开热v3，根50/区域41/器物8不变；当前开局仍512逻辑格，不是扩容或永久压缩存档。

doctor/最终导入通过，导入5.935秒/工作集1005301760B，无引擎错误（`logs/thermal-store-import-final.json`）。最终9组1368项0失败，7.093秒/235376640B（`logs/thermal-store-final.json`）；历史导入/设备旧档/普通场景归档3组199项0失败，14.894秒/431988736B（`logs/thermal-store-legacy.json`）。覆盖唯一Q/投影隔离/逐轨道整数预算、原地理气候与禁压缩细格完整参照、天气突变、不同分片/独立JSON、相邻源/启用设备展开、真实施工/塌顶拒绝边界和原fixture。原grouped/history等572项及独立真实地理141项另见`thermal-store-rules-final.json`、`thermal-store-world-final.json`，不累计重叠断言充当规模。

同机i5-13600KF/20逻辑核/34104020992B内存、Godot4.7.2开发程序，组件基准40次×1秒、同一可信open几何、实际气候/天气、16笔组件pulse及400逻辑格：压缩96个Q槽，推进mean/p95/p99=1.21505/10.707/11.222ms；禁止压缩但同样复用几何的400槽参照为0.936225/8.880/9.077ms。两者完整状态SHA256同为`a2f82db539ab744aec344bc29a488354eae22f20bf62e459fd4315266ba8a340`，含4次冻结边界和分片未来一致。展开捕获mean1.807/1.065ms，完整恢复mean27.061/23.991ms，JSON96364字节；进程2.059/2.006秒、工作集210923520/211386368B。日志`thermal-store-400-compressed-retained.json`与`thermal-store-400-trusted_fine.json`。异质512格安全回退512槽，推进mean/p95/p99=5.219075/15.237/15.571ms、恢复mean31.484ms（`thermal-store-512-fallback.json`）。这是准确的存储表示，当前CPU成本更高，峰值内存未证明下降；不是FPS、多年、移动源或大世界容量验收。

普通原生[停开脚本](https://github.com/fewnfds/reol/blob/8c3deaa972f932e999167b61ea6b166b928cfe5f/tools/qa/thermal_store_restart.gd)真实到场学习并付费释热，25格压到6槽；进行中时刻367133ms保存完全退出，由独立进程普通loader读回并继续62347ms。完整checkpoint摘要`a9c52a18a216d6941f0a2217f9f2cfa2794f9206c7b4e3182f50e20325c60ac9`，原/新进程完整未来均`61a85b20c016f2ab5a96c2b735b89d99aa392c6ad8a74c9ba491052ea22c511f`；保存文件SHA256 `fbee56c8d54365876ffd3913be727b82e96a1b223109516377bffdc540c0e0fc`。Compatibility/OpenGL/RTX5060Ti，write/read完整进程8.393/6.879秒、工作集446377984/432005120B、采样私有峰651550720/647921664B；30秒/1GiB外部guard且无引擎错误，`thermal-store-native-{write,read}.json`、`thermal_store_native_{write,read}.json`。1600×900的`logs/thermal_store_read.png`已观察，普通角色/环境暖意与重载场景成立，不声称画面逐像素一致。

早期400格探针虽退出0，但含String/bool比较SCRIPT ERROR，已按真实bool/string几何分支修复；原失败`thermal-store-400-compressed.json`保留，不当作通过。后续保留合格块的原六Q，避免每次先展开再压回，但投影/重冻成本仍待处理。所有最终验证顺序运行并设30秒/1GiB上限，未重复完整回归。

本次真实提交检查：`4394dfbffdf1215c7e435dfdfb8cb05a3612dd32`/41922985281缓存终态completed/cancelled，不算通过；从Git取得准确前推送`b6c6ccb6c5219c9b5c486657320b35d712fafaf0`仅一次发现41925101451为in_progress，留下一真实提交检查。一次错误SHA/缺run参数未发出有效查询，不计证据。最近已核完整绿仍99eb91c；本包一次原生审查及最终SHA完整回归待接续，不等待或轮询。

C1c-1d代码`c0d7dcf42a72ae0b70410da66751d834013a6c79`已完成一次Sol/custom显式read-only原生静态审查，240.469秒、退出0，无可操作发现；核唯一Q/压缩展开、时间/结构和存读，未运行引擎/测试/CI或修改文件。证据`logs/reviews/<SHA>.explicit-sol.log`及`.explicit-sol.summary.json`；不重复整包审查。19文件暂存检查无凭据模式、第三方/输出/缓存/原fixture或超大资源，结构201当前文档/404脚本0错误、diff通过；代码与审查登记文档阶段推送，最终SHA完整回归仍待验，Goal继续active。

### C1c-2a：新格分配预检与多源容量测量（提交前证据）

2026-11-05，脉冲与设备启用共用只读新格计划，按坐标并集/原绑定逻辑限额先拒绝，再计算底量和物化旧场；成功提交复用新行，不重复查询底量。`allocation_capacity`明确逻辑格、实际Q槽、完全细化预留与保守流记录计数，只作开发查询，不是字节内存保证或第二份Q。保持正式512、自定义1–8192、完整v3写档及全部根/域格式；新增`CellStore.snapshot`只生成一份脱离全场行集，避免压缩投影再深复制整场。

定向6组1242项0失败，11.011秒/236417024B（`logs/thermal-allocation-focus.json`）；含显式完整地理包30格精确满额、偏心重叠只增5格、实际失败动作与同刻取消对照不改Q/账/原物储量、50格真实设备启用后完全展开、天气/不同分片/独立JSON同未来、600上限内容绑定恢复及原热核/结构/设备。不把600空场当600实际负载。旧档/原生归档3组199项0失败，15.039秒/432193536B，导入6.799秒/1004879872B且无引擎错误（`thermal-allocation-legacy.json`、`thermal-allocation-import-final.json`）。

递增实际器物基准只在独立内容装配前将max_cells设600/1600；其它热规则不变，每件由预声明真实操作者完成原study/enable，火/寒交替、地点间隔8格，保原居民与两地区但关闭fixture自主。40次×1秒、每件真实转移40000000Q，逐件储量/总账守恒、两次独立完整JSON及两种分片7337ms未来一致。改前后完整checkpoint/未来SHA相同，无伪造收据/直接注Q；正式Main未扩大容量。以下是修后最终证据：

| 实际器物/热格/人物 | 推进mean/p95/p99 | 完整恢复两次 | 完整进程/工作集峰值 | JSON |
|---|---|---|---|---|
| 24 / 600 / 36 | 5.487425 / 25.896 / 40.364ms | 265.243 / 261.594ms | 3.713秒 / 237789184B | 220974B |
| 64 / 1600 / 76 | 15.174325 / 70.678 / 120.463ms | 1250.376 / 1246.750ms | 11.615秒 / 237449216B | 527788B |

同前述i5-13600KF/Godot4.7.2，原始全部样本`logs/thermal-allocation-scale-{24,64}-final.json`；最初测量`thermal-device-scale-{24,64}-capacity.json`保留，不能把同类多次测量当独立容量或提速证明。enabled场600未来SHA `bcb6413f40bbd7ae6010ad7387fc3516075e7948c2ef34d7d3c393b87a9c7a5a`，1600为`34c5f6dfd7c69973422497da27330928fff62152c5e4f733c3a11b7d0086d0d6`。结果揭示集中重冻/候选恢复开销，非FPS/多年/移动源/全停开规模验收。

普通Main本次真实到场/付费脉冲的两进程完全停开通过，重启再62347ms完整未来同为`2a1359e8d07ee5053d16310f6f0ffebe3e281f857c82746b0a57b7784141a7a6`，checkpoint `7a747f09a8cf6afb9148662abbd3974bc553c756c7fe8f72224f796eb2e5e7fe`；25格/6槽，仍非600/1600原生Main出口。write/read完整进程8.644/6.883秒、工作集472498176/434987008B、采样私有峰659972096/639668224B，Compatibility/RTX5060Ti，`thermal-allocation-native-{write,read}.json`及`thermal_allocation_native_{write,read}.json`，1600×900 `thermal_allocation_read.png`已观察。另直接只读上一包原生保存并比对原有checkpoint/未来SHA通过，7.033秒/436256768B，`thermal-allocation-previous-native.json`；原文件不改。两次新开局截图的Fog采样覆盖可因呈现帧不同而不同，不把重开新局与同档续算混作一个断言。

本次真正提交检查：前推送`b6c6ccb6c5219c9b5c486657320b35d712fafaf0`/41925101451 completed/failure，232组通过/1失败/33368断言。完整artifact `logs/ci/41925101451-artifacts/`；唯一首错是原练习剑与新微光珠同住处同展示点，点击按ID命中珠子，正在窄修真实叠物可选性。一次发现准确前推送`c40c5573457f06d65b11bade434f7e05de72065a`/41929130480为in_progress，留下一真实提交，不等待/轮询。本包最终SHA完整回归待验。

C1c-2a提交前集中修复上述真实点击问题：同物理格且原展示点相同的**当前可见**器物按稳定ID上下分散，单件/持有者连续点/高度及原冷热石左右偏移保留。绘制与一次指针事件共用单次临时layout，不逐件再扫全域，不保存另一份物理坐标；未见器物不影响已见布局。原世界选择器/能力/可见/距离规则不改。武器/固有光/热光runtime及纯器物4组653项0失败，17.455秒/417800192B，无引擎错误（`logs/object-stack-focus.json`）；含真Main同住处剑/珠分别经平移缩放点击、火/寒石分别点击、被真实视线阻挡的同格环不影响已见物位置，完整世界在查询/点击前后不变。原生Compatibility/RTX5060Ti运行同一相机变换、两次实际指针选择及1600×900剑/珠面板与收起后分散图标截图均已观察（`logs/object_stack_{training_sword,amber_pearl,separated}.png`）。最终原生6.079秒/工作集431759360B/采样私有峰630657024B，无引擎错误，日志`object-stack-native-final.json`；30秒/1GiB顺序guard，未重跑整套。4器物原reference基准模式也通过，2.149秒/237555712B（`thermal-allocation-scale-reference.json`）。本包一次原生审查及最终SHA完整回归仍待接续。

## 当前采用的环境

- Godot当前安装/验证及CI采用 **4.7.2稳定版**，未来跟进最新稳定版，不自动采用dev/RC。
- GDScript、Windows本机、GitHub Linux无头检查；正式Windows独立包未验收。
- AI工具的版本、认证连接与配置归属见[套件实装](../../engineering/tooling/setup.md)，不在本页重复维护第二份清单。

## 存档格式

| 层 | 当前格式 | 说明 |
|---|---|---|
| 联合根schema | 50 | 49固定冷热器物、50自然日照内容；当前工作包最终SHA完整回归待验 |
| 区域/村落 | 41 / 7 | 热状态/定义3、环境状态3绑定climate2、土地资源4、药草生态状态2 |
| 器物/私人交换 | 8 / 1 | 8新增真实器物储能/开关，7成功warmed的heat_amount继续严格互核；私人交换格式不改 |
| 内容输入 | 37份ContentDB文档的version1包 | 旧档绑定固定v42兼容输入，当前存档携独立内容与装配输入；部分新局规则仍直接读盘 |

其他域版本以对应schema常量和真实fixture为准，不在多个文档手工抄整张版本表。`tests/fixtures/`保持只读，目录说明见[fixture索引](../../../tests/fixtures/README.md)。旧档迁移不补造过去的知识、实物、交易或动作；现代缺域/混版不能借旧版兼容清空历史。

A0a的根43与隔离争环稿曾用的根43不是可互换格式。争环稿留原分支，不能直接拿其存档喂新引擎；兼容方案须在未来整合前明确。

## 当前候选：待对应SHA完整回归

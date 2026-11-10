# 通用建筑与组合空间验收

> 历史资料：保留原日期与结果，不是现行指令或任务；当前信息查[项目记忆地图](../../README.md)。归档于2026-11-11。

范围：用户授权的基础建设第二阶段。唯一计划为[foundation-priorities](../../plans/foundation-priorities.md)，原owner与接口见[建筑合同](../../engineering/construction-contract.md)。起点`2e6b6a61caf11b5560c15a97f1a58cb156a7300b`，分支`codex/general-buildings`；实现`806aea3f6be9c021b53063e8a4afd869a6cd6b5f`，审查修复`392538904f34ddf505ca7a9ee3428ef9c7504965`，最终受检/已推送代码`d00bac954b69cab096d580db002fb04013fa2543`；随后仅整理Markdown。

## 上一阶段集成

用户要求先查CI并合并旧代码。CI[42375335176](https://github.com/fewnfds/reol/actions/runs/42375335176)已由`tools/ci.py status`核对完整headSha与上述起点一致，completed/success；工作区干净、main无分叉，已快进并推送main，随后才开新分支。原分支及受保护WIP/stash未删除或改写。

## 实现范围

- 定义与当前工地开局分开；13类代表性结构/家具复用同一原材料施工、实例/多格/朝向、物理事实和恢复机制。包含两种材料、多个工地/布局、自由用途标记、窗/屏风的独立空间事实。
- `SimFacilityUse`接真实操作位、桌椅关系、互斥/取消、原数量预约和有限容器取放；`SimPersonalProduction`从建成工作台读取原工艺条件，不复制配方、燃料、批次或工时。
- 耐久/防护由原建筑owner结算；损毁中断相关使用和生产，保留残骸、内容物和有限余料。清理不重复发行余料，失败候选/事务中回调不改活世界。
- 普通N营造面板支持工地切换、用途、朝向、家具使用与原生产入口。根53、区域44、施工3、设施使用1、生产2；39份绑定源文档。根52明确拒绝，原fixture只读保留。

## 定向证据

`test_building_framework`是新公共合同的主要测试owner，使用小型原owner fixture，不实例化完整Main；约1.4秒，当前108项检查。保护多格去重/朝向、独立物理事实、不同工地/材料/床、用途变更/清除、桌椅依赖、操作位冲突、真实取放/容量/回执、残骸内容、生产在制状态、原截止时间与独立恢复、恶意候选和损毁回调重入。

原施工、围合/床、屋面/天气、结构查询/变化、活动所有权、原生产及普通施工运行层按影响定向验证。首轮暴露了新面板的空工地列数、已过期的最小结构夹具，以及共同查询对未结远区的拒绝边界：分别修正有效UI状态、补齐合法新夹具，并将占位复核留在实际到场/完成边界，保留原owner与共同查询的时间合同，没有放宽门禁或退化旧断言。

实现提交`806aea3f6be9c021b53063e8a4afd869a6cd6b5f`经一次原生`gpt-6.1-sol`/custom只读静态审查，3项P2及1项P3均核实并修复：成品收取复核操作位预约并允许残骸回收；等候沿统一scope互斥且开始家具使用清理已有wait；工作台到场/结算前复核真实身体/地面占位；无效床位先做合法性检查。主owner测试增加对应反例，`test_building_framework`与普通施工运行层共162项通过；审查日志`logs/building-framework-review.txt`，未递归审查或重复启动审查者。首轮3925389完整check在1800秒超时，完成161组、最后开始`test_private_exchange`，没有完整终态，不能算通过。首个真实错误为`test_heat_topology`仍未装配新开局配置及多格字段；修正合法夹具后，原断言又指出非热家具误发环境拓扑通知。产品代码改为按定义的roof/thermal_barrier/enclosure_boundary/roof_support决定环境通知，床不触发。三组370项定向通过；完整验收改用现有4片顺序check和覆盖聚合，不提高每片超时、不删断言、不并发本机引擎。原失败日志`logs/building-framework-full-check.txt`和计时`logs/check-test-timings-1794116564133759500.jsonl`保留。最终准确SHA为d00bac，完整结果见下一节。日志均在忽略的`logs/`；局部选组不等于全游戏回归。

## 最终完整验收

准确SHA`d00bac954b69cab096d580db002fb04013fa2543`，现有4片check在本机顺序执行，每片保留原结构/导入/脚本错误、1800秒超时与退出码门禁：

| 分片 | 包装器退出码 | 包装器墙钟 | 组内计时 |
|---|---|---|---|
| 1/4 | 0 | 740.294秒 | 725.814秒 |
| 2/4 | 0 | 1184.759秒 | 1171.331秒 |
| 3/4 | 0 | 604.854秒 | 591.087秒 |
| 4/4 | 0 | 752.025秒 | 739.211秒 |

`python tools/check_test_reports.py logs/building-framework-shards-20261108 --shards 4`核对注册表、每片选择、逐组完成与总数：**250组/126290检查/0失败**，完整无遗漏。worker日志及`workers.json`、`check-test-timings-shard-*.jsonl`和`coverage-verified.txt`均保留。首次本地汇总因报告命名为shard-N而未被工具发现，按工具约定重命名后聚合通过，未重跑游戏测试或改断言。

本机顺序总墙钟约3282秒、组内合计3227.443秒，比前阶段本机样本更慢，不能由此断言GitHub性能、GPU不足或将全部差异归因本包。主代理未停止其他用户进程，未据此新增优化工程。与前阶段完整报告`logs/check-test-timings-1794055341936221000.jsonl`相比，检查数增加1188：新框架108、普通运行层5、版本边界5、脚本解析4、现有领域注册表检查各1共3；余1063来自未改`test_environment_ground_compute._drain`的有墙钟预算续算循环，最终对照与完成门禁保持。

## 普通Main与完整停开

按需脚本`tools/qa/building_framework_acceptance.gd`通过Godot AI在实际Main执行普通营造面板命令。使用原随身钱币存箱，没有发放测试库存；停掉游戏进程后，在新Main进程独立加载施工、座位使用和存箱三个在途档。每案核对完整会话checkpoint、原due_ms与完整未来SHA，全部一致；本地证据在`logs/building_framework/expected.json`、`read.json`和PNG。最终准确代码d00bac已再次完成上述三个独立进程案例，均通过，原截止分别181269、423608、607791毫秒；与修复前保存未来的SHA保持一致。最终原生运行日志`logs/buildings-d00bac-editor-20261108.log`没有SCRIPT ERROR/ERROR。

Godot4.7.2 stable、实际NVIDIA GeForce RTX3060。已观察1280×720原生画面；发现并修正营造面板被其他入口遮挡、储藏完成后随身数量/活动显示未刷新的问题。只有声明的功能与局部画面证据，不是满密度/16GB整机性能或正式美术验收。

## 边界

当前仍是原home账本和开局授权内的有界建设；完整攻击/修理、灯火燃料及室温、跨账本/嵌套/独特器物容纳、所有工艺和在制物换台未覆盖。伤害接口不等于普通攻击玩法。用途区域不是功能建筑或访问权，窗的屏障事实不意味着室外场已经隔热。

初次证据提交时，代码d00bac已推送`origin/codex/general-buildings`，同SHA的[CI42457788038](https://github.com/fewnfds/reol/actions/runs/42457788038)尚为in_progress，因此当时未合并。该记录不表示当前待验。

## 阶段整合与主线合并

2026-11-08，用户明确要求完整合并主线并盘点框架缺口。在真实整合检查点执行`python tools/ci.py status --run 42457788038 --sha d00bac954b69cab096d580db002fb04013fa2543`，返回非缓存completed/success，完整headSha相符。fetch后工作区干净、远端main无分叉，`git merge --ff-only codex/general-buildings`及`git push origin main`成功，main由2e6b6a6到`eb330ee9c38fa3a5cc72004372ddeefd70409b1e`。

d00bac到eb330ee仅10份Markdown，代码、数据、测试及工具未变；本轮阶段整合也只改Markdown，沿已有准确代码验证，不重复启动引擎、回归或模型审查。分支祖先核对中，全部已完成本地/远端开发分支均已在main历史，仅旧争环WIP未合入；该分支和命名stash完整保留。当前缺口收敛到技术总表，下一阶段范围只改原主计划，不新增平行计划。主线push的独立CI状态以BASELINE为准，不能把本run写作其精确SHA通过。

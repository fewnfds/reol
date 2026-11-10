# 共同结算内核验收

> 历史资料：保留原日期与结果，不是现行指令或任务；当前信息查[项目记忆地图](../../README.md)。归档于2026-11-11。

核对：2026-11-09。用户授权的共同结算框架横跨现有顶层领域；接口见[共同结算合同](../../engineering/settlement-contract.md)，出口归[唯一主计划](../../plans/foundation-priorities.md)。分支`codex/settlement-kernel`基于main `a4fb83a6c29e3203bf71fc1c1f950afe4906830b`；原受审提交`79d4543c532b5fc1e0a99dbd8b804b71ea6f6d38`，收尾差异受审提交`0062ac533f4256933cd948bad1d170c3ff411188`，最终生产代码`d99ac6492ad5dbe5ba1af5bcc00171b5753c28e4`、最终测试补丁提交`38606ea342f09e5aadcb50112df6620ddafbe10f`。经受检差异核对后，本机12片完整回归通过；最终测试SHA的[CI42508829722](https://github.com/fewnfds/reol/actions/runs/42508829722)已核success；后续仅Markdown，于`8cc40919599680d57e1f333f1482ebab38df7e3b`快进合入并推送main。

## 范围与来源

`SimSettlementKernel`编译阶段/依赖的稳定顺序并拒绝非法图；读取到期边界，预算不足保留同一步骤。`SimWorldSettlement`沿原规则组织40步/8阶段，原领域仲裁同刻资源和结果。runtime保留共同整数毫秒及原请求，`GameClock`不发布部分结算时刻。部分状态拒绝保存、原地恢复、已受保护行动及共同查询；帧间合法完整会话加载仍可独立候选替换，不能概括成所有加载均被禁止。

`SimFacilityUse`在真实活动工作之间按预算续算，游标和调用图是派生执行状态；原身体、实物、库存、环境响应和行动仍归原owner。当前普通写档根53、区域44不变；完整动作在途档仍可保存。其他领域的单个原子回调或内部大循环不因接入内核而自动可中断，区域内部过程仍沿原执行器；内核也不会自动实现五行、温度或伤势之间的业务规则。

依据包括[Godot处理回调](https://docs.godotengine.org/en/4.7/tutorials/scripting/idle_and_physics_processing.html)、[Godot线程安全边界](https://docs.godotengine.org/en/4.7/tutorials/performance/thread_safe_apis.html)、[SimPy时间调度](https://simpy.readthedocs.io/en/stable/topical_guides/time_and_scheduling.html)、[Factorio并行化](https://www.factorio.com/blog/post/fff-215)和[存读](https://www.factorio.com/blog/post/fff-270)。[RimWorld Multiplayer实现](https://github.com/rwmt/Multiplayer/blob/master/Source/Client/AsyncTime/AsyncTimeComp.cs)是社区源码，只作公开工程参考，不代表官方内部审计。无新增运行依赖。

## 定向验证

最终代码`d99ac6492ad5dbe5ba1af5bcc00171b5753c28e4`的时钟、建筑、灯光、物品行动、普通物品界面和玩家身体6组定向测试**782检查/0失败**，包装器退出0；日志`logs/test-20261109-012022.log`、逐组报告`logs/settlement-close-review-targeted-20261109.jsonl`，不是完整注册表回归。此前`0062ac5`对应5组712检查/0失败，证据`logs/test-20261109-004922.log`及`logs/settlement-close-targeted5-20261109.jsonl`。Python工具测试**73项通过**，结构检查321份现行文档、499脚本入口、0错误。

此前实现包5组**730检查/0失败**，证据`logs/settlement-final-targeted.txt`；纯内核反例覆盖依赖、稳定次序、动态到期、非法图、失败阻止后续步骤和10000项工作预算续算。普通时钟和家具测试验证部分边界保护、真实工作分片与不限预算的完整未来一致。

## 原生审查与修复

对实现提交`79d4543c532b5fc1e0a99dbd8b804b71ea6f6d38`执行一次Sol/custom原生只读审查。首次终端宿主错误中断，没有审查结论；使用官方resume恢复同一session `01a1bb9c-abc9-7c32-baad-5494a0c93193`，提供精确commit diff及源码后静态完成。两项P2均经核实并修复：

- 跨续算的视图变化baseline和地区通知债保留到完整时刻发布，避免先前阶段的事件变化在后续续算中丢失；成功load后清除派生观察标记。
- `SimFacilityUse.cancel`拒绝外部调用在部分结算边界绕过屏障；同类检查沿18个原领域的19个公开取消/停手入口及`RegionalSimulation.interrupt_occupation`接齐，包含撤销蓝图。内核执行中的原中断及没有共同时间接口的独立领域用法保持原合同，内部环境候选撤销不套此屏障。

修复后的`test_clock_world_commit`及`test_building_framework`共**203检查/0失败**，包装器退出码0，日志`logs/settlement-review-fixes.txt`；补齐同类取消屏障后同两组203检查再次通过，日志`logs/settlement-cancel-barriers.txt`。审查过程记录在`logs/settlement-native-review.txt`与`logs/settlement-native-review-resumed.txt`；没有另启整包审查或由审查器运行测试。

收尾提交`0062ac533f4256933cd948bad1d170c3ff411188`另作一次原生只读**差异审查**，静态完成于session `01a1bc17-accd-7e00-b6a6-c5b30b669b6b`，日志`logs/settlement-close-native-review-20261109.txt`。两项P2均已核实并由`d99ac6492ad5dbe5ba1af5bcc00171b5753c28e4`修复：延迟`_draw`可能错过完整边界的缓存采集，改为公共`GameClock`发布时同步采集、绘制只回放；pending/FAILED时停止反馈被吞，改为服务/引息的notice独立更新，并对鸟身/残识事实加guard。首个`test_clock_world_commit`修复定向**127检查/0失败**、包装器退出0，证据`logs/settlement-close-review-clock-20261109.jsonl`及`logs/test-20261109-011802.log`；未重复审查整个分支。

## 原生Main、完整停开及性能样本

审查修复代码`d99ac6492ad5dbe5ba1af5bcc00171b5753c28e4`在Godot **4.7.2 stable**、Godot AI **4.4.1**及NVIDIA GeForce RTX 3060原生复验。预算1与不限预算的完整未来一致；结清保存checkpoint、推进5000毫秒后，完全停止游戏进程并重启独立载入，checkpoint `ac5955affae9a0f9b436ecb27db9c51d2bcc516546a9a7b898126fea2d1e4105`及未来`6dca1aa17d52f7cc22c955b885ecf1e1496a1b3ce8af4c24d3a4de5066226d7a`一致，读档后5200毫秒，且与`0062ac5`结果相同。原生证据目录`logs/settlement_kernel_review_20261109/`，游戏正常stop、编辑器quit，日志`logs/settlement-close-review-editor-20261109.log`。

最终代码普通开局预热120帧，再用`RenderingServer.frame_post_draw`间隔测600帧：P95 **17.943ms**、P99 **18.883ms**、最小1.197ms、最大22.241ms；模拟6100毫秒、完成126个边界，结束无pending。真实施工在clock 194118、world 194119毫秒停于`facility_use`时详情/canvas保持旧投影；完成194119后两者更新且视线失效已冲刷。另测240个真实绘制帧、预算1和连续新增宿主时间，6次完整clock发布后末次clock 194419与`canvas_at_ms`一致，`coherent=true`；停止请求被拒时实际Label即时可见。1280×720部分施工和连续欠算画面均已观察。

这是含渲染和帧节奏的普通开局短样本，时长会波动，并非内核CPU耗时、密集世界或全项目16GB/目标规模验收。此前`0062ac5`的独立停开、施工发布和600帧P95 15.415ms/P99 15.822ms证据保留于`logs/settlement_kernel_close_20261109/`；不能据短样本差异宣称性能提升。缓存型`Performance.TIME_PROCESS`重复值无效，不作为性能证据。

## 完整回归与CI

CI已从4片增加到12片以缩短并行等待，各片仍执行结构检查、导入、现有测试及错误/超时/退出码门禁，完成后聚合整个相同注册表。工具测试覆盖完整聚合及漏片拒绝；测试中故意制造的错误和超时输出不代表产品失败。按上次本机250组完整报告加本轮新组重新按现行注册顺序取模估算，本次4片最慢约1026秒、12片最慢约479秒，均是组内模拟耗时，不包括GitHub排队、checkout、安装和导入；新增组也会改变分配。CI42508829722已实际完成12worker并行：各job108–202秒、聚合5秒，run创建至更新213秒。下载的12份报告再次核251组/125351检查/0失败，证据`logs/actions-node24-upgrade-20261109/settlement-ci-artifacts/`及`settlement-ci-jobs.json`；这是该次实际样本。本机验收仍串行执行。

本机按最终生产代码`d99ac6492ad5dbe5ba1af5bcc00171b5753c28e4`和测试提交`38606ea342f09e5aadcb50112df6620ddafbe10f`完成12片顺序check：**251组/125351检查/0失败**，12个包装器均退出0，覆盖聚合退出0。各片墙钟秒数依次为320.192、636.872、460.935、110.703、93.504、148.873、107.031、89.245、118.762、97.506、116.005、110.744，成功worker合计2410.372秒；该本机顺序结果不等于GitHub并行墙钟。与建筑基线相比，未改`test_environment_ground_compute`的墙钟预算续算断言10053→8992（少1061次）；其固定对照/完成门禁保持，其他差异来自新增内核及接缝检查，逐组覆盖未减少。该计数变动机制已有[测试成本证据](20261107_test_optimization.md)。最终证据目录`logs/settlement-close-delivery-full-20261109/`；manifest的最终HEAD为完整`38606ea342f09e5aadcb50112df6620ddafbe10f`，1554个输入digest前后一致，值`a68d007355a5c762a88fe88e7a5005cfb5dfb553329e1a1dc52176b4937dee8f`。

复用1–8片前逐项核对Git差异路径和分片选择：1–3片受检`d99ac6`至`6200542`仅有两个不在这些片、也不被其依赖的suite变化；重跑第4片受检`f35b7df`至`6200542`仅有未被该片选择的terrain suite变化；`6200542`至最终`38606ea`仅改第9片suite。生产代码、共同fixture及完整注册表一致，metadata保留每片原SHA、差异路径、digest和包装器退出；第9片按最终代码全重跑。没有混入旧`68fa8`或`0062ac5`产品版本。旧主线[CI42473540525](https://github.com/fewnfds/reol/actions/runs/42473540525)对应`eb330ee9c38fa3a5cc72004372ddeefd70409b1e`，已核completed/success，仅证明该主线SHA。

## 完整回归首错与测试调用合同

`b29385c`首轮第1片失败于`test_geographic_content`假定一次`GameClock.advance_msec(62347)`即完成，实际预算正确保留欠算；改为沿同一请求续算并保留整世界未来断言。长跨度领域/存读fixture明确设置无界host工作预算，专项时钟测试仍使用预算1；重建Main后存读fixture重新设置hostpolicy。地理定向96/0、存读224/0，首错及存读日志分别在`logs/settlement-kernel-shards-20261108/`与`logs/settlement-persistence-fixture.txt`。产品默认4096、业务规则和存档未因测试适配而改变。

`d99ac6`第4片20组通过、1组失败，首错`test_field_opportunity_absence`长跨度用例漏设host预算；`f35b7df1763c7199e284e1e81de5441aa6856504`仅补该suite两次Main host预算，定向8/0且第4片全重跑退出0。原失败日志`logs/settlement-close-reviewed-full-20261109/worker-4.txt`及定向日志`logs/settlement-close-absence-fixture-20261109.jsonl`保留。临时编排读取日志遇GBK编码错误，保留worker首错并改用UTF-8。

随后静态核查发现`test_terrain_edits._test_artifact_contact`的分钟取放子案例有同类遗漏，`62005423faf194a886e979af8ef6f9c834bbf206`仅补其host预算，定向66检查/0失败、包装器退出0，证据`logs/settlement-close-terrain-fixture-20261109.jsonl`与`logs/test-20261109-015236.log`。其他terrain短时与故意pending场景、产品默认预算和原断言均不变。

`6200542`第9片20组通过、1组失败、1554检查：`test_workplace_runtime`旧断言要求`fog.visibility_updated`直连`queue_redraw`，与`d99ac6`完整边界同步capture入口不符。`38606ea342f09e5aadcb50112df6620ddafbe10f`只修改该suite，实际emit visibility后核两个room的`canvas_at_ms`等于公共clock；定向65检查/0失败、包装器退出0，证据`logs/settlement-close-workplace-visibility-20261109.jsonl`与`logs/test-20261109-020300.log`。产品代码未改。

## 旧版本用户暂停检查点

测试fixture提交`68fa8d38c5dbafdb13974d42f4dcbb527dc4ede6`的旧12片顺序check在用户暂停时只完成1–3片，证据及原进程终态在`logs/settlement-kernel-shards-final-20261108/`。其后生产代码变化，这些旧片未混入最终结果。另`0062ac533f4256933cd948bad1d170c3ff411188`回归在确认差异审查问题后主动中止，证据`logs/settlement-close-full-20261109/interrupted-for-review.json`，也不算完整通过。

## 专项问题与收尾验证

2026-11-08晚用户授权架构/流程审视。以`12f93f5`为静态基准发现普通停止可绕过部分结算屏障、施工signal可让视图提前读到局部状态、FAILED可能被宿主重复续算；当前收尾代码已分别接入以下行为：

- `WorldContinuityRuntime.stop_player_action()`对外返回受理结果，相关UI按回执提示；部分边界拒绝外部停止，合法内部中断保留。
- `RegionalSimulation`缓存`action_finished`直到完整边界；域内索引通知仍同步。`CommittedWorldCanvas`只缓存有限可见绘图参数，部分结算回放旧投影，施工视线失效、Fog和灯光延后呈现更新。上节真实施工样本同时检查旧画面、详情及结清后的刷新，不只检查时钟。
- `SimSettlementKernel.has_failed()`区分失败终态和普通预算欠算，runtime暂停、展示原因且不重复续算；帧间合法完整会话可独立校验候选并替换失败世界，坏候选不改活世界。

`tools/godot.py check`的import失败已改为快速失败，不再继续启动测试；Python反例保护这一错误路径。覆盖聚合只核注册表与覆盖，不验证代码身份；本机必须另记受检版本和各worker退出，不能混用旧版分片。

收尾定向验证首次因测试夹具工地坐标错误且未早退导致240秒超时；下一尝试选到固定运粮路上，施工完成合法拒绝。最终改用普通入口可用且不占路线的格，产品断言未放宽。原生QA探针调试还曾因`main._player`属性错误和暂停时请求产生eval失败；修正辅助脚本并重新启动后，前述停开/发布样本通过。这些是夹具和探针问题，不能记为产品运行失败，相关本地日志保留。

`0062ac5`的收尾差异审查及`d99ac6`修复详见上文。规模仍是独立限制：工作预算按工作项而非墙钟计数，地区前置推进与多数原子回调未受内部预算；库存`operations`与认识`events`可能长期增长。密集联合负载需验证边界延迟、积压、命令/保存等待及存档增长，不能删减幂等记录或认识来源凑性能。

# 共同结算内核验收

范围：用户授权的共同结算框架，横跨现有顶层领域；现行接口和算法见[共同结算合同](../engineering/settlement-contract.md)，建设依赖仍归[唯一主计划](../plans/foundation-priorities.md)。工作分支`codex/settlement-kernel`基于main `a4fb83a6c29e3203bf71fc1c1f950afe4906830b`。实现与受审提交为`79d4543c532b5fc1e0a99dbd8b804b71ea6f6d38`，审查后最终修复代码为`b29385c30dc72e8942eef803d781e526e4093986`；完整回归正在运行，推送CI尚待完成，不能用前序建筑代码的通过冒充。

## 范围与来源

`SimSettlementKernel`装配阶段、声明依赖并编译稳定顺序，拒绝未知依赖、倒置和环；调用实际到期边界，预算不足时保留同一阶段/步骤。`SimWorldSettlement`沿既有同刻规则组织40个步骤、8个阶段；原领域负责同刻资源争用和规则结果。`RegionalSimulation`和普通runtime保留共同整数毫秒及原请求，不把部分结算时刻发布给`GameClock`监听者。部分状态拒绝保存、加载、受管行动和共同对象查询。

`SimFacilityUse`在真实活动工作之间按预算续算，游标和调用图是派生执行状态；原身体、实物、库存、环境响应和行动仍归原owner。当前普通写档根53、区域44不变；完整动作在途档仍可保存。其他领域的单个原子回调或内部大循环不因接入内核而自动可中断，区域内部过程仍沿原执行器；内核也不会自动实现五行、温度或伤势之间的业务规则。

依据包括[Godot处理回调](https://docs.godotengine.org/en/4.7/tutorials/scripting/idle_and_physics_processing.html)、[Godot线程安全边界](https://docs.godotengine.org/en/4.7/tutorials/performance/thread_safe_apis.html)、[SimPy时间调度](https://simpy.readthedocs.io/en/stable/topical_guides/time_and_scheduling.html)、[Factorio并行化](https://www.factorio.com/blog/post/fff-215)和[存读](https://www.factorio.com/blog/post/fff-270)。[RimWorld Multiplayer实现](https://github.com/rwmt/Multiplayer/blob/master/Source/Client/AsyncTime/AsyncTimeComp.cs)是社区源码，只作公开工程参考，不代表官方内部审计。无新增运行依赖。

## 定向验证

实现提交前的工作区运行`python tools/godot.py test --suite test_settlement_kernel --suite test_clock_world_commit --suite test_building_framework --suite test_conflicts --suite test_world_field_save_boundary --test-timeout 180 --timing-report logs/settlement-final-targeted.jsonl`，5组**730检查/0失败**；包装器退出码0，脚本错误门禁通过，日志`logs/settlement-final-targeted.txt`。这些组分别保护内核顺序/失效计划/续算、真实时钟和身体的部分边界、家具两个真实工作项、原战斗和环境存读合同；不是完整注册表回归。

纯内核反例覆盖无依赖稳定次序、动态到期、注册后不可改计划、依赖环/未知或倒置、失败阻止后续步骤、10000项工作预算回执及效果不重算。普通时钟测试验证预算1使公开时钟停留、部分边界拒绝外部行动/共同查询和存读，续算结果与不限预算的身体、路线及整个世界未来一致；建筑测试验证实际在两个家具工作间暂停并与不限预算世界快照一致。

## 原生审查与修复

对实现提交`79d4543c532b5fc1e0a99dbd8b804b71ea6f6d38`执行一次Sol/custom原生只读审查。首次终端宿主错误中断，没有审查结论；使用官方resume恢复同一session `01a1bb9c-abc9-7c32-baad-5494a0c93193`，提供精确commit diff及源码后静态完成。两项P2均经核实并修复：

- 跨续算的视图变化baseline和地区通知债保留到完整时刻发布，避免先前阶段的事件变化在后续续算中丢失；成功load后清除派生观察标记。
- `SimFacilityUse.cancel`拒绝外部调用在部分结算边界绕过屏障；同类检查沿18个原领域的19个公开取消/停手入口及`RegionalSimulation.interrupt_occupation`接齐，包含撤销蓝图。内核执行中的原中断及没有共同时间接口的独立领域用法保持原合同，内部环境候选撤销不套此屏障。

修复后的`test_clock_world_commit`及`test_building_framework`共**203检查/0失败**，包装器退出码0，日志`logs/settlement-review-fixes.txt`；补齐同类取消屏障后同两组203检查再次通过，日志`logs/settlement-cancel-barriers.txt`。审查过程记录在`logs/settlement-native-review.txt`与`logs/settlement-native-review-resumed.txt`；没有另启整包审查或由审查器运行测试。

## 原生Main、完整停开及性能样本

最终修复代码`b29385c30dc72e8942eef803d781e526e4093986`使用Godot **4.7.2 stable**、Godot AI **4.4.1**，实际NVIDIA GeForce RTX 3060。通过`tools/qa/settlement_kernel_acceptance.gd`在普通Main使用原世界及原身体，预算1暂停于`previous:health`，部分状态拒绝快照；跨实际帧续算后的完整世界SHA与从相同起点不限预算结果一致。结清后保存checkpoint，再推进5000毫秒得到未来SHA；完整停止游戏进程、重新启动Main并独立载入后，checkpoint与完整未来均一致，读档后时间为5200毫秒，也与修复前的未来SHA一致。证据在忽略目录`logs/settlement_kernel/expected.json`、`read.json`及`tested_version.json`，普通1280×720画面已观察；游戏与编辑器运行错误为0，原有编译器警告不计作运行错误，编辑器日志为`logs/settlement-final-editor.log`。

同一修复代码重新启动后的普通开局，先预热120帧，再使用`RenderingServer.frame_post_draw`之间的真实时间间隔测600帧：P95 **15.126ms**、P99 **15.529ms**、最小1.269ms、最大16.11ms；该样本推进模拟5000毫秒、完成100个边界，结束时没有待结算阶段。结果见`logs/settlement_kernel/performance.json`。这是含渲染与帧节奏的短样本，并非内核的CPU耗时、密集世界或全项目16GB/目标规模验收。旧的修复前P95 17.348ms样本保留在`logs/settlement_kernel/before_review_fixes/`作为历史记录，两个短样本不能据此宣称性能提升。先前使用缓存型`Performance.TIME_PROCESS`重复值的结果无效，不作为性能证据。

## CI分片与待验

CI已从4片增加到12片以缩短并行等待，各片仍执行结构检查、导入、现有测试及错误/超时/退出码门禁，完成后聚合整个相同注册表。Python完整工具测试72项通过，覆盖聚合完整与漏片反例通过；测试中故意制造的错误和超时输出不代表产品失败。按上次本机250组完整报告加本轮新组重新按现行注册顺序取模估算，本次4片最慢约1026秒、12片最慢约479秒，均是组内模拟耗时，不包括GitHub排队、checkout、安装和导入；新增组也会改变分配。新配置的GitHub真实墙钟、并发可用性及最终SHA均待验证；本机验收仍串行执行，避免本机并发引擎。

最终生产代码`b29385c30dc72e8942eef803d781e526e4093986`的首次check未通过；测试fixture适配后将固定受检SHA，核每片包装器退出/日志门禁并聚合覆盖，结果由主代理更新本页与[BASELINE](../status/baseline.md)。旧主线[CI42473540525](https://github.com/fewnfds/reol/actions/runs/42473540525)对应`eb330ee9c38fa3a5cc72004372ddeefd70409b1e`，已核completed/success，仅证明该主线SHA。

## 完整回归首错与测试调用合同

`b29385c`首轮12片顺序check在第1片完成21组、其中20通过/1失败、2175检查，包装器退出1，269.198秒；失败为`test_geographic_content`假定`GameClock.advance_msec(62347)`一次调用完成，实际预算正确保留请求而已结算28000毫秒。未运行后续片；报告与日志在`logs/settlement-kernel-shards-20261108/`。一次性编排脚本读取失败日志时遇到编码错误，但worker原退出与首个断言失败均保留。

地理案例改为沿同一GameClock请求有界续算，保留原完整时刻与整世界未来断言并加欠算完成门禁，96检查/0失败。原长跨度领域/存读fixture明确设置无界host工作预算，专项共同时间测试仍显式预算1；能力测试不再直接调用runtime跳过GameClock。产品默认4096、业务规则和存档不因测试调整改变；最终仍须全部注册表验收。

受影响长跨度fixture定向9组先8组通过、存读组因重建Main后未重新设测试预算失败；补齐替换场景hostpolicy后`test_world_persistence`224检查/0失败，包装器退出0，日志`logs/settlement-persistence-fixture.txt`。不更改生产预算或用空快照比较代替完整未来。

## 用户暂停检查点

测试fixture最终提交`68fa8d38c5dbafdb13974d42f4dcbb527dc4ede6`；相对`b29385c`只改测试hostpolicy/同请求续算与Markdown，生产代码一致。12片顺序check的1/12和2/12包装器退出均0，墙钟分别356.842秒、557.753秒。用户在第3片运行时明确要求暂停，主代理停止只负责后续分片的协调进程，保留当前worker自然结束；未启动4–12片。证据目录`logs/settlement-kernel-shards-final-20261108/`，第3片随后自然完成21组/1577检查/0失败，包装器退出0；`pause-boundary.json`保留原进程终态。三个报告均有完整run_finished，尚缺4–12片。具体恢复入口在HANDOFF登记。当前不是完整回归通过，也尚未推送本分支。

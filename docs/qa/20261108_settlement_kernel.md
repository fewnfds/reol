# 共同结算内核验收

范围：用户授权的共同结算框架，横跨现有顶层领域；现行接口和算法见[共同结算合同](../engineering/settlement-contract.md)，建设依赖仍归[唯一主计划](../plans/foundation-priorities.md)。工作分支`codex/settlement-kernel`基于main `a4fb83a6c29e3203bf71fc1c1f950afe4906830b`。本记录目前描述提交前工作区的实测；最终代码SHA、原生审查、完整回归和推送CI尚待完成，不能用前序建筑代码的通过冒充。

## 范围与来源

`SimSettlementKernel`装配阶段、声明依赖并编译稳定顺序，拒绝未知依赖、倒置和环；调用实际到期边界，预算不足时保留同一阶段/步骤。`SimWorldSettlement`沿既有同刻规则组织40个步骤、8个阶段；原领域负责同刻资源争用和规则结果。`RegionalSimulation`和普通runtime保留共同整数毫秒及原请求，不把部分结算时刻发布给`GameClock`监听者。部分状态拒绝保存、加载、受管行动和共同对象查询。

`SimFacilityUse`在真实活动工作之间按预算续算，游标和调用图是派生执行状态；原身体、实物、库存、环境响应和行动仍归原owner。当前普通写档根53、区域44不变；完整动作在途档仍可保存。其他领域的单个原子回调或内部大循环不因接入内核而自动可中断，区域内部过程仍沿原执行器；内核也不会自动实现五行、温度或伤势之间的业务规则。

依据包括[Godot处理回调](https://docs.godotengine.org/en/4.7/tutorials/scripting/idle_and_physics_processing.html)、[Godot线程安全边界](https://docs.godotengine.org/en/4.7/tutorials/performance/thread_safe_apis.html)、[SimPy时间调度](https://simpy.readthedocs.io/en/stable/topical_guides/time_and_scheduling.html)、[Factorio并行化](https://www.factorio.com/blog/post/fff-215)和[存读](https://www.factorio.com/blog/post/fff-270)。[RimWorld Multiplayer实现](https://github.com/rwmt/Multiplayer/blob/master/Source/Client/AsyncTime/AsyncTimeComp.cs)是社区源码，只作公开工程参考，不代表官方内部审计。无新增运行依赖。

## 定向验证

工作区运行`python tools/godot.py test --suite test_settlement_kernel --suite test_clock_world_commit --suite test_building_framework --suite test_conflicts --suite test_world_field_save_boundary --test-timeout 180 --timing-report logs/settlement-final-targeted.jsonl`，5组**730检查/0失败**；包装器退出码0，脚本错误门禁通过，日志`logs/settlement-final-targeted.txt`。这些组分别保护内核顺序/失效计划/续算、真实时钟和身体的部分边界、家具两个真实工作项、原战斗和环境存读合同；不是完整注册表回归。

纯内核反例覆盖无依赖稳定次序、动态到期、注册后不可改计划、依赖环/未知或倒置、失败阻止后续步骤、10000项工作预算回执及效果不重算。普通时钟测试验证预算1使公开时钟停留、部分边界拒绝外部行动/共同查询和存读，续算结果与不限预算的身体、路线及整个世界未来一致；建筑测试验证实际在两个家具工作间暂停并与不限预算世界快照一致。

## 原生Main、完整停开及性能样本

Godot **4.7.2 stable**、Godot AI **4.4.1**，实际NVIDIA GeForce RTX 3060。通过`tools/qa/settlement_kernel_acceptance.gd`在普通Main使用原世界及原身体，预算1暂停于`previous:health`，部分状态拒绝快照；跨实际帧续算后的完整世界SHA与从相同起点不限预算结果一致。结清后保存checkpoint，再推进5000毫秒得到未来SHA；完整停止游戏进程、重新启动Main并独立载入后，checkpoint与完整未来均一致，读档后时间为5200毫秒。证据在忽略目录`logs/settlement_kernel/expected.json`与`read.json`，普通1280×720画面已观察，游戏日志无运行错误。

同机重新启动后的普通开局，先预热120帧，再使用`RenderingServer.frame_post_draw`之间的真实时间间隔测600帧：P95 **17.348ms**、P99 **21.257ms**、最小1.586ms、最大35.38ms；该样本推进模拟5800毫秒、完成145个边界，结束时没有待结算阶段。结果见`logs/settlement_kernel/performance.json`。这是含渲染与帧节奏的短样本，并非内核的CPU耗时、密集世界或全项目16GB/目标规模验收。先前使用缓存型`Performance.TIME_PROCESS`重复值的结果无效，不作为性能证据。

## CI分片与待验

CI从4片增加到12片以缩短并行等待，各片仍执行结构检查、导入、现有测试及错误/超时/退出码门禁，完成后聚合整个相同注册表。按上次本机250组完整报告加本轮新组重新按现行注册顺序取模估算，本次4片最慢约1026秒、12片最慢约479秒，均是组内模拟耗时，不包括GitHub排队、checkout、安装和导入；新增组也会改变分配。新配置的GitHub真实墙钟、并发可用性及最终SHA均待验证；本机验收仍串行执行，避免本机并发引擎。

本包尚需一次原生只读审查、有效问题修复及最终代码完整回归/覆盖聚合；相应证据和准确SHA完成后由主代理更新本页与[BASELINE](../status/baseline.md)。旧主线[CI42473540525](https://github.com/fewnfds/reol/actions/runs/42473540525)对应`eb330ee9c38fa3a5cc72004372ddeefd70409b1e`，已核completed/success，仅证明该主线SHA。

# 共同时间的运行流速与过载政策

> 实现参考：描述代码接口及消费者假设，可随重构更新；稳定边界见constraints，范围按当前用户任务。

本合同属于共同运行框架，入口为[GameClock](../../scripts/autoload/game_clock.gd)、[ReolSimulationPacing](../../scripts/runtime/simulation_pacing.gd)及[结算内核](settlement-contract.md)。世界政策见[世界与时间](../../design/rules/world.md)，建设出口只见[主计划](../plans/foundation-priorities.md)，版本与验证归BASELINE/HANDOFF。

## 时间与所有权

玩家的`speed`保留1/2/4选择；宿主的`pacing.rate`根据本机计算成本调整，正常实时准入速度为二者乘积。身体、环境、攻击/治疗、生产等仍读取同一整数毫秒，不按机器快慢改变业务事件时刻、阶段、同刻仲裁或随机顺序。相同初始状态、规则、随机状态及已受理的逻辑输入序列，在相同游戏时刻应有相同结果；相同现实秒按键不等于相同已受理模拟输入。

`_process`用`Time.get_ticks_usec()`采样宿主时间和本次时钟调用成本，不使用Godot可能被缩放/限制的`delta`。`advance_frame(real_seconds)`是无墙钟测量的确定性驱动入口，沿相同准入和推进代码执行；规则fixture用它或显式`advance_msec`，不伪造引擎回调。项目不通过`Engine.time_scale`管理世界流速。

## 有限准入与反馈

- 新的自动推进最多保留所选倍率下250ms现实时间对应的游戏时间前瞻；已有未结算工作占用这个额度，满额后不再新增。部分阶段保留原时刻/步骤，不能跳过后续事件。一次长卡顿也不生成数秒或数小时的追赶目标。
- 超额但尚未准入的现实时间是主动放慢，不是丢失模拟工作。负载恢复后继续原时刻；已准入欠算、显式请求、等候目标及恢复自存档的旧欠算仍须完成，不能截断到新限额。
- 根据已提交游戏毫秒及其累计CPU成本估算吞吐；未发布阶段的成本计入后续完整结果。在250ms游戏时间尺度上分别衰减累计工作量与累计时长，再计算成本比值；不取单次片段比值的峰值，避免1ms因果切分把固定发布成本误判成持续过载。启动时以60Hz估算，此后按实际回调间隔的有界平滑值计算容量，每帧模拟预算6ms，留15%吞吐余量；一次正常让出不直接认定长期过载。
- 负载倍率最低0.01，上限1；降低立即生效，恢复每现实秒最多增加0.25。真实帧间隔采用有界平滑采样，长期低渲染频率也影响可用吞吐估计。倍率只影响未来准入，不回写已决定的事件。
- 玩家暂停不新增时间；普通暂停不消化在途推进，[保存屏障](architecture/04-persistence.md#保存请求与安全边界)可结清已受理工作而保留暂停状态；恢复和读档重设宿主采样基点。后台仍获得回调时沿同一政策运行，失去调度/休眠形成的长间隔只有限准入；不模拟离线世界。`Engine.time_scale`、系统日期和后台等待不成为另一份业务时间。

## 合作式执行预算

每真实帧由`GameClock`建立6ms截止时刻。`frame_budget_exhausted()`沿`WorldContinuityRuntime`、`RegionalSimulation.advance_to_ms`及`SimSettlementKernel.resume(work_budget, should_yield)`传入，在新边界/原领域步骤之间返回PENDING，保留原游标。无有效宿主回调时，显式工具推进仍使用原事件数/工作项预算。

时间预算不会修改调用图或业务输入。已完成步骤不重算，未完成步骤先完成再进入下一时刻；外部命令和公共画面仍遵守完整边界。截止时间已经耗尽且世界pending时，runtime返回旧公共时间，不读取部分身体投影。

预算领域可通过`SimSettlementKernel.should_yield_work()`复用本次resume的宿主截止条件，在自身有界工作项之间检查。环境到期响应按16格工作项保留原批处理handle和区间游标，完成后才放行健康等消费者；无宿主截止条件时仍沿同一过程结清。旧原子回调、地区前置推进及未拆分的大循环不能被中途抢占，单个原子步骤仍可超过6ms。该值是合作式预算，不是硬实时承诺；GPU过载、同步文件操作也不会被调速自动消除。

## 呈现、存读和诊断

`ReolMotionPresentation`在完整公共时间发布时接收人物的真实坐标，在相邻已提交目标之间作一个50ms规则步长度的显示过渡，`view_delta_seconds()`随共同负载倍率放慢。`Pawn`以原生节点变换显示插值位置并保留Godot绘图指令；玩家绘图与选择中心仍读取`presentation_position()`，镜头跟随同一显示点。场景节点都不拥有身体真值。新边界pending时最多完成上一条已接受显示段，不能读取/预测半结算身体。暂停冻结显示推进，首次出现、重新可见、同毫秒重定位及读档立即重置显示点；重复发布同一目标不重启过渡。UI、鼠标及暂停沿宿主继续响应，普通HUD显示“缓行”及准入倍率，按钮保留玩家选择。F3提供请求/有效倍率、已准入欠算、本次及最大时钟调用耗时；指标有界，不保存全历史。

时钟七字段格式保持，当前联合根/区域版本见[兼容政策](compatibility.md)。`frame_debt_ms`继续保存已准入时间和余数；机器成本估计、截止时刻和负载倍率是宿主派生状态，恢复后重新采样。部分阶段仍不能捕获新快照；完整合法会话替换与失败恢复沿原合同。

## 依据与验证边界

[Fix Your Timestep](https://gafferongames.com/post/fix_your_timestep/)说明固定步、显示分离与追赶导致的spiral of death，以及限制每帧工作后允许降速的取舍。[Godot Node](https://docs.godotengine.org/en/4.7/classes/class_node.html#class-node-private-method-process)说明`delta`的限制，[Time](https://docs.godotengine.org/en/4.7/classes/class_time.html#class-time-method-get-ticks-usec)提供单调宿主计时；这些只支持采用的原理，不证明Reol已达到整机规模。

`test_simulation_pacing`主要保护有限准入、已有工作保留、恢复斜率、宿主状态不入档，以及简化治疗/攻击在不同倍率和预算下的同未来。简化生命值不代表Reol已实现该药物玩法。`test_settlement_kernel`保护宿主让出不改阶段，`test_clock_world_commit`保护实际世界/身体/发布接缝；普通渲染、独立停开和声明负载以QA证据为准。

# 代码归属

U1-b1的`sim/site_affairs.gd`与`site_affair_schema.gd`保存有限地方安排、具名许可与归位核验依据；原`SpiritSources`同步通知原job开始/终态，不复制源量或收益。`SettlementServices`复用本人`site_loan/service`办理、管事本人`site_return/inspect→register`往返；申请者与执行者显式分开，不新增身体执行器。原C请求门面提供询问安排/申请借源/请求验还，纯查询不写个人知识，结果通过再次当面请求听取。旧档仅迁空，普通新局显式装配；事实/声明/亲见/登记范围见[QA](../docs/qa/20261104_source_loan.md)。

U1-a在`sim/conflicts.gd`保存有界冲突/学习与动作凭据，`conflict_space.gd`负责无状态空间判定，`conflict_schema.gd`独立校验历史；`runtime/conflict_runtime.gd`只接U/Q/E/R/X输入与有限可见绘制。木剑沿原器物域，命中伤沿原健康域，施术成本沿原灵源历史检查点；不复制位置/体力/灵力。主联合快照按精确边界/原身体排他一次提交，跨所属区仍用同一全局坐标。

U1-b0的`sim/conflict_perception.gd`为原交锋生成本人可见目标、起势和来弹线索；在实际开场与共同结算边界更新原`people.sight`的最新位置记忆。隐藏目标只支持走向最后见处，记忆过期后停止；所有场次先取线索再发起新动作。根36/区域32/交锋2显式保存`perception_since_ms`，旧档从原保存时刻启用、线索为空；历史目击校验不回查当前隐藏坐标或门墙来证明过去。实现范围和待验项见[有限感知规格](../docs/plans/conflict_perception.md)，最终构建状态只看BASELINE。

- sim/：纯模拟规则和可序列化状态；跨聚落服务放 sim/services/。
- runtime/：时钟/寻路/输入/视图适配与场景装配。
- persistence/：文件存读，不能发放奖励或改变社会规则。
- data/：定义类与内容加载；core/：小型通用坐标工具。
- world/：地形/区块/迷雾/相机；entities/：场景人物表现；ui/：可知信息和操作意图。
- autoload/：当前 GameClock；social/：尚未接入的继任原型。

`sim/world_map_data.gd`保存原固定生成器及静态地形/高度/通行查询。联合会话在RegionalSimulation持有地图，ReolWorld只借用并组合原动态阻挡、绘制区块；首次位置核验起的独立候选不得回查活视图。当前没有可变地表delta，地图拆分不升级存档格式。实施与验证见[独立地图包](../docs/plans/world_map_foundation.md)。

当前快照升级在 `persistence/session_save_schema.gd`；探索由Fog负责。库存有限认识在 `sim/stock_information.gd`，只读本人见闻/说法，实际执行仍用原库存与行动器。持续实施入口见[Goal工作包](../docs/plans/implementation_goal.md)。

`sim/embodiment.gd`只持有主体/载体引用/居留/排他通道；由RegionalSimulation装配与校验真实身体源。位置/库存/知识属于原领域，不向注册表再拷一份。人/鸟/魂已有不同短生活开局，完整生命流程仍待实现。

`sim/artifacts.gd`/`artifact_schema.gd`持有唯一器物容器引用、本人实验和实际效果；`runtime/world_objects_runtime.gd`连接局部绘制与`ui/object_inspection_panel.gd`，面板只收到获准认识。器物耗时与原生活均在共同毫秒轴，未做通用作用平台。`sim/heat_methods.gd`只存版本目录，试验/教学由原器物动作执行，掌握从个人实际事件读取；对应M手记在`runtime/heat_methods_runtime.gd`。

`sim/local_motion.gd`持有当前玩家速度/朝向/闪身阶段并读写原身体连续位置，身体节点只采集输入并在共同`GameClock.time_advanced`中投影；体力仍属于原actor。NPC与自动路线已用共同毫秒/连续段；分钟是同一时间的通知投影。当前格式/迁移只看BASELINE，真实旧档保持原格式保护跨进程接续。

main.gd 只装配和路由，不接着写玩法规则。依赖和不变量见[代码架构](../docs/ARCHITECTURE.md)。

`sim/construction.gd`/`construction_schema.gd`处理获准工地、门墙/工时、材料实际归处与原账凭证，`runtime/construction_runtime.gd`提供N施工簿/地面绘制。材料数量只在原SimInventory，身体只在原actor；世界通过阻挡查询共享结构。候选校验须用静态地形加候选自己的建筑，不能读当前活世界的墙。房间/家具与完整经营尚未实现。

当前运行入口是 [main.gd](main.gd)；本地模拟在 [village_simulation.gd](sim/village_simulation.gd)，共同时间和跨区事务在 [regional_simulation.gd](sim/regional_simulation.gd)，对应适配在 [runtime/](runtime/)。新工作从[当前路线](../docs/ROADMAP.md)与[交接](../docs/HANDOFF.md)开始，不重做旧服务包。

移动 GDScript 时一并移动 `.gd.uid` 并更新引用；运行 `python tools/check_structure.py` 后再执行 Godot 导入和测试。第三方插件留在 addons/，不借目录整理修改其内容。

`sim/personal_production.gd`/`production_schema.gd`保存私人批次/工时与原身体任务；料/燃料/成品仍在原SimInventory容器。原生活面板制作页提交意图，公共做饭不被转成私人收益；完成后仍实际取回，过程接原精力与共同时间。

`sim/budgeted_labor.gd`/`labor_schema.gd`只存现金条款/所知来源、原生尝试与结算。原村落的劳动开始/结束回调关联actor.active，不新增执行器；专款/工资仍是原库存转移，claim_wage复用原耗时服务，同次原工作贡献为零。C负责当面承接/验收，工钱页提供本人状态/续做/放弃。

`sim/capability_conversation.gd`是无状态通信协作者，查询本人日常/经历/学习/任职后复用原社会意愿，原私下事件保存自述。跨聚落用已有services.social；C重开只回想本人旧话，候选核对内容/决定双向引用，不授予技能/权限。

`sim/autonomous_livelihood.gd`只存有限口粮目的的公共寻找/退避；村落需求与承诺后预留决策，区域同刻再调用原交谈、预算劳动、验收和买卖。不复制身体、库存、钱包或任职；原公开动作呈现进程。

`sim/clothing.gd`/`clothing_schema.gd`保存唯一衣物/保管引用/穿法、原身体耗时事务与湿润，数量不又加入库存。原天气按分钟更新、村落只读回调计原精力；`runtime/clothing_runtime.gd`提供V本人衣着/近旁表层与纸娃娃，`entities/pawn_visuals.gd`只绘制原穿法投影。衣着不授机构权限。

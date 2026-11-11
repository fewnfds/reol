# 稀疏执行索引：接入指南

> 实现参考：描述代码接口及消费者假设，可随重构更新；稳定边界见constraints，范围按当前用户任务。

本页为现存Demo的实现参考；重构目标由[执行规格](../specs/world-engine/execution.md)定义。逻辑职责/有效规则不绑定下列class、数据结构或调用链。

代码入口：[SimParticipationIndex](../../scripts/sim/execution/participation_index.gd)。它是由原领域持有的可重建索引，记录哪些对象参与该领域、哪些工作已到期或因依赖变化待处理。对象的身体、位置、器物、知识、过程及共同时间仍归原所有者；索引不负责执行规则、不调用业务回调，也不另造时钟、实体表或事件总线。

**接入状态：** 普通环境和健康领域已接入并有[对应验证](../archive/qa/20261107_sparse_execution.md)；其他旧域不自动迁入。索引由原owner选择工作，[共同结算内核](settlement-contract.md)安排跨域阶段，两者不复制彼此状态。集成与范围只查[功能范围](../status/features.md)。

## 原生行动的截止点复用

`VillageSimulation`保留原行动、连续需求和观察所有权。普通世界通过`set_boundary_revision_provider()`声明可观察的导航/控制依赖：`WorldContinuityRuntime`监听实际阻碍；`SimEmbodiment.native_motion_revision`只追踪村民身份及行动、移动控制的变化。新增非村民的原登记和通信授权不影响这些截止点；整个登记册被替换时保守失效。世界绑定的控制变更在写入前仍按旧控制条件补齐对应地区，独立候选不带此宿主hook。大体型开始/结束整段占地也沿原空间signal通知，不等中心跨格。只有这条接缝完整时才复用每个人的绝对截止点；未提供依赖通知的独立Callable走保守查询。

开始/取消/完成行动及身体重定位使对应截止点失效；跨域改动调用原`RegionalSimulation.invalidate_region(region_id, actor_id)`；明确单个人物的命令可只使该人物失效，空actor参数保守处理全区，合并本边界的重复失效，在下一次调度前重算。`advance_region_to_world(region)`只推进该地区已到期行动和后果；同一毫秒不重跑。`synchronize_region()`在此基础上补齐指定人物或全体连续状态，实际需要可写身体的操作继续显式同步。恢复时清空截止点并重绑通知；索引不入档，不复制路径或成为另一份行动计划。派生截止点复用`SimParticipationIndex`，路径与动作仍由原执行器持有，不另存第二份行动计划。

普通行旅的格位同步/路线换段、`SimActionContract`占用与释放、已接入的服务结束/施法/命中/衣物负担变化都携带实际actor，只使当事人的截止点失效；这些通知不等于地形或所有人的控制发生变化。库存认识的输入版本、真实导航/控制修订及未知范围操作继续按原依赖处理，不把整个世界的失效一律改成单人。衣物天气脉冲仍保留原同步顺序，此处只收窄其失效通知。

开局零时刻的身体已同步、截止点尚未建立时，宿主可在两地准备之间让出一帧。已算好的原索引照常响应失效；等所有地区可用才选下一逻辑时刻。此让出不执行新区间，不改变任何地区的规则顺序。运行中的控制或阻碍变化可能涉及原行动收敛，仍走原边界，不以这条开局入口拆开。

`VillageSimulation`的原生截止点已复用`SimParticipationIndex`的可更新最小堆，只重算到期/失效人物，并按原ID顺序结算同刻候选。动作状态仍归原执行器，索引只持原引用和截止点，恢复重建。

普通runtime在导航/控制通知和连续输入变更接缝绑定后调用`set_sparse_actor_projection(true)`。每人保留可丢弃的已积分时刻；无跨格/到期/显式同步时，不随他人跨格反复积分。独立/不透明Callable保持原提前积分顺序，不猜测其捕获输入不变。

`actors`与`actor_state(id)`只返回原记录，不推进需求、移动、锚点或通知；记录中的连续值属于该人物最近积分时刻，不承诺与地区时刻相等。需要当前可写身体的规则入口显式调用`synchronize_actor(id)`；完整存档捕获、全体输入率变更用`synchronize_actors()`补齐原记录。画面发布不补算身体，沿已受理路段纯求值。`projected_actor_position(id)`求值至本地区时刻，实体/容器位置查询复用同一路段公式，不写身体或预测未受理未来。

山兽拟占地和`SimMotionClearance`从原已受理轨迹纯求值当前格/当前短段；整路积分通过原`Timeline`定位当前段，保留对角边格、已经跨入目标格但尚未结束的段。它们不为几何查询补算全体需求，也不复制路线。野外周期观察先推进到期后果，再以投影距离保守筛候选，入围人物仍走原同步、控制/高度/遮挡和个人认识记录。库存认识、移动来源和空间订阅的精确边界继续由原参与条件负责，不因查询变纯而取消。

`VillageSimulation.observe()`仍用同域原身体已经物化的格位与距离确定见证者。只有同刻有多条事件、格范围小于逐人扫描时才共用一次格内成员采样；原身体空间变化更新同刻采样，换时刻或身体表重建。它不准备实时组合空间索引，也不要求所有人物逐格物化。`SimSocialMemory`每条客观事件只留一份；按人保存紧凑的原事件下标，转述另记即时来源及可知范围。`knows()`、`saw()`只查个人索引；`observation()`按公开/当事人范围还原一条，内容递归只读，`known_events()`返回独立副本。存档从原事件的参与者和见证名单重建直接观察，另外存转述和例外的取得顺序；恢复验证来源链。支持范围见[兼容接口](compatibility.md)，离散请求和效果派发仍归[事件合同](event-contract.md)。

原动作结算与自主筛选只取到期及失效人物，保留原ID顺序。执行中同步通知使较后ID失效时，只合并本次新增变化；较早ID与旧顺序一样留待下个边界。累计dirty集合保留给下一次截止点查询，不能每处理一人就重新枚举其全部前缀。带明确格范围的导航变化复用原路线覆盖证明，只使相交或无证明的行走人物失效；`update_native_route_geometry()`返回原`invalidate_region(region, actor)`所需ID，空ID仍代表整区。只有旧边界版本和索引均有效时才确认这次局部版本；未知范围、既有版本失配、控制或首个空间消费者变化仍保守回退全体，不依赖未声明通知的Callable。`simulation_work`的`actor_settle_checks`、`actor_decision_checks`、`actor_merge_checks`仅计诊断，不入档。

跨格仍是精确因果边界，先发布真实占地/来源移动；显示只读取完整时刻。改变衣着暴露、外部劳动或休息恢复之前，原owner先同步旧输入；`synchronize_region(region, actor)`可仅补齐被改人物，无actor参数保守补齐全体。手动运动写原身体前先补齐该人，取消/保存/加载不能抹去尚未积分的需求。新增消费者不能持有身体引用跨边界后直接读取连续值；使用纯位置求值、已发布投影或显式owner同步，新连续输入必须有变更前屏障。

服务步骤只物化实际办理人的身体。搬运的来源和目的地区先推进到共同时间，让原预约、库存和位置按原规则可读；读静态货位不补算该地区其他身体。取货、保管、交付和中断仍走原库存/服务记录，不能以只投影办理人为由提前或省略结算。

工地过程与交锋也只显式同步参与者；每次交锋步使该参与者的原截止点失效。弹道和跨区见证先用`rule_actor_position`读原受理路线；未有可靠几何证明时回退原owner同步，实际接触再修改原身体。连续几何筛选不额外积分旁观者的需求，不变更命中及见证顺序。

库存观察按原分钟、真实内容epoch及跨格变脏人物更新；观察用原受理轨迹求值当前格，不为记录个人见闻同步全体需求/路段。库存缓存基线在截止点规划之前建立，避免首次取样再废掉刚完成的规划；规划之后、首次推进之前的真实库存变化也仍走原失效。同格内容变化仍立即可见，未到现场的人不获得远区真值。世界阶段使用[结算条件](settlement-contract.md)跳过未参与领域；空闲不代表没有持续过程，连续需求、来源和远区工作仍须推进。规模声明以相应版本实测为准。

## 四种状态

一个领域通常创建一份索引，`kind` 是该领域自定的稳定 `StringName`，`id` 是领域能够解析的非空字符串引用。不同 `kind` 可以登记同一个 `id`，不会把主体复制成新实体。不要把定义模板、身体、物品数值或玩家尚未知晓的信息写入索引。

| 状态 | 作用 | 何时变化 |
|---|---|---|
| member | 具有某种能力或相关状态，可能被该领域处理 | 原所有者生成/移除、获得/失去该能力或恢复时 |
| active | 当前持续参与该领域过程的 member | 过程启停、开始/结束、资格变化 |
| due | member 下次需要领域在共同时间处理的毫秒时刻 | 原过程创建、推进、重新安排、取消 |
| dirty | member 因一个或多个依赖改变而待处理 | 原状态提交后，沿既有接口标记原因 |

这四种状态不是生命进度或游戏属性。inactive 的 member 仍可持有 due 或 dirty，以便在正确时刻唤醒；因此“当前没动作”不能用于冻结需求、伤病、天气或远区。需要连续变化的领域必须保留自己的时间锚点、输入段和阈值规则；若不能证明批算等价，就继续使用原推进方式。

## API 与数据成本

所有调用由领域在原来的共同时间阶段执行；索引方法不主动推进世界。`kind` 与 `id` 必须由原领域定义稳定语义，不能依靠全知索引推断玩家认识。

- `set_member(kind, id, present = true)`：登记或移除成员。重复登记/移除是幂等成功；移除时自动清除此成员在该 kind 的 active、dirty 和 due。无效的空 key 返回 `false`。
- `has_member(kind, id)`：查询该索引是否登记。`set_active(kind, id, active)` 只接受已登记成员；重复设置是幂等成功。
- `member_ids(kind)`、`active_ids(kind)`：返回按 ID 字典序排列的独立快照。调用者可以修改返回数组；原索引不变。领域原有的同刻顺序如果不同，必须在领域侧保持原顺序，不能用字典序悄然替代。
- `mark_dirty(kind, id, reason)`：向已登记成员合并非空原因，返回正数 revision，失败返回 `0`。每次标记产生新 revision，即使原因重复也是如此。
- `pending_dirty(kind, limit)`：按 ID 字典序返回至多 `limit` 条 `{id, revision, reasons}`，不消耗待办；`reasons` 是独立数组。
- `ack_dirty(kind, id, revision)`：只有当前 revision 与处理完成的快照相同时才清除，成功返回 `true`。后来的新变化不会被旧确认抹掉。
- `set_due(kind, id, at_ms)`：给已登记成员设置一个非负共同时间截止点；再次设置会原位更新。`cancel_due(kind, id)` 取消该截止点，已登记成员没有截止点时为幂等成功。成员未登记时返回 `false`。
- `next_due_ms(kind, fallback)`：返回最早截止点；无截止点时原样返回调用者的 `fallback`。`due_ids(kind, through_ms, limit)` 按 `(截止点, ID)` 返回不晚于该时刻的至多 `limit` 个引用，不消耗或推进任何工作。不同阶段或不同领域的同刻优先顺序仍由原执行器决定。
- `clear()`：丢弃该索引所有派生信息，不清除同一索引实例的 dirty revision 计数。`diagnostics(kind)` 给出成员、活跃、脏、到期数量及最近到期查询检查的堆节点数，仅供诊断。

成员、活跃与脏集合按 kind 分开；有变更时缓存排序后的 ID，查询返回独立快照。快照复制仍随实际集合大小增长，dirty 集合变化后的首个查询需要对该集合排序；不要声称它们是常数时间。截止点采用可更新的最小堆，重排/取消不累积旧堆项；限量 due 查询只扩展所取结果的堆前沿，不扫描全部无关成员或复制整堆。

## 新能力最小接入

下面是原领域中的示意，`_owns_subject`、`_apply_change` 等由具体领域实现；kind 和 reason 均为抽象名称，不是固定游戏玩法。

```gdscript
const Participation = preload("res://scripts/sim/execution/participation_index.gd")
const KIND: StringName = &"example_process"
var _participation := Participation.new()

func _on_subject_created(id: String) -> void:
    if _owns_subject(id) and _has_example_capability(id):
        _participation.set_member(KIND, id)
        _participation.set_active(KIND, id, _is_running(id))
        if _has_deadline(id):
            _participation.set_due(KIND, id, _deadline_ms(id))

func _on_dependency_committed(id: String) -> void:
    if _participation.has_member(KIND, id):
        _participation.mark_dirty(KIND, id, &"dependency_changed")

func _on_subject_removed(id: String) -> void:
    _participation.set_member(KIND, id, false)
```

在原共同时间阶段按预算读取候选，完成原领域工作后才确认。下面只示意 dirty；是否允许部分提交、失败后的积压和跨域同步由原领域的事务/执行合同决定。

```gdscript
func settle_changes(limit: int) -> bool:
    for row: Dictionary in _participation.pending_dirty(KIND, limit):
        var id: String = row.id
        if not _owns_subject(id) or not _apply_change(id, row.reasons):
            return false  # 未确认的待办仍在，交给原执行器处理
        _participation.ack_dirty(KIND, id, int(row.revision))
    return true
```

若 `_apply_change` 引起新的同对象失效，旧 revision 的确认会失败，新工作保持待处理。不要在处理失败前预先清空 dirty。对于 due，先以 `due_ids` 读取，领域确认本次过程已成功完成后，再由该领域按实际下一边界调用 `set_due` 或 `cancel_due`；预算不足保留其余截止点。候选只提供引用而不是锁：处理前应复核原状态、条件和截止点，避免在其他同刻工作已取消或改期后执行过期候选。不能跨有观察/消费的物理时刻随意合并。

## 生命周期与恢复

1. 内容加载时按定义判断是否有能力；只有可参与的对象进入相应 kind。定义和实例状态分开，不能按物品或角色的名字写快捷分支。
2. 从真实生成/移除、启停、穿脱/转移、受伤/结束、跨区或其他实际变更接缝更新索引。变更失败或取消时不得发布不属于原状态的索引变化。
3. 打开新局和读取**已独立校验的候选世界**时，从候选的原领域状态重建派生集合和边界；候选失败不能修改活世界。保存原始事实和在途状态，不把可重建索引当第二份真值写档。
4. 同一索引实例执行 `clear()`、删除成员并重新登记后，旧 dirty revision 无法清除新标记。若替换的是整个索引实例，必须丢弃旧实例的待办快照；不能将它们拿到新实例确认。
5. 原领域存在可直接修改的 Dictionary 时，所有正式写入入口必须接齐索引维护。没有接齐时不能把索引当唯一候选来源，也不能让测试绕过入口直接伪造状态。

索引依赖单一领域所有者协调，不提供跨线程同步；后台并行若以后需要引入，应单独设计所有权、快照和发布阶段。它不是动作预约或权限锁，仍须通过原领域检查；也不改变远区同步、同刻先后、暂停、加速及存读的既有因果规则。

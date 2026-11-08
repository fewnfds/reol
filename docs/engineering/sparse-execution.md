# 稀疏执行索引：接入指南

代码入口：[SimParticipationIndex](../../scripts/sim/execution/participation_index.gd)。它是由原领域持有的可重建索引，记录哪些对象参与该领域、哪些工作已到期或因依赖变化待处理。对象的身体、位置、器物、知识、过程及共同时间仍归原所有者；索引不负责执行规则、不调用业务回调，也不另造时钟、实体表或事件总线。

**接入状态：** 普通环境和健康领域已接入并有[对应验证](../qa/20261107_sparse_execution.md)；其他旧域不自动迁入。索引由原owner选择工作，[共同结算内核](settlement-contract.md)安排跨域阶段，两者不复制彼此状态。集成与范围只查[技术总表](../status/technical-status.md)。

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

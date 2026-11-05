# 真实地面来源的分块基础目标缓存（A2a）

`SimEnvironmentGroundCache` 是权威开发接口，服务于普通世界接管之前的环境底座。它绑定原世界，不持有第二套实物、数量、位置或时钟。输出是当前来源合成的基础目标，**没有实际温度、五行残留或移动携物场**；普通Main仍沿原冷热模型。

## 定义与计算

- 输入为已配置的`EnvironmentSourceDefinitions`；profiles与内容digest沿[A1来源合同](environment-source-query-contract.md)，不自动从磁盘补定义，不加入普通存档。
- `SimEnvironmentFieldRules.BASE_TARGET_RULE_VERSION=2`统一最近整数舍入；冷热先对绝对强度舍入再恢复符号，避免冷源向零截断的不对称。旧A1 QA继续描述旧SHA。
- 对外五行顺序木/火/土/金/水；packed内部金/木/水/火/土/热侧极值/冷侧极值。纯转换函数明确映射，净冷热为两侧max之差。热冷极值不是物品新增属性。
- A1地面静物发源仍为锚格加`floor((size-1)/2)`，偶数向左上；多格实物只贡献一源，同类堆不按数量放大。

## 接口与状态

| 接口 | 行为 |
|---|---|
| `configure(world, definitions)` | 检查原所有者、定义、共同时间和区域同步；显式分配512²索引及最多262144来源slot，进入building |
| `advance(max_work=4096, max_usec=2000)` | 按预算装配、同步待变更来源、重建已请求块；返回state/work_used/elapsed_usec/pending_sources/pending_tiles |
| `request_area(rect)` | 裁剪到地图并向外对齐16×16块；只登记请求，不同步计算全图 |
| `read_base(cell)` | building、相关来源未同步或块未完成时返回pending且不附部分值；ready才返回五行与净冷热 |
| `diagnostics()` | 当前状态、实际来源数、装配进度、待处理/缓存块、slot高水位、复用及失效次数；不是玩家观察 |
| `close()` | 解开内部绑定，释放派生数据；同一个服务可再次configure |

成功读数带`visibility=authority_only`、`live=false`、scope、游戏毫秒、定义digest及计算rule_version。查询不会推进世界或写入人物认知。world欠算/区域未同步时明确拒绝读数，不把旧值标成当前；同步后可重试。

第一次装配按16×16空间桶扫描完整占地，只有锚点所在桶登记该物，避免跨桶重复。每步处理一个有限桶查询或一条来源投影；一桶最多256件排他地面物，桶查询自身不能任意细分，耗时单独计入。来源和索引从原owner派生，不调用全世界`to_dict()`，不把历史inactive槽复制到来源库。

ready不表示所有地图块都已构建，须同时看pending_sources和pending_tiles。未请求块可以一直不建；首次读会登记该块。基础目标可丢弃重建，不可丢弃未来接入的实际环境历史。

## 失效顺序与旁路

生命周期只允许一个弱引用基础缓存绑定。成功事务在写完原物及回执后、解除内部提交状态和任何外部`committed`通知之前，直接通知缓存；不能依赖signal连接先后。耗时动作同样经过此内部接缝，再结束动作并发外部通知。

缓存同步登记from/to的原地面引用及覆盖块。独特物跨地面移动仍以原ID定位；材料拆合分别处理两堆。旧源/新源影响区取并集，不标脏两端之间的长条。正数量的既有同类堆仍是一源，可跳过几何重建；最后一份移走才撤源。最强来源离开后重新比较剩余来源，不能从max减去旧值。

相关块在来源还没同步前就不可读为ready，远处干净块可继续读。后续advance从原owner重投影并调用已有packed缓存；块完整后发布。相同引用的未处理变更可合并；处理后再次变化必须重新入队，消费前缀定期回收，来源slot可复用。待同步不同引用最多8192条；超限使缓存进入明确error，原合法物品动作不因此失败。

`SimInventory.ground_revision`是非存档的单调epoch：受支持API对ground容器写入、成功同实例恢复会递增；失败及历史回执重放不递增。`SimArtifacts.state_generation`识别同实例初始化/恢复/整体开局装配。缓存同时核对world、lifecycle、ground、artifacts和各区域inventory实例及这些epoch，不只比较游戏时刻或位置revision。

在每次生命周期写入前先检查是否有未登记变化，防止后一正常事务遮掉先前旁路。聚落服务、跨区搬货及鸟类交换的直接账本路径拒绝新ground写入，地面物件由生命周期处理。器物只读guard期间也拒绝生命周期执行/预约/取消，避免克隆账本后重入写入又被覆盖。

直接调用ground变更或inventory ground API而不走生命周期，会被识别并拒绝继续读旧缓存；调用者须先维护原世界一致性，再关闭重绑。公开Dictionary的任意直接改写不在支持合同内，缓存不通过每次全图扫描防御任意脚本；不长期保留各容器旧字典引用。

## 恢复、失败与时间

world恢复替换原所有者后旧服务立即拒绝使用，即便新实例有相同时间和数字revision。同实例inventory/artifacts恢复也改变epoch。缓存不写普通存档，恢复后从验证过的原世界重新装配；不扩schema51/区域42。

building期间发生物件事务会中止装配并报initialization_changed，不能把前后时刻拼成新场；关闭后重新绑定即可重做。缺profile、owner替换、未追踪变更和工作异常不发布半结果，也不改原物、账本或时间。重复command只返回原回执，不制造第二次失效。

工作预算衡量算法工作量，微秒目标用真实墙钟检查；小片中包含的不可细分操作仍可能越过目标，不能宣称硬实时上限。该服务不拥有新10Hz/20Hz环境调度、时间背压或输入队列，不能仅凭缓存完成就声称动态尾迹或严重过载已经解决。

## 验证入口

- `tests/sim/test_environment_ground_cache.gd`：真实对象、参考对照、预算/回调/变更/恢复。
- `tests/sim/test_environment_inventory_epoch.gd`：epoch、失败/重放、同实例替换和直接写入旁路保护。
- `tools/benchmarks/environment_ground_cache_guard.py`：串行运行64²至512²真实混合地面物，外部限制时间和进程内存，测装配、局部/全图冷建、热读及变动重算。

工程合同不代替受检SHA及数值证据；本包完成记录见[缓存QA](../qa/20261105_environment_ground_cache.md)。后续实际响应和普通接管仍须单独排包。

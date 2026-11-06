# 真实地面来源的分块基础目标缓存

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
| `advance(max_work=4096, max_usec=2000)` | 按预算装配、同步待变更来源；无计算租约时再重建已请求块；返回state/work_used/elapsed_usec/pending_sources/pending_tiles |
| `request_area(rect)` | 裁剪到地图并向外对齐16×16块；只登记请求，不同步计算全图 |
| `read_base(cell)` | building、相关来源未同步或块未完成时返回pending且不附部分值；ready才返回五行与净冷热 |
| `diagnostics()` | 当前状态、实际来源数、装配进度、待处理/缓存块、slot高水位、复用及失效次数；不是玩家观察 |
| `close()` | 解开内部绑定，释放派生数据；同一个服务可再次configure |

成功读数带`visibility=authority_only`、`live=false`、scope、游戏毫秒、定义digest及计算rule_version。查询不会推进世界或写入人物认知。world欠算/区域未同步时明确拒绝读数，不把旧值标成当前；同步后可重试。

第一次装配按16×16空间桶扫描完整占地，只有锚点所在桶登记该物，避免跨桶重复。每步处理一个有限桶查询或一条来源投影；一桶最多256件排他地面物，桶查询自身不能任意细分，耗时单独计入。来源和索引从原owner派生，不调用全世界`to_dict()`，不把历史inactive槽复制到来源库。

ready不表示所有地图块都已构建，须同时看pending_sources和pending_tiles。未请求块可以一直不建；首次读会登记该块。基础目标可丢弃重建，不可丢弃未来接入的实际环境历史。

普通CPU初建使用原`SimEnvironmentGroundField`的16²来源块逐通道等级计数/最大堆：每个目标块只汇总最大半径覆盖到的来源块，所得保守强度上界用于原距离有序搜索。汇总每个来源块占一个work，完成后才开始接收格计算；原整数核/舍入/max和完整块发布不变。直接增删/移动和候选提交均维护派生计数，同强/次强和空块回收保留；不复制实物或保存第二份场。候选搜索仍用原排除旧slot的全局上界，GPU仍用已有独立基础场管线，不因这个索引自动提速。

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

## CPU/GPU 计算接缝

`EnvironmentFieldComputeRuntime.configure(ground_cache, mode)`接受此服务以及原底层场缓存，mode为cpu/gpu/auto。模拟层不依赖渲染运行层；只新增受控的计算协议，GPU线程只收到脱离原物的只读投影。

- 运行层通过`acquire_compute_backend(owner)`取得唯一弱引用租约；此时原`advance`只装配/同步来源，目标重建只由计算服务驱动，避免两处重复推进同一队列。空闲运行层`close()`释放租约；ground关闭或重绑作废原租约，旧服务不能操纵新绑定。
- `export_compute_job(area, compact)`要求来源已同步，附带原绑定、单调来源代次及定义digest；不暴露底层cache写引用。潜在来源变动在内层投影尚未更新时已递增代次，不能只查内层revision；普通容器转账或保持正数量的既有同类堆不重启计算，所有事务仍核原owner/epoch。
- `publish_compute_result(job, prepared)`在原owner线程核原世界、所有者、库存epoch、绑定、定义、来源队列和代次，再交原cache校验/发布；不在复验与发布间调用外部回调。过期结果不部分写入，后续预算CPU可继续同步并计算最新值。
- GPU请求遇来源待同步进入preparing；poll按正常预算同步后再尝试一次GPU。已有运行中GPU作废后回CPU，设备/快照/显卡失败有明确原因；不无限重试显卡。取消和换世界后仍由原服务poll回收活线程，忙时close拒绝，不在主线程等待活GPU线程。
- `rebuild(max_tiles,max_work)`供运行层CPU路径使用，来源同步与目标重建共享约2ms检查目标；`pending`表示来源仍待同步，块队列另看pending_tiles。快照打包、发布、分配并非天然满足此时间片，分别测量，不能宣称硬实时上限。

开发请求严格使用地图内16×16整块；原`request_area`查询仍可裁剪扩块。自动阈值由本包真实CPU/GPU同负载测量决定，不能套用合成例子的阈值。该接缝不引入新时间、存档域、普通Main开关或实际温度/五行响应。

## 验证入口

- `tests/sim/test_environment_ground_cache.gd`：真实对象、参考对照、预算/回调/变更/恢复。
- `tests/sim/test_environment_inventory_epoch.gd`：epoch、失败/重放、同实例替换和直接写入旁路保护。
- `tests/runtime/test_environment_ground_compute.gd`与`tools/qa/environment_ground_compute.gd`：真实CPU/无设备回退及硬件GPU、原物变更与未同步结果拒绝、取消回收和原世界替换。
- `tools/benchmarks/environment_ground_compute_guard.py`：相同真实物品布置下的CPU/GPU/auto对比，整链路、分散变化和主线程耗时；GPU回退单列，不冒充硬件成绩。
- `tools/benchmarks/environment_ground_cache_guard.py`：串行运行64²至512²真实混合地面物，外部限制时间和进程内存，测装配、局部/全图冷建、热读及变动重算。
- `tools/bench_environment_cold_build.py`：真实密集来源，分开装配与CPU冷建，输出work、分片分位、外部进程内存和独立原物参考；同参数对照口径见[初建QA](../qa/20261106_environment_cold_build.md)。

工程合同不代替受检SHA及数值证据；本包完成记录见[缓存QA](../qa/20261105_environment_ground_cache.md)。后续实际响应和普通接管仍须单独排包。

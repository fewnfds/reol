# 静止地面来源的实际响应接缝

本页说明当前代码接口；授权与验收结论看[接续](../status/handoff.md)，计划范围见[小包规格](../plans/environment-object-loop/response-ground.md)。不代替[已定环境规则](../../design/rules/environment.md)。

## 唯一状态与职责

- `RegionalSimulation`及其原领域仍持有物品、身体、容器、动作、回执与整数游戏毫秒。
- `SimEnvironmentGroundCache`仍只有一套来源槽位与基础 max 场；联合变更在它的原 `_cache` 内准备，不建立第二份长期来源。
- 地面构造使用`SimEnvironmentGroundField`继承同一缓存。七通道非零等级计数与索引最大堆仅提供可下降的搜索上界；候选排除被替换slot，仍按原距离核、整数舍入与空间索引求精确max。相同最高等级的其他源不能被错误排除。
- `SimEnvironmentTemperatureState`是本接缝实际温度 owner；新`SimEnvironmentPhaseState`持有五通道实际影响，内部按金/木/水/火/土、既有 milli-grade 单位排列。来源配置的木/火/土/金/水顺序由原 Rules 显式换序。
- `SimEnvironmentSourceChange`联合单来源场、温度和可选五行候选；`SimEnvironmentResponseTargets`在气候/天气/潮汐段边界重订目标。
- `EnvironmentResponseSession`是**封闭开发验收适配器**，不向普通 Main 安装新环境，也不拥有另一套玩家世界。调用者绑定后不得直接读写所交付的原 world；原公开领域对象本身不提供全局事务隔离。

实际响应沿既有端点公式，不新增邻格传热、守恒、积分账本或逐源 tick。读取不改时间锚点；越过未接续目标边界、早于保留锚点或未初始化时明确拒绝。

`SimEnvironmentTargetCompiler`只缓存一个时刻/期限下各区域的气候与下一边界，配置一次完整验证并隔离复制。每格仍按原整数规则计算潮汐和目标，冷热与五行复用该格同一潮汐倍率；缓存不持另一份世界或历史。不等同于GPU联合候选加速。

## 初始化与受控区域

`configure(world, definitions, settings, area)`只接受无时间债且完整同步的原世界、已验证来源配置，以及16格对齐的区域。配置的气候、天气与 epoch 必须匹配原世界。

适配器通过`pump()`有界完成来源装配、基础目标和实际锚点初始化；初始化完成才进入`ready`。初始温度取此生效时刻可证明的当地中性气候，五行取此时已有静态场的潮汐目标。该策略不能倒称生效前已有新模型历史。区域全部追踪，首次查询不会补造历史；物品旧/新影响覆盖必须在受控区域内。

目标刷新每个候选最多64块；适配器分块行续算512²，全部完成才发布完整时刻。剩余块的中间状态不向适配器查询或视图发布。当前初始化/恢复/长段刷新累计耗时与同步峰值须按QA解读，不承诺常时大世界实时吞吐。

## 原物变更协议

生命周期先生成冻结计划：`request/reference/from/target/size/definition/at_ms/ground_revision/artifact_generation`。来源投影`project_move(plan, event_context)`不写原物，读模板生成未来来源。

```text
prepare_move → pending/resume_move → 最终复验
  → 原物短同步提交 → 原缓存/温度/五行发布 → 回执/动作结果 → committed
```

候选期间不分配正式slot、不写位置、不切换实际环境。取起撤源并回收slot，放下预留空闲slot，移位复用slot；无来源变化的合法移位可用空环境候选。成功联合路径不再调用普通`objects_changed`重复同步，旧GPU快照按原代次失效。GPU当前只加速基础目标，没有加速这里的原子候选。

首包仅接已存在、受控独特实物的同区域取放/移位；其他实物和材料堆作为静态背景。生成/销毁地面源及材料地面拆并在写前拒绝。`SimArtifactTransfers`的独立地面guard与原业务guard串联，避免旧器物转移路径绕过联合写入；无环境会话时沿原路径。

## 共同事件边界与取消

直接操作`execute()`可返回pending句柄，`pump()`继续；不重复发物或扣成本。已有耗时动作仍是人物原地等待、到期转移，pending保留active、预约、原due_ms和身体控制。它不是携物走路或沿途辐射。

世界只在opt-in guard下挂起对象结算边界。手动移动、区域推进、上一段结算和抵达已执行一次；续算从对象阶段继续，不重复它们，也不越过未完成动作运行后续领域。context凭据绑定原世界、guard、当前毫秒、阶段和全部区域同步状态；不能用`allow_backlog`布尔绕过原检查。

适配器挂起期间普通命令/事实查询/保存返回busy；`view()`只返回之前完整投影，`status()`公布已发布时刻和待算阶段。允许受控resume/cancel。取消销毁候选，保留已经发生的时间和旧阶段成本；原物不移位、不写成功回执。到期边界取消后仍须收尾后续阶段。原始world仍能被不遵守封闭合同的外部代码直接读取，因此此接缝不能直接当普通 Main 的全局隔离层。

## 开发验收存读

`EnvironmentResponseSnapshot.capture(session)`只在完整ready、无欠时/候选时捕获原世界、配置digest、受控区域及温度/五行锚点。开发快照当前版本2：原世界保留原`to_dict/restore`，响应以16²块的packed时间、状态和float64数值列保存，避免每格字典及浮点文本。

`stage(data, world_factory, definitions, settings)`调用独立世界工厂，验证并恢复原物、动作和时间，再重建派生缓存。`EnvironmentResponseColumns`校验完整覆盖、块顺序和两种owner的锚点后才一起赋值；后续按`cell_budget`逐格核对时刻、tau、目标与真实来源，期间状态为`validate_restore`。全部通过才ready；失败不替换活会话。残留无需仍有来源，正常进行中动作可保存；准备中保存busy。原世界恢复及列结构校验仍是同步加载步骤，不能把分片目标校验宣传成全程无尖峰。

`EnvironmentResponseFile.write/read`传输当前快照：固定magic/文件版本、白名单数据树及全流SHA256，64KiB缓冲；只允许普通值和数值packed数组，不启用Object反序列化。限制深度、节点、单值及2GiB文件大小，拒绝损坏、重复key和尾部。写临时文件完成校验后，先将有效主档复制并校验为固定`.recovery`，再保留唯一主档备份并提升新档；已有恢复文件（包括复制残片）先轮转为独立文件，目录或链接占位时拒绝。只有主档缺失时读取完整恢复文件并返回`recovered=true`；损坏或不可读的主档拒绝回退与覆盖。恢复文件仅校验传输结构与哈希，业务候选仍须经`stage`完整校验。此过程要求同一路径单写入者，提供进程中断后的可发现恢复点；Windows目标替换不保证原子，且不提供断电后的全盘fsync保证。该文件层仍同步执行，尚非后台自动保存。捕获/解析结果应在下阶段接管后及时释放，避免同时保留不必要的完整世界副本。

大档内存还取决于原世界元数据：原`object_receipts`将材料转移沿既有生成回执机制压为语义完整记录，`_receipt()`按需解码；请求格子与实际合并目标分开，预约与原库存操作可核验。库存范围和已完成动作校验均通过同一解码接口，不将数组当另一套账本。普通schema51/生命周期版本1不变；当前写紧凑记录，既有完整字典仍在原受支持读取范围内。数据输入与恢复owner不共享可变数组，失败不提交。

该格式仅是开发验收快照，不改变普通schema51，不自动支持旧环境档。普通Main接管、材料事务、携物整体发源、房间、生物后果仍需后续单包。

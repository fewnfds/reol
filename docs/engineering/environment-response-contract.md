# 静止地面来源的实际响应接缝

本页说明当前代码接口；授权与验收结论看[接续](../status/handoff.md)，计划范围见[小包规格](../plans/environment-object-loop/response-ground.md)。不代替[已定环境规则](../../design/rules/environment.md)。

## 唯一状态与职责

- `RegionalSimulation`及其原领域仍持有物品、身体、容器、动作、回执与整数游戏毫秒。
- `SimEnvironmentGroundCache`仍只有一套来源槽位与基础 max 场；联合变更在它的原 `_cache` 内准备，不建立第二份长期来源。
- `SimEnvironmentTemperatureState`是本接缝实际温度 owner；新`SimEnvironmentPhaseState`持有五通道实际影响，内部按金/木/水/火/土、既有 milli-grade 单位排列。来源配置的木/火/土/金/水顺序由原 Rules 显式换序。
- `SimEnvironmentSourceChange`联合单来源场、温度和可选五行候选；`SimEnvironmentResponseTargets`在气候/天气/潮汐段边界重订目标。
- `EnvironmentResponseSession`是**封闭开发验收适配器**，不向普通 Main 安装新环境，也不拥有另一套玩家世界。调用者绑定后不得直接读写所交付的原 world；原公开领域对象本身不提供全局事务隔离。

实际响应沿既有端点公式，不新增邻格传热、守恒、积分账本或逐源 tick。读取不改时间锚点；越过未接续目标边界、早于保留锚点或未初始化时明确拒绝。

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

`EnvironmentResponseSnapshot.capture(session)`只在完整ready、无欠时/候选时捕获原世界、配置digest、受控区域及温度/五行锚点。保存使用项目`SnapshotValues.canonical_json`保留浮点精度。

`stage(data, world_factory, definitions, settings)`调用独立世界工厂，验证并恢复原物、动作和时间，再重建派生缓存。两种响应owner完整校验后，逐格核对区域覆盖、时刻、tau、目标与真实来源，再发布候选；失败不替换活会话。残留无需仍有来源，正常进行中动作可保存；准备中保存busy。当前恢复末尾逐格联合校验是同步尖峰，按实测披露。

该格式仅是开发验收快照，不改变普通schema51，不自动支持旧环境档。普通Main接管、材料事务、携物整体发源、房间、生物后果仍需后续单包。

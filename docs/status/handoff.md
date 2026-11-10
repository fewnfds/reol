# 当前接续

2026-11-11：用户授权开始A的第一小部分。本包接通普通Main原身体的CPU批计算、原owner有序采用及取消/恢复失效；未创建Goal。A整包和300人性能出口仍未完成。

## 当前依据与实现

- [唯一主计划](../plans/foundation-priorities.md)：P01–P16、S01–S12及A–D框架交付；不恢复旧局部优化队列。
- [目标执行规格](../specs/world-engine/execution.md)、[领域职责](../engineering/architecture/05-framework-domains.md)保持目标/逻辑边界，允许替换现有类、存储与调用链。
- 已接[CPU批执行](../engineering/execution-batches.md)：SimBatchExecution＋SimActorAdvance，native_interval/native_actors进入同一个SimSettlementKernel。普通运行按到期集合准备，worker只算紧凑数值候选，原身体/空间/动作owner采用；手动输入在begin前受理。
- GPU输入/结果/代次的公共采用接缝已明确，本包没有GPU dispatch。世界仍有同步准备/路线/决定/领域与提交成本，不能宣称所有模拟已并行。

## 工作区、验证与接续

分支`codex/execution-foundation`，起点`3e32b7048e0622de87bc1fa6823ed661c36b8369`。旧8份代码补丁已原样保留于`10260b3b45952b7b45055e807f360824227efce2`，旧文档清理为`95eac7d624b39d12fe36ba2b936ac342e7bcee89`；本包按需替换其中实现，不继续旧优化收尾队列。

本包定向证据、实际失败及修复见[QA](../qa/20261111_actor_batch_execution.md)。原身体串行/worker未来、搬运守恒、取消/成功与失败restore通过。实际clock/world与环境/搬运接缝5组526检查通过；扩充后批组132检查通过，最终失败回执反例由完整回归覆盖。

当前唯一完整验证是`python tools/godot.py check --test-timeout 3600`，活终端handle `9476`，不另开重复整套；只剩等待时一次工具编排持有此handle直到终态。原生审查尚未启动，后续按准确代码提交一次只读审查；主代理协调测试，审查器不得再开引擎或递归审查。

300人Windows实卡20秒样本证明18个真实worker批次、1302份结果被采用；workers=4/0约0.5126/0.5203×，帧P95约22.13/22.024ms。没有可信整体收益，未达1×/60FPS。准备/发布比数学更贵；下一A内部工作应收敛热数据所有权与批量发布，不能用线程占用代替性能出口。

未改变内容JSON/原fixture/保存格式。新脚本保留Godot生成UID；导入新增的shader .import空行在提交前复原为HEAD原字节。原争环分支`4e17c5c165cf8fca9ef884a111aa1c3ca35f445f`及stash `424f956d280fb390d17e1f6dd879f3614b51a430`未恢复/删除。

## Git与CI

main/origin/main仍为`839ff88f1b7fee240d0c798f533314a3ae446430`，无自动合并。已核代码祖先`8c3deaa972f932e999167b61ea6b166b928cfe5f`的[CI42833827684](https://github.com/fewnfds/reol/actions/runs/42833827684)为completed/success，只证明该祖先；本地新提交不继承其绿色。

CI仅在真实提交准备点核对相关已推送SHA/run一次，不轮询、不后台等待、不声称GitHub结果可唤醒聊天。本包最终提交/原生审查/完整回归终态完成后直接改写本页与BASELINE。

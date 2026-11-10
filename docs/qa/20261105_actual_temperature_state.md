# 已知目标段的实际温度状态（F2a-1）

日期：2026-11-05。此包是隔离规则，不是普通 Main 的冷热替换；接入顺序见 [F2合同](https://github.com/fewnfds/reol/blob/8c3deaa972f932e999167b61ea6b166b928cfe5f/docs/specs/environment/integration.md)。

## 实现与边界

[`SimEnvironmentTemperatureState`](../../scripts/sim/environment_temperature_state.gd) 只持有显式跟踪地块的实际温度响应锚点，不拥有物件、场强、Q、积分账或第二时钟。读取不改锚点；未知格、过去已被替换的响应、超出已知目标段分别明确失败。完整目标批次预检后原子提交，预算不足不改状态；计划绑定原 owner/revision，提交一次、恢复或新计划都会使旧计划失效。

响应查询复用原闭式表达式，新增 `sample(at_ms, false)` 跳过累计积分。空间核已经预计算；此处没有逐格数值积分或每格 Timer，也没有证据要求新建时间响应查表。保存使用全精度 JSON；完整候选校验后才恢复。

本包通过 F0 场目标演示热源 A→B 后旧格回归、新格建立及冰火等阶抵消。**测试直接修改隔离场夹具，并不证明原物、场索引与温度已形成联合原子事务。** 气候/tide目标段编译、普通共同时间接入、真实器物变更、人体/草木历史、房间和有限旧档导入均留后包。

当前每格是独立响应对象，`next_boundary_ms` 遍历已跟踪格；预算是完整批次格数，不是可暂停的墙钟预算。本包仅验证少量已知段，不将配置容量、GPU静态规模或断言数量当作密集动态温度容量。

## 验证证据

- Godot 4.7.2 stable，Windows，同现有开发机；最终导入 `logs/import-20261105-110646.log` 通过。
- Response＋实际温度两组：**378断言、0失败**，1.698秒，工作集峰222449664 B，外部30秒/1 GiB守卫；`logs/temperature-state-first.json`。包括有源建立/无源回归、连续切换、只读查询、错误/预算/过期计划拒绝、绝对零边界、独立JSON未来。
- 跟踪的 [两进程QA](https://github.com/fewnfds/reol/blob/8c3deaa972f932e999167b61ea6b166b928cfe5f/tools/qa/environment_temperature_restart.gd) 先 `-- write` 完全退出，再独立 `-- read`：3格/12个未来点，两个进程均约0.348秒、约100 MB工作集，无SCRIPT ERROR/ERROR。`logs/temperature-state-restart-{write,read}.json`。
- 检查点SHA256：`8d7c17afe6f0723279d7100eb8df182e66ec138a7d24f744663d947c4e1c6a40`；未来SHA256：`d7f16afe1f22d31590ec264ebb59787ac7ece8a56ad99e2fb8b0e95bdfaa98c2`，跨进程相同。这里只保存独立温度域，**不是普通Main完整停开**。

尚无本包画面变更。完整回归留推送SHA CI；不能借前SHA绿色或在跑的CI代替。提交准备仅发现前推送 `08c8b1dbaf8ab47c8cf98452943bd495c43dbcaf` 的 run `41958840430` 为 in_progress，不等待/轮询。

代码 `2e995b83b12bebbd9d7bb070adfe48168cbcc393` 完成一次Sol/custom只读原生审查，125.729秒、退出0，无可操作发现；没有运行引擎/测试/CI或修改文件。记录为 `logs/reviews/<SHA>.explicit-sol.log` 与 `.explicit-sol.summary.json`，不重复整包审查。

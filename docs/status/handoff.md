# 当前接续

核对：2026-11-05。用户已排定通用世界骨架的详细实施文档与首包 A（对象、能力和空间合同）。当前 Goal active；先做基础，不扩玩法；完成本包并报告后停止，后续 B–E 待逐项排定。第一阶段完成不能由首包完成代替。

## 当前范围

- [详细阶段方案](../plans/world-foundation/README.md)：包 A–E 的输入、接口、验收、性能与停止点。
- 当前首包沿原对象/身体/库存/自然源/结构所有者提供共同描述、能力和空间快照接口；多类实际来源验证，不新增玩法和玩家全知 UI。
- 空间快照只表示捕获时刻和指定引用集合，不是实时全世界索引；跨变更必须重建，实时失效/更新协议随后续生命周期包接。
- 先定向验证，再做必要完整回归或对应 SHA CI、一次原生只读审查。无画面改变不以 headless 冒称视觉验收。

## 保留的游戏半成品

起点为 `codex/world-engine` / `bbd4303eb2ae477015dd1d9a40b170562c40a4d8`。本轮开始时以下四个文件有未提交环境源/接收区/潮汐相关改动，**未在本轮测试或入库**：

- `scripts/sim/environment_field_cache.gd`
- `scripts/sim/environment_temperature_state.gd`
- `tests/sim/test_environment_field_cache.gd`
- `tests/sim/test_environment_temperature_state.gd`

本轮已在忽略的 `logs/doc_reorganization_20261105/protected.json` 记录 SHA256，收尾核对字节未变。恢复开发时先检查实际 diff，不据文档把 WIP 当已验实现。

## 提交和接续

文档重构已提交至 `42b0aa7`；本轮具体代码、验证证据和待验边界登记在 [首包 QA](../qa/20261105_world_object_contract.md)。未提交工作以实际 Git 为准，保护文件不纳入首包。

主代理协调引擎与验证；子代理不另跑全套或审查。只在真实提交检查点核对 CI 一次，不轮询、不派等待代理；首包完成后向用户报告通用能力、性能、限制和下一包建议。

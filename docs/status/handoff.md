# 当前接续

核对：2026-11-05。用户授权的第一阶段 A–E 通用世界骨架已完成声明范围的联合验收；本轮只完成基础，没有扩玩法或接管新环境场。目标为16 GB整机内存、单张中低端消费独显，本机32 GB不能直接当最低配置实测。当前没有自动排定下一阶段。

## 已完成与证据

A多类对象/能力查询与显式集合空间快照，B受控实物与多格地面位置，C同账本材料堆拆及共同耗时搬运，D装配/候选存读与在途恢复，E开发诊断/普通呈现/声明规模测量均已接入。身体、器物和数量继续沿原所有者，接口是权威开发接缝，不授玩家距离/认知/社交权限。

- [生命周期合同](../engineering/object-lifecycle-contract.md)说明请求、归属、占地、时间、取消和恢复边界。
- [最终出口QA](../qa/20261105_world_foundation_exit.md)记录同一普通Main离返后完全退出、新进程恢复和相同未来；512²真实物品落盘、批量搬运与候选；满格呈现1800帧；1/4/8大型身体及保存候选。
- [完整包QA](../qa/20261105_object_lifecycle.md)保留原失败、修复、审查与早期测量，不覆盖原日志。

游戏主代码 `c529c96910a0ef07af5e6d720bd848f395c4fed8`，一次原生Sol/custom只读审查的五项问题已修复到 `b78f3af607c3b8c798411f4945de123d1d0ebf30`。后者精确SHA在独立检出完整check通过：254组、98467断言、0失败、无ERROR/SCRIPT ERROR，1127.369秒。后续只扩四个验收基准和文档，游戏逻辑/定义/场景未变。最终基准逐次记录HEAD、diff和脚本哈希；无额外整包审查或完整回归。

## 工作区保护与版本

分支 `codex/world-engine`；游戏、验收脚本与文档按可解释提交保存。最后推送和本地HEAD以Git为准；新推送CI未查询/未验，不声称自动回调或等待。上一已核CI为d0bc对应41982168735 success，仅复用终态缓存。主验收使用上述精确游戏SHA的本机完整check。

四份原环境WIP不属于本包、未混入提交或精确SHA回归；起始SHA256在 `logs/world_lifecycle/protected.json`，须继续原样保护：

- `scripts/sim/environment_field_cache.gd`
- `scripts/sim/environment_temperature_state.gd`
- `tests/sim/test_environment_field_cache.gd`
- `tests/sim/test_environment_temperature_state.gd`

原始性能/截图/审查/失败日志均在忽略目录 `logs/world_lifecycle/`。独立check原日志保留到 `isolated-check-logs/`；最终检出日志/存档另保存到 `final-validation-artifacts/` 后可移除自建验证worktree。不可删用户文件或四处WIP。

## 已知限制与后续依赖

普通Main冷热仍是旧Q，新冷热/五行场、GPU接管、完整房温、生态及大量自主NPC属于[后续基础依赖](../plans/foundation-priorities.md)。用户未在本轮授权自动连续扩阶段。动态只测原大型身体上限8；环境传播不由静态物品密度证明。

满密度候选恢复约32.7秒、工作集峰4.82GiB；大量JSON和恢复延迟、历史槽位/回执安全回收仍有优化空间。真实16GB主机、满密度Main跨进程存档、全AI与新场同时运行、正式切片和独立发布未验。不把第一阶段底座完成称为完整游戏完成。

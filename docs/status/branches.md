# 分支与保护范围

核对：2026-11-11；实时指针以Git为准。本页不列已结束分支的实施历史，也不因旧分支存在恢复其任务。

| 引用 | 作用 |
|---|---|
| main / origin/main，839ff88f1b7fee240d0c798f533314a3ae446430 | 当前已集成旧Demo，其准确SHA完整CI通过 |
| codex/execution-foundation | 当前A开发入口；从旧保留点建立，首条CPU批执行已接普通Main，验证与准确提交见HANDOFF/BASELINE |
| codex/navigation-data-reuse，10260b3b45952b7b45055e807f360824227efce2 | 文档清理95eac7d与原样代码WIP保留点，均本地提交、未推送；没有自动合main |
| codex/sparse-runtime-dispatch | 上一共同运行实现及夹具修补来源；完整证据见BASELINE，不继续旧局部优化队列 |
| codex/field-contest，4e17c5c165cf8fca9ef884a111aa1c3ca35f445f | 隔离的旧争环WIP，未恢复/删除，不是新架构待合并成果 |

命名stash `424f956d280fb390d17e1f6dd879f3614b51a430`继续保留，不应用或删除。其他历史分支不清理、不强推，使用Git按需追溯。当前任务、工作区和工具handle只登记[HANDOFF](handoff.md)，验证见[BASELINE](baseline.md)。

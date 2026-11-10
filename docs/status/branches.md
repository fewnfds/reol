# 分支与保护范围

核对：2026-11-11。本次已将`codex/execution-foundation`快进合入main；源分支保留。main包含CPU批代码`7f5947b80b62256ca370d4276dd3f62842f61d8a`及流程退役`7f881097e5091b1f44637d34927851022111c386`，另有后续整合说明提交。准确HEAD以Git为准。

| 引用 | 状态 |
|---|---|
| main / origin/main | 本次整合主线；性能和未完成项见HANDOFF，不继承旧CI的绿色声明 |
| codex/execution-foundation | 本次整合来源，已有全部成果进入main，不再有独立待合并开发项 |
| codex/navigation-data-reuse，10260b3b45952b7b45055e807f360824227efce2 | 早期补丁保留点，已随源分支进入main；未完成的配对/停开等验证明确标记，不阻碍本次整合 |
| codex/field-contest，4e17c5c165cf8fca9ef884a111aa1c3ca35f445f | 明确隔离的旧争环实验，未合入、未恢复、未删除 |

本次Git祖先核对中，除上述隔离实验外，其余本地开发分支均已包含于整合历史；保留历史名称，不清理或强推。stash `424f956d280fb390d17e1f6dd879f3614b51a430`原样保留。

旧CI/全量测试及自动审查门禁已退役。当前停在讨论节点，不自动恢复性能开发或历史收尾；授权和缺口只查[HANDOFF](handoff.md)。

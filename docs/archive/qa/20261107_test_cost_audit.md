# 工作流与测试成本调查

> 历史资料：保留原日期与结果，不是现行指令或任务；当前信息查[项目记忆地图](../../README.md)。归档于2026-11-11。

## 范围与来源

2026-11-07；起点`d4e5f716aa1cd9fb84b47727160506c2b63addc9`，分支`codex/sparse-world-execution`，受检代码`b60adadfcab73a17e101b62538da62ddc5bccf9f`。本包只改工程工作流、测试工具与运行器、CI计时artifact；生产scripts/data/scenes/addons及全部现有测试组/断言不变。收尾提交只更新文档证据。

只读参考本机`agent-shell`的AGENTS、文档策略、测试策略及外部工作台；未修改参考项目。可复用的是现行契约与阶段过程分离、完成时同步说明、按主要owner与成本选测试。其`.docs`未纳入Git、索引仍有漂移，故没有机械迁移Reol目录或建立仓外唯一权威。现行规则落在[文档合同](../../DOCUMENTATION.md)、[开发流程](https://github.com/fewnfds/reol/blob/8c3deaa972f932e999167b61ea6b166b928cfe5f/docs/engineering/workflow/ai-development.md)、[测试策略](../../engineering/workflow/testing.md)。

## 原有证据及调查限制

本机原完整回归248组/124980断言；数字是断言调用次数，不是独立案例数。runner有220个外部测试入口和28个内联/特殊组。目录里另外的历史测试不一定注册，不能把全部源文件的循环都算进当前成本。

既有[CI42345202281](https://github.com/fewnfds/reol/actions/runs/42345202281)在1800秒超时退出124；Python及import完成，启动221组、完成220组，最后RUN地形编辑。原包装器缓冲输出，旧日志无法反推逐组耗时；不能据此认定该组或无显卡为根因。原日志`logs/documentation-audit/ci-42345202281-failed.log`已保存，本轮复用终态，没有查询/等待CI。

## 有界实测

doctor核Godot4.7.2。硬件沿本机i5-13600KF/32GB环境；五组为debug/headless CPU单次测量，非GPU或16GB整机性能承诺。命令选择下表五组，设置240秒总上限；由原session取得终态，没有轮询testlog。日志`logs/workflow-audit-selected.log`，逐组记录`logs/test-cost-audit/selected.jsonl`。

| 测试组 | 断言调用 | 耗时ms | 主要工作 |
|---|---:|---:|---|
| world_map_data | 122 | 21693.259 | 512×512旧生成器等价、2097152方向步对照、边界和副本 |
| terrain_edits | 66 | 13395.403 | 三次完整Main装配、多次完整快照及存读、在途连续性 |
| world_environment_fields | 163 | 1944.733 | 多次完整内容/两区世界fixture及恢复 |
| environment_field_cache | 53372 | 930.276 | 缓存与独立参考逐格/七通道一致、预算与候选发布 |
| environment_field_rules | 1171 | 6.583 | 纯核曲线、距离/边界和等级等规则 |

**五组54894断言、0失败**，组内合计约37.97秒。缓存组静态至少50480条来自6310格次×8条检查；这一大数字没有成为本样本耗时主项。反之仅122条的全图组花21.69秒，说明不能按数量删除断言。该样本不能代表全部248组，也没有解释全部1800秒。

## 实际改动与验证

- 原runner新增精确选组、列举、每组耗时/断言增量、最慢十组及可选JSONL；默认仍248组。每组开始/完成flush，超时可保留已完成项，无需实时读日志。
- Python入口默认创建唯一计时报告；`test --suite`可重复，`check`拒绝选组，避免把定向结果称全套通过。原SCRIPT ERROR/ERROR、退出码和超时门禁保留。
- GitHub workflow上传计时JSONL；没有改变覆盖、超时上限、runner或安装GPU依赖。
- Python全套60项通过，约1.84秒：`logs/workflow-audit-python.log`。输出中的脚本错误/1秒超时是已有故意失败样例。
- 实机runner列举248组；重复选择规则组只执行一次，1171断言与JSONL相符；未知/空名称非零，无法打开报告在执行组前失败。证据在`logs/test-cost-audit/`及`logs/workflow-audit-list.log`。
- 结构/链接与差异检查通过。没有游戏表现变化，未开实时场景或为工具改动重跑几十分钟全游戏回归。
- 受检提交一次原生`gpt-6.1-sol`/custom静态审查终态无可执行发现，日志`logs/test-cost-audit/review-b60adad.log`；审查没有启动引擎、测试、CI或额外审查。推送触发的完整CI留待下一真实提交检查点核查，不把本机五组结果冒充全套。

JSONL中的失败数只覆盖断言；仍须核包装器脚本错误及退出码。flush不保证检测所有磁盘刷新故障，本报告不是崩溃一致性存储承诺。

## 后续成本治理边界

先利用下次正常提交CI的逐组证据，集中看最慢组：缩小纯规则fixture、避免多个层次重复装配Main、重新判断全图历史迁移穷举应否常驻。每次按契约和反例保留必要集成出口；没有实测收益不改游戏代码，也不以采样或删断言掩盖现行回归。

当前普通GitHub runner验证CPU规则、存读及无GPU回退；RTX3060真实compute、画面和帧时留本机。GPU缺失不是当前CPU超时的已知原因。没有引入付费GPU、自托管runner或模型云审查。

本轮完成的是诊断与工作流改进，**未宣称整套耗时已降低或CI已修复**。

# 已核实基线

核对：2026-11-11。这里只登记当前版本与仍有参考价值的测量；授权/下一步在[HANDOFF](handoff.md)，可用操作在[FEATURES](features.md)。原始报告属于[archive](../archive/README.md)，旧成功不继承为新架构通过。

## 代码与采用版本

main已整合CPU批执行`7f5947b80b62256ca370d4276dd3f62842f61d8a`、测试/流程退役`7f881097e5091b1f44637d34927851022111c386`，整合说明为`4bf039fe8fadf95e639ae64a077e4fc3c7bdeeea`。文档提交可能更新HEAD；代码证据不因此自动变成对新行为的验证。

| 项目 | 当前值 / 代码依据 |
|---|---|
| 引擎 | Godot 4.7.2 stable，GDScript；开发机Windows |
| 根存档 | 56，`SessionSaveSchema` |
| 联合区域 | 47，`RegionalSimulation` |
| 村落 / 环境保存 / 内容包 | 7 / 5 / 3；对应领域schema与`ReolContentBundle` |
| 内容清单 | 内容包绑定44份定义/开局；不等于整个data目录的文件数 |

支持/拒绝语义见[compatibility](../engineering/compatibility.md)。正式独立导出和目标PC验收尚无证据。

## 有效性能事实

开发样本硬件为i5-13600KF、约32GB RAM、RTX5060Ti，Godot Windows Forward+/D3D12开发进程；不是[目标PC](../engineering/constraints.md#产品与技术范围)。

| 负载与证据 | 已测结果 | 能说明什么 |
|---|---|---|
| 普通300人持续行动，20秒，workers=4 / 0 | 世界流速0.512640 / 0.520303×；帧P95 22.130 / 22.024ms | 真实worker已采用18批/1302份结果，但没有可信整体提速；规模目标未达 |
| 上述workers=4分项 | 准备累计13.488ms、worker累计2.347ms、发布38.511ms；native身体步骤另含大量直接执行 | worker数学不是整体最大成本，不能用线程活动当性能出口 |
| 独立512²环境基础目标服务 | 历史CPU约20.65秒、GPU约0.616秒，来源装配另计 | 独立服务有实卡证据，普通环境仍未采用其GPU数学 |

身体批的代码/样本差异和限制见[原报告](../archive/qa/20261111_actor_batch_execution.md)；GPU范围见[原报告](../archive/qa/20261105_environment_ground_compute.md)。单次开发机样本不证明稳定收益、长局、RTX3060或发布版表现。早期导航/地形补丁已合main，但最终配对性能及完整停开未验收，不为此恢复旧测试队列。

## 验证证据的范围

短smoke三项（结算续算、CPU批一致、库存守恒）实际通过，检查体0.783ms、不含引擎启动；启动器短检查0.287秒。准确日志与退役处理见[记录](../archive/qa/20261111_workflow_retirement.md)。当前验证方法和CI状态只在[开发循环](../engineering/workflow/testing.md)维护。

原整套回归在用户要求停下时人工终止，不能算完整通过。历史CI仅证明旧SHA，不再有待等CI或待补全回归任务。本轮文档整理未改变游戏代码，也未新增游戏/性能证据。

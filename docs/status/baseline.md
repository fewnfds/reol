# 当前构建与证据基线

核对：2026-11-10。本页只说明重构起点，不把旧阶段结果累计成新架构完成度。当前工作看[HANDOFF](handoff.md)，目标与验收看[主计划](../plans/foundation-priorities.md)。

## 代码起点及完整回归

- Git main/origin/main：`839ff88f1b7fee240d0c798f533314a3ae446430`；其[CI42776609463](https://github.com/fewnfds/reol/actions/runs/42776609463)已核completed/success，只证明该旧主线。
- 重构前代码保留点：`10260b3b45952b7b45055e807f360824227efce2`，原样保存导航/地形/视图查询WIP；文档清理为独立提交`95eac7d624b39d12fe36ba2b936ac342e7bcee89`。当前开发分支`codex/execution-foundation`，具体保护范围见HANDOFF。新重构尚未实现或获得完整回归。
- 本次提交准备点核对代码祖先`8c3deaa972f932e999167b61ea6b166b928cfe5f`的[CI42833827684](https://github.com/fewnfds/reol/actions/runs/42833827684)已completed/success；WIP保留点与新运行架构不在其覆盖内。此前1879f0c的CI42828875579失败及8cd155e夹具定向修补已被这个准确SHA的完整回归取代。
- 保留补丁最后定向7组637检查通过，另有导航/地形联合6组898检查通过；本轮仅原样提交，没有重跑或补齐完整回归/最终性能验收。原日志由HANDOFF登记。

## 引擎、内容与存档

采用Godot **4.7.2 stable**，GDScript；本机Windows，CI Linux headless。正式独立导出尚未验收，升级跟最新稳定版并核插件/模板/CI。

旧Demo当前根存档56、区域47、村落7、环境场5、内容包3。实际常量分别在`SessionSaveSchema`、`RegionalSimulation`和`ReolContentBundle`；原内容包清单含44份定义/开局文档，与data目录文件总数不是同一数量。旧根1–55普通入口拒绝，原fixture只读。

这些版本说明现有输入边界，不要求重构继续使用原schema或迁移链。新的支持范围须明确，候选失败不改活世界。

## 当前性能与加速事实

旧开发机为i5-13600KF、约32GB、RTX5060Ti；16GB/RTX3060[目标PC](../engineering/architecture.md#全项目性能基线)另行验收。

- 旧原生100/300人20秒样本约0.970/0.430×，帧P95约16.732/27.069ms；规模出口未达。[共同运行QA](../qa/20261110_sparse_runtime_dispatch.md)保留波动及反向样本，不用首轮改善冒充稳定收益。
- [CPU调查](../qa/20261110_runtime_cpu_root_cause.md)测得主要模拟计算集中在一个线程；普通世界尚无项目级CPU并行或GPU数学结算接入。
- GPU服务确实实现并实卡验证过；[基础目标QA](../qa/20261105_environment_ground_compute.md)的512²密集请求约20.65秒CPU/0.616秒GPU，来源装配另计，排除普通Main及后续房间/实际响应。它是可复用代码，不能算当前游戏加速。
- WIP保留点的最终配对/原生/停开验收未完成，不能报告为新性能基线。

[QA索引](../qa/README.md)保留各包原始证据；测试数量、旧集成SHA和历史“已完成”不构成对新执行结构的证明。

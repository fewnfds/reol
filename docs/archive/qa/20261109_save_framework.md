# 通用存读模块验收

> 历史资料：保留原日期与结果，不是现行指令或任务；当前信息查[项目记忆地图](../../README.md)。归档于2026-11-11。

## 受检范围

2026-11-09，分支`codex/save-load-framework`基于main `f63844b3cd18f92624f58de3749b1fbbcdd32fdd`，主体提交`96a6fe0ed891dd386cf455b4f389449d74f5b878`，最终代码`d682e030a5e28dfd04a5101bb5f826e37958422b`仅补回坏档的具体拒绝提示；已推送工作分支，尚未合入main。采用Godot4.7.2 stable；FileAccess/JSON与原`SimSaveStore`保持，未安装新依赖或复制外部实现。方案理由和公共接口维护于[存读合同](../../engineering/architecture/04-persistence.md)，这不是另一份开发计划。

`SimSaveRegistry`提供纯数据参与者capture/stage/check/install，`SimWorldSaveDomains`登记29个固定owner及可选services，当前区域捕获/形状/恢复/库存范围使用同一目录。`RegionalSimulation.restore`由350行收敛到98行，业务状态和校验仍归原域；这个行数只说明装配重复减少，不是性能结论。`SimSaveSession`提供严格保存、普通请求/完成回执和候选加载；UI/F5/开发编辑保存复用安全边界。

根53/区域44、既有领域记录与`local_heat`wire key保持。进行中动作继续保存其业务状态；未结清的内部执行游标不直接写入存档。

## 定向与反例

最终`test_save_registry`、`test_save_session`、`test_clock_world_commit`：**3组188检查、0失败，包装器退出0**。日志`logs/test-20261109-104234.log`，计时`logs/test-timings-1794192154809540600.jsonl`。

- 最小独立参与者扩字段/新增域，重复登记/缺记录/空捕获拒绝；候选不改活owner，跨域校验失败不能install；全owner先装完再bind，原物范围冲突在两种登记顺序均拒绝。
- 本地时钟与极小文件fixture验证严格接口BUSY、受理不等于文件写成、完成期间重入拒绝、30秒截止与取消释放。当前步结清后保留未启动150ms欠算；120秒等待只结清已受理的60秒区间，保留未来目标；非持久显式请求必须完成，用户暂停保持。
- 真实双区/原身体/行程在event budget与settlement work budget均为1时请求保存，多帧结清到原25ms，无额外时间准入；加载后相同250ms未来。FAILED请求不重试失败owner、不改已有档，可正常读档恢复。

前序同包定向：区域旧版拒绝/current在途roundtrip与独立工厂2组75检查（`logs/test-20261109-103106.log`）；原活动所有权、实际clock发布和双区运行存读3组256检查（`logs/test-20261109-103350.log`）。它们是各步对应代码的证据，不把这些数直接相加冒称当前版本完整回归。初次新增类未导入、测试fixture引用环导致的运行错误已修正；失败输出不计通过。

补充 construction/content bundle/field save boundary 验证中，前两组235检查通过；第三组检出坏档提示被简化，已按原合同恢复具体说明，定向重跑311检查/0失败、包装器退出0。日志分别为`logs/test-20261109-104556.log`和`logs/test-20261109-105215.log`；没有放宽断言。

完整回归交由最终代码SHA的12片CI。[CI42553338071](https://github.com/fewnfds/reol/actions/runs/42553338071)的完整headSha已核为`d682e030a5e28dfd04a5101bb5f826e37958422b`，植物计划文档的真实提交准备点经`tools/ci.py status`核completed/success；前一次文档收尾时的in_progress已成为历史状态。后续仅Markdown，产品/测试仍对应该受检代码，不重复本机全套。不是以定向通过代替完整验收；不在本机默认重复全游戏check。

## 原生Main与完整停开

永久回归外的驱动为[save_framework_probe.gd](https://github.com/fewnfds/reol/blob/8c3deaa972f932e999167b61ea6b166b928cfe5f/tools/qa/save_framework_probe.gd)。用Godot `--path . --script res://tools/qa/save_framework_probe.gd`运行；退出后另启动同命令加`-- --resume`。各次采用包装器75秒超时、错误日志及退出码门禁，均退出0。普通面板的保存signal实际连接`request_save`；测试使用独占`user://tests/save_framework_native_6118159.json`，未接触玩家普通档位。

真实Main选择人身、开始前往river的原行程，以预算1在部分结算中申请保存，再按真实帧循环续算。**121帧**后唯一成功回执，保存恰为原75ms，暂停保持；该帧数是有界验收样本，不是保存速度承诺。

| 比较 | SHA256 |
|---|---|
| 原档、同进程恢复、独立重启checkpoint | `5b2e4fd70b111841f6dc45a7e9d661e915ee67b73f9571628e69a47dddf9d0e9` |
| 三者继续250ms后的联合未来 | `5b89a9fd8b87226caf15a1e371782a235be4214c85d12ac53fe61f0eedb522d8` |

hash覆盖规范化的整个regional world、七字段clock和原玩家motion。未来比较两路均把工作预算恢复到4096；恢复不改已完成事实。日志为`logs/save-framework-native-final-20261109-104318.log`与`logs/save-framework-resume-final-20261109-104358.log`，原始JSON为`logs/save-framework-native.json`。

实际D3D12使用RTX5060Ti，1280×720原生恢复画面已查看：原身体/行程、暂停、保存后接续提示正常；截图`logs/save-framework-native.png`、`logs/save-framework-resumed.png`。这是画面与流程证据，**不是RTX3060或16GB整机性能验收**。一次参数分隔错误启动了普通Main而非QA脚本，已核归属并停止该测试进程；该次不算验收。

## 结构、审查与限制

doctor为Godot4.7.2 / Python3.14.3；当前文档结构、链接/大小及差异检查通过。一次原生Sol/custom静态主审针对主体完整SHA，无可确认修复发现。首轮因宿主Git启动故障未读到diff，不计通过；随后接续同一会话`01a1be31-657c-76f3-9ced-f6e8f421818e`，提供精确diff/完整关键源文件并补充只读源码，完成实际分析，退出0。日志`logs/save-framework-review-96a6fe0.txt`、`logs/save-framework-review-resumed.txt`；审查器未启动测试、CI或递归审查。之后只有上述拒绝提示修复，由失败反例和311检查复验覆盖。main起点同SHA的CI42544116843在产品提交准备点已核completed/success，不作为本包结果。

本包没有把`local_actions.json`、`workplaces.json`、`sparring.json`纳入内容包；这些直接读盘规则仍是原主计划的会话规则前置。普通Main使用新管线；独立Village测试/工具入口仍保留严格同步保存。没有后台无停顿快照、任意多区呈现、永久旧档迁移或大档性能承诺。文件编码层未改，不把UI协调改造解释为文件系统掉电事务已得到新保证。新业务字段仍须原owner定义和校验，通用模块不能推断领域因果。

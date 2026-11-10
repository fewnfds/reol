# 共同空间与最小行动阶段验收

范围：基础建设主计划第一阶段，开发分支`codex/world-space-actions`，起点`b3ae3399d24e01975d231cd000c0af342740070b`。最终受检`f50f0a84085294faf72e6315e99aa5343e7dbf15`，代码/测试之后仅整理Markdown证据；不合并main，不恢复隔离实验。

## 框架出口与实现

- 世界地块与空间：`SimWorldSpace`组合现有身体、地面器物/数量堆、蓝图/已建结构和固定组件。原地面/项目索引继续使用，新增身体/固定/场所物的可重建格链接。查询有预算、类型/层/范围和来源时间，完整成功才发布引用；容器锚点不冒充地面物。
- 实体、物品与容器：原位置writer、雀升降、生命创建、取放/数量转移及蓝图/建拆/门提交后通知；冻结引用和变化范围。恢复失败保留旧服务，成功重建并使旧handle明确失效，普通独立世界替换也退役旧服务。原身体、物品、账本和schema均未另建副本。
- 单位行动与交互：`SimActionContract`在耗时取放/施工中实际共用存活/控制/占用检查、执行复核、暂停/恢复原自主权、原预约释放和共同终态通知；原阶段/截止时间/材料成本和领域效果保留。施工在取料/作业位置改变后中断，不远程完工。普通实物面板读共同原动作投影，F8移除沿共同空间候选。

合同见[实时空间](../engineering/object-query-contract.md#实时局部空间)与[最小行动](../engineering/object-lifecycle-contract.md#与施工共用的最小行动合同)。通用植物、多工地/多格家具、全域动作编排、完整绕路、跨账本搬运和房温不在本阶段实现。

## 定向验证

`test_world_space`为实时查询主要owner，复用两份原领域fixture而不重复装配Main；保护跨格/跨层/多格去重、地面/包含区别、数量堆、两布局/两结构类型、建拆、冻结变化、低预算/未知/待算/滞后拒绝及恢复原子性。`test_object_actions`扩展两原过程互斥、共同投影/终态、施工位置改变和材料守恒；运行层只补普通候选替换退役旧handle和恢复deadline。

初轮暴露并修复通知数组类型及旧signal对象已释放后的断连接错误；一次测试错误地把取消命令的幂等重试当作新动作，改为独立新command验证占用，未改变原重试规则。脚本错误按包装器门禁处理，没有把runner显示PASS当作通过。

- `logs/stage1-core-tests.log`：原取放/施工/对象查询3组445断言通过。
- `logs/stage1-contract-tests2.log`：新空间、共用行动及施工3组357断言通过。
- `logs/stage1-integration-tests.log`：空间、普通物品面板、身体朝向、大兽查询、施工运行、房间和本地移动7组607断言通过，包装器0退出。其后补通知首次准备前/失败重建后仍有效及终态回调替换守卫；`logs/stage1-final-targeted.log`最终3组443断言通过，包装器0退出。

## 普通Main与完全停开

Godot AI核对Reol工程、Godot4.7.2 stable和官方插件4.4.1后启动普通`scenes/main.tscn`。按需脚本[world_space_acceptance.gd](https://github.com/fewnfds/reol/blob/8c3deaa972f932e999167b61ea6b166b928cfe5f/tools/qa/world_space_acceptance.gd)通过实际开发编辑适配器、普通物品面板、行旅与施工簿操作，不进入每次回归注册表。

`write`创建两格长石板、通过非锚格移除另一个原物、普通耗时取起；随后实际走到库房、登记工地、落图、取料并开始木床施工。两个过程均保存进行中checkpoint，再记录完整联合未来。完全停止游戏进程、重启普通Main后执行`read`，分别恢复两份档并按同一时间继续；checkpoint和完整未来SHA256均相同，原截止时刻为60000与243448ms，旧空间handle失效。当前根52/区域43/村落7不变。

证据在`logs/world_space_stage1/`：`expected.json`、`read.json`、两份checkpoint及handling/construction的pending、完成和restarted截图。主代理实际查看取放进度与施工簿截图，确认真实界面；审查修复后的最终代码再次完整write/read通过，四份完整快照SHA与首轮相同；当前干净运行的Godot AI game log只有helper注册信息。早期探针误读一个不存在的诊断属性导致debugger break，停止该进程重启后修正；验收脚本首次传`res://`给文件保存被拒，改为既有绝对路径接口后通过，未改产品存读校验。

一次普通512²世界的两格查询短样本：1000次共59834µs、总工作6000单位（每次6），约0.060ms/次。首次重建另计，不扫描全部地面物；这是局部CPU短测，不代表大量动态单位、联合帧时或16GB整机验收，也未声称GPU收益。

## 最终版本与交付

代码`fa45228b35fd42c090e1e297f47b211fcb6b8fb7`已执行一次原生`gpt-6.1-sol`/custom只读静态审查（`logs/stage1-native-review.log`），审查未运行引擎/测试/CI。3项P2均有效并修复：多鸟/大兽同批跨格的通知期间明确拒绝查询，全部链接完成后才允许完整查询；来源时钟领先世界的正常区域移动仅更新原几何，不再触发全量重建；候选逐个计费，低预算不先复制密集格全集。

`logs/stage1-review-regressions.log`复现并保护这些反例，连同原对象查询/取放/大兽/玩家身体共5组635断言通过，包装器0退出。有效修复在`5fd6e3152464fd30320ac858d28c19caaea46559`，不另启动第二个主要审查；起点main的CI42365643089在真实提交检查点复用终态success。阶段分支只在最终证据提交后一并推送，远端结果待后续真实提交检查点核验。不得把旧SHA绿色当作新代码通过。

首轮完整check（`5fd6e3152464fd30320ac858d28c19caaea46559`，`logs/stage1-full-check.log`）用时约1287秒，249组全部执行，248组通过；唯一失败组`test_heat_topology`有9条自主权释放断言和同源脚本类型错误。原因是旧夹具用简化RefCounted Authority调用新的强类型共用合同；实际原世界相关组通过。夹具改为最小RegionalSimulation派生、保留原热观察者/账本和全部断言，补真实起止时刻与终态断言；没有修改产品代码或放宽门禁。`logs/stage1-topology-final.log`该组205断言通过，夹具修正在`f50f0a84085294faf72e6315e99aa5343e7dbf15`。

最终`python tools/godot.py check --test-timeout 1800`在该准确SHA完成：**249组/125102断言/0失败**，结构317份当前文档/491脚本0错误，import=0、test=0及包装器脚本错误门禁通过，约1286秒。日志`logs/stage1-full-check-final.log`、`logs/check-test-20261107-204221.log`及对应逐组timings保留本机。未并发引擎；两次长check和原生审查均由一次工具内部持同一handle等终态，模型未固定间隔查询、数PASS或轮询CI。

本阶段plan/coding/review/验证已交付，后续Markdown记录随分支推送，不自动合并main或启动下一阶段。源码/测试与准确受检提交相同；本阶段没有新增外部依赖或复制第三方代码，日志/凭据/存档/截图均不入库。

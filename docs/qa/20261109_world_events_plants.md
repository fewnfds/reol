# 全局事件与植物框架验收

## 受检范围

2026-11-09，`codex/world-events-plants`基于`66f56b94a259db9a72e707ba0c09362bf808ed6e`，承接已完整验证的通用存读底座；主体提交`801d71e971136e52eab594f4049d2d4f6cef0856`。Godot4.7.2 stable / Python3.14.3。原生主审及修复完成，最终产品/测试为已推送的`45f140b90aa1fb6d4adbf3d028efac12ae25aa9c`；本次文档提交准备点核得对应CI仍in_progress，完整覆盖待验；最终版本以BASELINE/HANDOFF为准。

全局规则队列`SimEventQueue`与可信目录`SimWorldEvents`首先服务运输评估、植物觉醒两个领域；连续过程与实际效果仍归原owner。会话内容包3包含44份定义/开局，移动、值事房和约练不混用当前磁盘。根54/区域45，旧根53缺事件/植物因果而明确拒绝，不补造历史。

植物领域包含生境、物候、有限水、伤损/年生寿命/根桩、原库存产物、花盆、有限行动、共享环境profile、空间、观察和最小灵智组合。普通草木不创建NPC、主体、背包或Node。框架行为只在[事件合同](../engineering/event-contract.md)、[植物合同](../engineering/plants-contract.md)维护，不在此另立计划。

## 定向证据与修复

| 范围 | 结果 | 日志 |
|---|---|---|
| content_bundle / natural_world_runtime / plants / world_field_save_boundary | 4组689检查，0失败，包装器退出0 | `logs/test-20261109-162454.log` |
| 建筑、时钟、施工、事件、灌溉、植物、内核、工作场所、世界连续性 | 9组754检查，0失败，包装器退出0 | `logs/test-20261109-162658.log` |
| event_queue / plants / terrain_edits / world_object_query | 4组328检查，0失败，包装器退出0 | `logs/test-20261109-163047.log` |
| 会话A/B规则闭包 / events / plants | 3组253检查，0失败，包装器退出0 | `logs/test-20261109-163529.log` |
| 花盆直接采走后恢复、移栽/损毁/行动、植物其他owner合同 | 1组75检查，0失败，包装器退出0 | `logs/test-20261109-163856.log` |

以上对应各步代码，不相加冒称最终完整回归。审查修复后`test_event_queue`和`test_plants`为2组114检查/0失败、包装器退出0，日志`logs/test-20261109-170408.log`；最终产品Godot定向汇总6组523检查/0失败、原日志无SCRIPT ERROR/ERROR（`logs/test-20261109-173939.log`），覆盖content_bundle、events、私水照料UI、natural_world_runtime、plants及settlement_services_runtime。

永久反例主要归`test_event_queue`（最小独立queue）和`test_plants`（最小双区域fixture），普通Main接缝复用原运行测试。新增fixture使用加速定义时也同步有效开局，不放宽生产校验。曾因新增开局校验暴露fixture的旧生长年龄，与更新后的定义不相容；修正fixture后通过。

已修真实问题包括：预算工作回执为0、JSON浮点版本被整数集合拒绝、自引用Callable环、旧植物通知未解绑、同格草木与旧布局冲突、花盆采走只释放单侧关系、损毁支撑未先结旧区间，以及单株动作重建全体索引。生产存读仍复用原registry/候选/文件层，没有重新实现SL。

最终定向的外围捕获器在打印已完成日志时发生GBK编码错误并退出1，不能把该捕获器称为成功；原始Godot及计时终态完整落盘。后续原生两进程已独立执行，并使用UTF-8输出与错误/退出码门禁，均退出0。完整游戏验收仍交准确SHA CI。

## 完整CI归属

最终45f140b的[CI42595092906](https://github.com/fewnfds/reol/actions/runs/42595092906)在真实文档提交准备点经`tools/ci.py status --run 42595092906 --sha 45f140b90aa1fb6d4adbf3d028efac12ae25aa9c`核到in_progress、完整headSha一致；尚无终态，不能称完整回归通过。推送后只做过一次未登记run发现，随后按真实提交检查点查询；没有时间轮询或等待器。后续仅Markdown不改变本包产品/测试，仍须核该run终态。此包Goal保留active，缺准确完整结果时不提前标完成。

## 原生静态主审与修复

一次主审针对主体完整SHA，Sol/custom，审查会话`01a1bf7c-3027-7143-83b3-987796305808`。首轮因宿主`registered Core launch requires an installed app`未读到差异，不算通过；接续同一会话提供精确提交差异和关键完整源码，完成静态分析，退出0。日志`logs/world-events-plants-review-801d71e.txt`、`logs/world-events-plants-review-resumed.txt`，审查器未启动引擎、测试、CI或递归审查。

确认并修复四项P2：过湿休眠不蒸发、目标旧区间结算后未重新验行动、自然死亡产物进度未归一，以及觉醒后仍留不合法作业。新反例先在主体代码复现8项断言失败（`logs/test-20261109-170338.log`），覆盖四条实际路径及外伤立即释放；修复后114检查通过。补充代码由主代理核对受影响路径，不重复整包模型审查。

首次完整回归第2片因`test_herb_ecology_migration`继续读取已交接的旧生态`water`而脚本报错，夹具未释放导致后续clock executor占用失败。生产模型未改；该测试更新为现行交接的双增长/孤引用/缺身体/未来出生/注入旧水账及未背书消耗等11个原子拒绝反例。原v32 fixture保持只读；更新后定向95检查/0失败、退出0（`logs/test-20261109-171621.log`）。首片的生产/内容/测试经digest核对无变化，只有第2片该suite修改，后续重跑2–12片；首次失败不计最终通过。完整脚本的控制台GBK编码报错仅影响失败摘要，原worker日志已完整落盘。

续跑2/3片退出0，第4片的旧照料测试同样直接读取退役生态并污染后续fixture；追查同时确认原采集页未转接私水照料。收尾补原按钮→共同植物作业、真实进行中状态/完成通知、可见植株投影及正确工时提示；保持私水、原身体控制、取消和无公差奖励。已知资源地点允许从远处动身，任意独株仍限当前观察。更新后的实际UI回归41检查/0失败、退出0（`logs/test-20261109-173833.log`），并验证完成后的完整候选可加载。本机未形成最终全套通过，最终完整覆盖改由收尾提交的12片CI承担，不把上述部分结果相加或复用为最终结论。

## 原生Main、观察与完全停开

驱动为[world_events_plants_probe.gd](../../tools/qa/world_events_plants_probe.gd)。Godot原生进程运行该脚本，退出后独立运行加`-- --resume`；外层145秒超时，脚本120秒真实计时器，均退出0且无SCRIPT ERROR/ERROR。

最终生产45f140b原生两进程通过。普通人身开局6株，其中原野药/野稗交接4株，赤叶草和古树各1株。共同推进60000ms，显式事件为原古树建立一次主体。观察赤叶草后启动真实跨区行旅；预算1保存经86帧结清至60075ms，原暂停保持，恰有一次成功回执。受检档位为独占`user://tests/world_events_plants_native_7245702.json`，未接触玩家档。

| 比较 | SHA256 |
|---|---|
| 原档、同进程恢复、独立停开checkpoint | `6c33bf3ec66229af11d706c837866994ef7c823f06329c849e5889131685bb9b` |
| 三路继续250ms后的联合未来 | `69a17adcd855f2c51670a96578be898fdc1b56d70cc54ea45904efddc09700db` |

hash覆盖规范化的整个regional world、clock及原玩家motion；未来比较恢复工作预算4096。日志`logs/world-events-plants-delivery-native.log`、`logs/world-events-plants-delivery-resume.log`，报告`logs/world-events-plants-native.json`。原生1280×720观察截图已实际查看：外观描述、目标选择、两列动作及收起按钮均在窗口内，未提前显示灵智/药性/五行数值。截图`logs/world-events-plants-observation.png`与停开截图留本机证据，不入库。

## 普通运行短测

当前QA驱动在原生恢复后等待402帧，确认地块加载/绘制队列为空，再暖机60帧、取180帧正常1×样本。6株、0个植物动作，条件采样周期60000ms；帧间隔P95 **16.751ms**、P99 **34.587ms**、最大34.759ms，公共时间前进1800ms，最大已受理待算50ms。引擎静态内存计数344535265字节，不等于进程峰值或整机占用。显式推进首分钟耗时749.816ms并跨15个呈现帧，预算1保存耗86帧；这些测量包含整个普通世界及QA开销，不是植物单函数成本或吞吐承诺。

首次采样尚在地块加载阶段，P95 38.060ms，不能与稳定样本混称纯模拟性能。一次尝试复用旧`world_performance_probe.gd`因其仍查询已不存在的旧环境`cell_count/storage_summary`接口而失败；没有按它报性能通过，也未修改旧证据。现行驱动使用实际原owner、预算/时钟和有限呈现队列，结果见上述JSON。

## 到期密度与预算样本

最终45f140b的一次性headless样本在原双区域fixture内装入1024株草本，把植物采样周期加速至1000ms，全部同时到期，无植物动作；不登记每次CI的永久压测。建株115.747ms，整世界capture/规范化JSON 392.619ms、1539444字节。独立恢复645.504/969.462ms；工作预算64分18次调用结清，总458.194ms、单次最大43.806ms，无界预算1次403.093ms。两路整个世界未来hash均为`7fb6b64460cb7f941c890b0ea855cef75b0504ba21a5aff9d195c9a1a4b0a4d4`。原始数据`logs/world-events-plants-density.json`，一次性驱动`logs/world_events_plants_density.gd`，退出0。

该样本证明真实due工作预算续算不丢不重，不能从1000ms加速采样推断默认60000ms周期的平均成本；原子环境/地区步骤仍可形成超过一帧的调用，未宣称密集动态世界稳定60FPS。未用删除回执、冻结远区或跳过植物换取数字。

## 验收限制

原生为D3D12 / RTX5060Ti；不是RTX3060、16GB整机或密集多年世界验收。六株开局只证明当前普通组合，植被覆盖整个地图的自然种群、繁殖网/食物网、根系流体、任意距离携带活株与完整树身人生未交付。条件默认每游戏分钟采样，年生寿命有精确边界；不声称逐毫秒生态求解。

全局事件不提供任意脚本DSL、故事导演、全事件重放或全世界事务回滚。多数旧原子回调尚不能抢占，历史回执仍需保留；大规模成本不由少量反例或headless通过推断。最终CI须按准确SHA另记，不能沿用前包绿色结果。

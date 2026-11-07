# 当前接续

核对：2026-11-07。**用户要求暂停，已停止实现与本机验证，等待讨论，不自动接续。** [普通接入小包](../plans/world-foundation/runtime-integration.md)首代码`f7baba0279fccb8d4592dc30194ddaa50dbf7f12`，最终修复`f641ddd035a588b504574df32617d708507cbd71`。按定义生成/移除受管实物已进原F8世界编辑；普通面板取放走同一生命周期耗时动作，移动/停止取消、截止触及/遮挡复验，多格、原身体、时间与普通存档不分叉。代码已阶段提交，停点文档提交后统一推送，不轮询CI。

本包干净隔离检出最终4组469断言0失败，真实Main/D3D12/3060双进程普通存读通过：实际F8/鼠标放置2×1物、普通取起517ms保存、完全退出后摘要一致、原动作完成后再普通放下；已观察编辑/进行中/恢复截图。一次原生Sol/custom静态审查P1“暂停wait后取放导致可写不可读”已修：成功启动清原wait、取放中拒新wait，失败点击不清wait。新增两种操作顺序回归通过，不再开第二整包模型审查。

首轮完整check因修真实P1主动中止，不算通过；最终修复SHA干净检出的完整check随后因用户要求暂停而主动停止，**完整回归仍待验**。结构295文档/475脚本0错误、导入成功；不要把主动中止的exit1当产品首错，也不冒称整套通过。所有本包引擎/审查进程已结束，日志/截图/临时脚本保全到`logs/framework_integration/validation-artifacts/`后移除本包临时检出。四WIP未混入。QA见[普通接入](../qa/20261107_framework_runtime_integration.md)。

新冷热/五行/GPU尚不能接管普通Main：旧设备、人物/植物、墙门屋面仍依赖旧热；新会话未接普通唯一时间/全部相关写入，守卫还拒绝生成/移除/材料，实际残留未进入普通存档。本包未强绑开发会话、未叠两份温度，未扩新压测、存档优化或玩法。材料拆合仍是权威接口，未做通用选堆菜单/NPC指挥。后续应补普通接缝并退役旧模型，不继续另起独立验收设施。

旧性能Goal继续paused/未complete，本轮是用户另行授权的小包，不恢复旧性能队列。上轮“当前快照/操作历史”提问已澄清：存档保存当前世界及在途状态，不靠重演全部历史；技术回执保留/归并属于工程取舍，不需用户改变世界法则，不能继续以等待概念拍板作为阻塞。当前没有改历史/去重合同。四份原WIP哈希保持。

## 前次性能工作与核验

[性能有限接续Goal](../plans/environment-object-loop/performance-followup.md)按用户“解决不了停下讨论”条件暂停收尾，**未complete**。A代码`9467cb9790229284ee24edd61cc48a45d809d1f0`用原逐格占用只读点查替代材料目的地桶扫描；128²创建4178.175→2694.914ms，512²真实创建44027.021ms、场2929.918ms、装配10979.623ms。4组定向9666断言0失败，Sol/custom静态审查无发现，原成本/数量/回执不变。

B两条轻量存读尝试没有显著端到端收益，全部撤回运行代码，`environment_response_file.gd`保持原字节/格式/校验。工具/测试代码`603cdff7a65672e486b831453ec9114a71ea1ade`仅增加显式`--snapshot --transport-profile`分项测量及字符串原格式字节/坏编码测试，默认不多读写。4组定向298断言0失败，Python守卫8项通过，一次Sol/custom静态审查无发现；64²独立候选完整存读通过。C多移动源吞吐未实施，不把静态建议或单源瞬时样本当通过。

前次[QA与停止理由](../qa/20261107_world_performance_followup.md)记录数据及当时的历史简化提问，未改变规则。最新真实提交检查点一次核对：A的[CI42269548713](https://github.com/fewnfds/reol/actions/runs/42269548713)completed/success；B的[CI42270554012](https://github.com/fewnfds/reol/actions/runs/42270554012)completed/failure，完整回归1800s超时，停在world_persistence且无最终汇总，不能当通过；准确SHA均匹配。未重复轮询或放宽门禁。干净检出日志保全到`logs/world_perf_followup/validation-artifacts/`后移除临时检出，四WIP哈希保持不纳入验收。没有证据证明必须换引擎或缩小整个世界。

此前[环境初建有限优化](../plans/environment-object-loop/cold-build.md)首代码2291ab9，最终`760cf7ed5c613ed2643b4dae1b6fb5c96277746e`已整合推送。最终[CI42223048834](https://github.com/fewnfds/reol/actions/runs/42223048834)在本轮真实提交检查点核为completed/success、完整headSha一致，前包完整CI不再待验；首代码CI42222372361未继续查询。前包6组定向10541断言0失败，Sol/custom均匀场work回退已修。以下保留前包范围和证据，不能代证当前修改。

同环境128²基础场14.041→1.927秒（约7.29倍），含来源装配14.658→2.606秒。最终512²真实262142材料堆+1实物：来源装配10.823秒，场2.916秒，逐件原生命周期创建69.385秒，全部基准83.652秒；峰工作集约2.062GiB/private采样峰2.102GiB，同10GiB守卫。完整测量与限制见[初建QA](../qa/20261106_environment_cold_build.md)。不是完整游戏加载/FPS或20Hz移动源证据，不把旧550.9秒与新分项直接计算倍数。

隔离检出的代码指纹与最终SHA一致，日志保全到`logs/environment_cold_build/validation-artifacts/`后移除临时检出，不维持第二套模型。四份原WIP哈希保持，未混入。下一步先讨论剩余来源装配/原物批量创建或大档编码/校验/恢复的独立小包，不因本次有效就继续无限优化；目前无证据需要简化世界法则或换引擎。多极值/大半径/多移动源常时吞吐及16GB整机联合负载仍未验。

此前[成熟模拟游戏调研](../../design/research/large_simulation_optimization.md)已完成；本包只落实CPU基础场初建，不扩存档格式、普通Main、携行/房间或玩法。大档编码/校验/I/O优化仍为后续独立候选，不自动连做。

此前[来源候选与大档内存优化](../plans/environment-object-loop/optimization.md)已按限定范围完成并停下讨论。最终代码`8ce9e031e03d706285a5bce2b5657ec4bf30d22e`（首代码992acf0）已整合/推送到`codex/world-engine`，四份原WIP字节不变、不纳入验收。14组定向25944断言0失败；一次Sol/custom原生静态审查P2已修。收尾提交检查点一次核得对应[CI42181067921](https://github.com/fewnfds/reol/actions/runs/42181067921)为completed/success、完整headSha一致：268组/134155断言/0失败，Python57项通过；本机不再重复整套。

最终512²、262142真实材料堆+1实物、半径16、32次单源变更与独立候选完整存读通过，同10GiB守卫内峰工作集5.734GiB（采样private5.884GiB）。单变更p50 0.244s/p99 0.350s，比旧p99 3.634s明显下降；累计CPU成本仍不足以代表20Hz大量携源。文件217.8MB，写137.3s、读85.1s、stage103.5s、重建599.4s；环境初建576.9s，来源/基础缓存占550.9s，仍很慢。首轮新文件在原物恢复OOM的失败保留，随后原账本材料紧凑回执才使同守卫复测通过，不提高预算凑绿。目标编译、packed列、流式文件及中断恢复合同见[接口](../engineering/environment-response-contract.md)，完整证据看[优化QA](../qa/20261106_environment_optimization.md)。

最终代码RTX3060真实渲染、两进程完整停开到同一9000ms未来，以及64²基础目标GPU全格参考/局部变化均通过。30份代码指纹一致。所有引擎/审查/基准已结束；隔离检出`logs/environment_optimization/dev`日志保全到`logs/environment_optimization/validation-artifacts/`后移除，不维持第二套运行模型。普通Main仍用旧Q；携行、材料环境事务、房间、生物后果未扩。

前包后的来源/基础缓存全域初建热点已由本轮有限优化改善；大档加载与其他未验范围仍按当前页首及新QA解读，不自动沿旧Goal/旧QA连做。

## 前包与证据入口

本轮起点为d4ea4df；此前连续响应功能代码98e7135/0d8c035已验，失败和限制保留在[前包QA](../qa/20261105_environment_response.md)，不将其中“下一步/未优化”理解为本轮仍未实施。普通Main与开发会话的区别仍适用；新优化实际范围按本页首段、BASELINE及本轮QA解读。

## 已完成基线与边界

- 第一阶段A–E按声明范围完成：原身体/物品/库存/账本与整数毫秒唯一，统一对象/空间查询、受控生成/位置/数量、耗时动作、候选存读、普通Main离返/完全停开及有限规模出口。见[联合出口QA](../qa/20261105_world_foundation_exit.md)。大型动态体仅1/4/8，不外推全世界NPC。
- A1真实地面来源投影 `8bf7aa2a012af393fbc1b96fea6220aa18825833` 完整check255组/98618断言0失败；后续CI42008084331准确SHA成功。
- A2a来源缓存修复 `3636dc37ea498fa1f57c1d970fca6e50289aff93` 完整check257组/99000断言0失败；CI42026400068准确SHA成功。
- GPU接入修复 `9b3e724ce7e405d01b885e9b3e477b8afa09b226` 独立检出完整check258组/107976断言0失败，1105.781s，无ERROR/SCRIPT ERROR；一次Sol/custom审查的无关背包转账重启计算问题已修。3060的10案例6144格43008通道通过。512²满密度/半径16基础目标CPU20.65s、GPU0.616s，来源装配仍7.4s，不是Main FPS或动态每50ms全图更新证据。见[计算QA](../qa/20261105_environment_ground_compute.md)。

原性能/失败/审查证据在各QA链接及 `logs/environment_a1/`、`logs/environment_a2/`、`logs/environment_ground_gpu/`；历史独立检出已保全日志后移除。GPU修复SHA最近一次真实方案提交检查点只查到无匹配run，不称CI通过；本机同SHA已完整验收。CI只在真实提交检查点查一次，未终态留待下次，不按时间轮询。

## 必须保护的原WIP

原始SHA256在主工作区 `logs/world_lifecycle/protected.json`。下列四份不属于本包，保持字节不变，不混入提交或准确SHA回归：

- `scripts/sim/environment_field_cache.gd`
- `scripts/sim/environment_temperature_state.gd`
- `tests/sim/test_environment_field_cache.gd`
- `tests/sim/test_environment_temperature_state.gd`

本包只复用它们已提交的HEAD接口。若未来需要修改，先重述范围并明确保护/整合办法，不能偷偷纳入已有草稿。

## 当前概念与后续边界

- 方格地图/建造＋原人物权威子格位置＋按格环境缓存；不恢复全对象强制格心/移动纯动画结论。未来携源可按权威跨格时刻切换，实际驻留留下环境残留；当前只做到期瞬时转移，不假称走路尾迹。
- 五行逐通道max；冷热单signed等级，两侧max相减映射当地背景；五行火不等于热。实际值按共同时间建立/消散，残留不是复制来源，同类数量不放大辐射。规则在[环境](../../design/rules/environment.md)。
- 首包开发会话封闭访问原world；原公开对象不是通用隔离API。等待期间仅最后完整view可见，保存busy，已执行边界阶段不重跑。普通Main、完整过载治理、材料拆并、携物整体遮掩/中和、房间、生物后果仍未接。
- 普通存档schema51/区域42保持；开发验收快照不等于正式普通存档迁入。失败候选不改活世界，历史版本按[兼容政策](../engineering/compatibility.md)有限退役。

下一步由本包实际测量和讨论决定，不从旧Goal/历史QA自动连做。当前不宣称完整游戏、45–60分钟切片或Windows独立发行已完成。

# 构建、兼容与验证基线

核对：2026-11-09。采用版本与准确代码证据记录在此，操作范围见[FEATURES](features.md)，当前停点见[HANDOFF](handoff.md)，详细日志和限制见[QA](../qa/README.md)。历史分卷只描述当时版本。

## 共同时间过载降速（已合入main）

`codex/adaptive-world-time`基于main `2c4ea10723d8140c5ae4b5f4c599f156d2ea6e5b`，共同时间已接有限准入、负载倍率和6ms合作式宿主预算；普通显示/HUD沿同一流速。根53/区域44及原状态owner不变，宿主负载估计不入档。最终定向8组796检查/0失败、包装器退出0；原生人工负载实际速度0.162×、帧间隔P95 17.600ms，移除后准入倍率恢复1×；同进程及完全停开250ms未来hash相同。产品/永久测试`f4257e38a1665c08c8596028fe71c0cea0dbeab9`的[CI42542611182](https://github.com/fewnfds/reol/actions/runs/42542611182)已核completed/success，完整12片通过；一次Sol/custom原生静态审查退出0，无可确认修复问题；已按用户授权快进整合main。产品/永久测试保持该SHA，后续仅QA帧驱动与文档，后续推送SHA的CI另行登记，不继承为已通过。细节和限制见[QA](../qa/20261109_simulation_pacing.md)。

## 共同结算内核（已合入main）

`codex/settlement-kernel`基于main `a4fb83a6c29e3203bf71fc1c1f950afe4906830b`，最终生产代码为`d99ac6492ad5dbe5ba1af5bcc00171b5753c28e4`，最终测试提交为`38606ea342f09e5aadcb50112df6620ddafbe10f`；最终测试SHA的[CI42508829722](https://github.com/fewnfds/reol/actions/runs/42508829722)已核completed/success，251组/125351检查/0失败；其后至`8cc40919599680d57e1f333f1482ebab38df7e3b`只有Markdown差异，已快进合入并推送main。共同时间、结算阶段/依赖与预算续算已接普通Main，原身体、库存、伤势、环境及动作继续归各领域；部分边界不能捕获新存档或原地恢复，帧间完整会话加载仍可由独立候选替换，根53/区域44未变。[QA](../qa/20261108_settlement_kernel.md)记录准确版本、日志和限制。

当前代码已修普通停止入口绕过屏障、施工通知与画面提前发布、FAILED后宿主无效续算三项跨层边界，并补齐收尾审查的两项P2：`CommittedWorldCanvas`在完整clock发布时同步捕获，`_draw`只回放；PENDING/FAILED期间命令提示立即显示，世界事实保持最后完整投影。内部索引通知仍同步，外部完成通知沿完整边界发布；失败终态暂停并显示原因，合法会话加载可恢复。`tools/godot.py check`导入失败立即退出，不再启动后续测试。最终定向6组**782检查/0失败**、包装器退出0，Python完整**73项通过**。

最终完整回归**251组/125351检查/0失败**，12片包装器退出均0，完整覆盖聚合退出0；1554项输入前后digest一致，证据目录`logs/settlement-close-delivery-full-20261109/`。生产代码保持d99ac；后续仅调整3个独立测试suite，原前1–8片中未受影响的证据经逐路径及选组核对后复用，涉及失败owner的4/7/9片均在相应suite最终内容下完整重跑。未混用旧`68fa8d3`或`0062ac5`生产代码报告。

同一代码普通Main预算1与不限预算的完整未来一致；完全停止游戏进程后独立载入，checkpoint `ac5955affae9a0f9b436ecb27db9c51d2bcc516546a9a7b898126fea2d1e4105`及随后5000毫秒未来`6dca1aa17d52f7cc22c955b885ecf1e1496a1b3ce8af4c24d3a4de5066226d7a`均一致。真实施工部分/完整发布验证通过；另以预算1运行240帧，连续6次clock与canvas发布一致。RTX3060普通600帧样本间隔P95 **17.943ms**、P99 **18.883ms**、最小1.197ms、最大22.241ms；模拟6100毫秒、126个边界，结束无pending。只证明该短样本，不代表密集世界、长期历史增长或16GB整机目标验收，也不与旧短样本作性能提升结论。

原内核实现和收尾差异各完成一次Sol/custom主要审查，有效问题均已修复；收尾两项P2由d99ac修复并有定向和原生反例证据。审查及原生验证已完成，不重复整包审查。

CI已改为12片，完整覆盖及漏片反例工具验证通过，CI42508829722实测12个worker同时运行，worker墙钟108–202秒、覆盖聚合5秒，run创建至更新213秒（3分33秒）；不是所有未来运行的保证。原始job元数据和下载的12份完整报告在`logs/actions-node24-upgrade-20261109/`，覆盖汇总再次核通过。旧暂停分片及因审查问题中止的`0062ac5`回归只保留历史证据，不算最终通过。推送及集成状态以HANDOFF和Git为准。

主线结算集成点`8cc40919599680d57e1f333f1482ebab38df7e3b`的[CI42538304156](https://github.com/fewnfds/reol/actions/runs/42538304156)也已在本轮真实提交准备点核completed/success；与上述分支最终测试SHA的CI分别记录。

## 官方Actions Node24升级

代码`dc2558b219cb2fbdf164c2d63371e01b0cff8226`已合入并推送main，只修改workflow。四个官方稳定release精确提交的签名、`action.yml`均核通过；六处调用使用`node24`且输入合法，原触发/权限/引擎/Python/12片/ZIP报告语义保持。一次Sol/custom原生静态差异审查无可执行发现，日志和YAML/输入比对在`logs/actions-node24-upgrade-20261109/`。本轮未重复本机Godot全套；本包真实提交准备点已核同SHA的[CI42539000023](https://github.com/fewnfds/reol/actions/runs/42539000023)为completed/success；终态缓存复用。[维护规则](../engineering/tooling/maintenance/01-updates.md)解释运行时与升级边界。

## 通用建筑与组合空间（已合入main）

main包含建筑阶段最终受检代码`d00bac954b69cab096d580db002fb04013fa2543`：定义/实例/能力分开，多格/朝向、多工地/用途，独立空间事实、操作位/桌椅、原库存储藏、工作台接原生产、耐久/防护/损毁已接普通Main。13类定义、两种材料，框架出口和实际限制见[本阶段QA](../qa/20261108_building_framework.md)及[建筑合同](../engineering/construction-contract.md)。

准确代码本机4片顺序完整check **250组/126290断言/0失败**，各worker结构、导入、脚本错误/超时及退出码均通过，独立覆盖汇总核250组无遗漏；总墙钟约3282秒，最慢片约1185秒，没有放宽单片1800秒门禁。首次单进程全量因夹具/非热通知错误及1800秒超时未通过，修复与证据保留在QA。一次Sol/custom原生静态审查的3项P2/1项P3均已修复并用反例验证。

最终d00bac普通Main多格施工、座位使用、存箱三案均在完全停止游戏进程后独立恢复，checkpoint、原截止时间与整个联合未来SHA相同；RTX3060原生1280×720界面已查看。[CI42457788038](https://github.com/fewnfds/reol/actions/runs/42457788038)已在本轮整合检查点核completed/success，完整headSha与d00bac一致。此后至主线集成点只有Markdown差异，受检代码/数据/测试保持不变；本轮未重复游戏验证。

## 当前集成代码

当前结算集成点为`8cc40919599680d57e1f333f1482ebab38df7e3b`，已推送；以下建筑与空间记录保留各自来源。用户授权后，main从`2e6b6a61caf11b5560c15a97f1a58cb156a7300b`快进并推送到建筑阶段证据提交`eb330ee9c38fa3a5cc72004372ddeefd70409b1e`，其后有阶段整合Markdown；结算分支基于main `a4fb83a6c29e3203bf71fc1c1f950afe4906830b`，已在上述集成点合入。实时指针以Git为准。已完成的前期开发分支均在main历史，旧争环WIP及原命名stash仍受保护。

主线[CI42473540525](https://github.com/fewnfds/reol/actions/runs/42473540525)的headBranch为main、完整headSha为`eb330ee9c38fa3a5cc72004372ddeefd70409b1e`，已在本轮真实提交准备检查点一次核得completed/success；本包不是该SHA，需独立证据。阶段整合文档结构/链接/大小检查覆盖319份现行文档、495脚本入口，0错误；这不是新的游戏回归。

前阶段共同空间集成点`2e6b6a61caf11b5560c15a97f1a58cb156a7300b`的[CI42375335176](https://github.com/fewnfds/reol/actions/runs/42375335176)已核同SHA completed/success；该次合并在建筑开发之前完成。

前阶段共同空间最终代码`f50f0a84085294faf72e6315e99aa5343e7dbf15`的249组/125102断言/0失败、一次Sol/custom审查及两案完全停开证据见[阶段QA](../qa/20261107_world_space_actions.md)。该能力现已在main；旧QA的“未合并/远端待验”只记录当时状态，不能覆盖本页。

## 术语与运行入口

受检代码`771a587d20a38998845331fb214cd886d361d876`：普通环境成员和调度domain统一为`RegionalSimulation.environment_fields`；区域存档键`local_heat`通过codec映射，现行schema不变。术语/真实代码映射见[唯一入口](../engineering/terminology.md)。本包import与定向10组1203断言通过，RTX3060真实HUD确认灵气文案，一次Sol/custom静态审查无发现；完整CI尚待准确SHA，证据见[QA](../qa/20261107_terminology.md)。该整理不新增游戏机制或改变main集成范围。

## 测试工作流与成本

测试提交`f166cdb4360e91055a3f942cedf66ae446f2301e`与受检快照`2b9828040343e53a469ec8cdce5f12df16656e31`的完整tree一致：4片完整覆盖本机**248组/124981断言/0失败**，各worker日志/退出码与汇总校验通过，Python72项及错误退出smoke通过，一次Sol/custom静态审查无可执行发现。组内合计1495.275→1325.163秒；受改两组重复装配合计减少40.751秒，其余波动不全归因代码。4片最慢组内466.318秒，本机顺序验证不等于GitHub并行实测；一个未改组的预算循环断言次数波动已定位，固定检查/结果出口没有减少。范围、完整证据与远端待验见[优化QA](../qa/20261107_test_optimization.md)。生产代码及存档格式未改。

前序受检代码`b60adadfcab73a17e101b62538da62ddc5bccf9f`建立248组精确选组和逐组计时；当时Python60项及有界五组54894断言通过。其后纯文档提交`d27337d67c0148132dfaef2d802d72a860b62d38`的[CI42356120868](https://github.com/fewnfds/reol/actions/runs/42356120868)已在本轮真实提交检查点核completed/success，完整SHA相符；不替代后续术语和分片版本的远端结果。五组实测与限制见[成本调查](../qa/20261107_test_cost_audit.md)。

## 顶层稀疏执行框架（已集成）

代码`ee3504d3c313aa07ac4e87caec3bd39488c725e3`在`codex/sparse-world-execution`建立通用owner-local能力参与/活跃/到期/变脏索引，普通环境与健康接入。准确代码本机完整check **248组/124980断言/0失败**，一次Sol/custom静态审查无有效发现；普通两次来源操作短样本224/221ms→8.081/7.173ms，无GPU。存档字段/版本不变、恢复重建派生索引；未把其他旧域自动迁入，不代表满密度或16GB整机验收。

本轮真实文档提交检查点核得[CI42345202281](https://github.com/fewnfds/reol/actions/runs/42345202281)，完整headSha`2f305de8efcbd8e51c290bbeae73cc5531fc2996`一致，终态**failure：测试1800秒超时（test=124）**。该head与上述本机受检代码只有文档差异；Python工具测试和导入完成，但Godot没有完整终态汇总，不能称远端通过。末条RUN为`test_terrain_edits`，不足以证明超时根因。未重跑/轮询或放宽门禁；日志与限制见[QA](../qa/20261107_sparse_execution.md)。

## 普通环境接管基线（已验收并入main）

最终代码 `6137481a07ec98b372e32ca857e546f1e1b07ee1` 已使普通Main接唯一室外冷热/五行场，原物与材料变更、人体/野药温度、共同时间及普通存档共用当前模型。保存拒绝未完成事务；旧根1–51明确拒绝，原档保留。准确SHA本机完整check **244组/124778断言/0失败**，1174源文件前后不变；同SHA双进程普通Main存读同未来、RTX3060真实画面与600帧联合负载通过。一次Sol/custom静态审查的3项有效发现均修复。普通单次生成/材料变更仍约0.22秒卡顿；不代表满密度或16GB整机验收。最终[CI42337874837](https://github.com/fewnfds/reol/actions/runs/42337874837)在后续真实调查文档提交检查点已核completed/success，完整headSha6137481一致；本包本机与CI均有准确代码证据，不重复测试。集成点`ffe7e8c705d2d7259dfb77dcfba3dd0a64c9c61c`已并入并推送main，之后仅更新文档；停止点查[HANDOFF](handoff.md)，完整证据与局限见[QA](../qa/20261107_world_engine_finish.md)。

## 采用版本与存档

- Godot **4.7.2 stable** 是这次采用和验证的版本；长期跟进最新稳定版，每次升级需核插件、CI与导出模板。当前是 GDScript、Windows 本机开发，CI 为 Linux headless；Windows 正式独立包未验收。
- 当前普通联合根存档 schema **53**，区域 **44**、村落 **7**、场状态 **4**（`outdoor_fields_v1`）、环境受体状态 **3**（climate **2**）、器物状态 **8**。内容包 **v2** 固定包含39份定义/开局及来源digest；部分动作等规则仍直接读取项目文件。当前只接受根53；旧根52因建筑模型、1–51因环境模型明确拒绝；[兼容政策](../engineering/compatibility.md)不承诺永久迁入链，真实fixture保持只读。
- 本轮起点 `2483a3771bc9f469509293a514fb0a059eefe095`。原环境缓存、温度及两测试的四WIP已备份并与原工作区字节核对，不混入隔离实现/验收。分支快照见[分支状态](branches.md)，当前操作以HANDOFF为准。

## 历史里程碑入口

当前验收只看上面的主线/分支版本；以下QA保留各自当时的范围、失败、性能与CI，不能把其中“未接Main、pending、下一包”当作当前状态。

| 历史主题 | 证据入口 |
|---|---|
| 世界骨架、空间查询、生命周期、联合出口 | [对象](../qa/20261105_world_object_contract.md)、[生命周期](../qa/20261105_object_lifecycle.md)、[第一阶段出口](../qa/20261105_world_foundation_exit.md) |
| 环境来源、基础缓存与独立GPU | [来源](../qa/20261105_environment_source_bindings.md)、[缓存](../qa/20261105_environment_ground_cache.md)、[计算](../qa/20261105_environment_ground_compute.md) |
| 连续响应、密集负载及有限优化 | [响应](../qa/20261105_environment_response.md)、[优化](../qa/20261106_environment_optimization.md)、[冷建](../qa/20261106_environment_cold_build.md)、[性能接续](../qa/20261107_world_performance_followup.md) |
| 普通接入与环境主线收尾 | [运行接入](../qa/20261107_framework_runtime_integration.md)、[最终主线验收](../qa/20261107_world_engine_finish.md) |
| 本轮顶层稀疏执行 | [框架验收与普通入口成本](../qa/20261107_sparse_execution.md) |

旧完整基线流水可从Git的`2f305de`版本文档追溯；不在当前入口复制历史全文。早期分卷仍在[baseline-history](../qa/baseline-history/README.md)。当前技术缺口集中在[技术落地总表](technical-status.md)。

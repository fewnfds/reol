# 构建、兼容与验证基线

核对：2026-11-10。采用版本与准确代码证据记录在此，操作范围见[FEATURES](features.md)，当前停点见[HANDOFF](handoff.md)，详细日志和限制见[QA](../qa/README.md)。历史分卷只描述当时版本。

## Demo反馈与独立诊断（独立分支）

FPS后续包：顶部原生读数与F3帧间隔/峰值，一组17检查及实际画面、按键/暂停只读通过。约110–120FPS下位移约20Hz，玩家显示插值仍缺；小场景流速不证明规模达标。主审/完整CI待验，证据见[QA](../qa/20261110_demo_feedback.md#fps显示与呈现频率核对)。

`codex/demo-slowdown-fix`最终生产/测试`b364870e5ddc92f3c3de2d689fcf3e2755e8d67d`已推送，修复重复画面捕获、环境原子刷新及短片段误降速，未合main。原生90秒0.986×、时钟最大17.645ms，30秒移动39格无world_errors；定向通过，一次Sol/custom主审的灵体读档旧flora回调P2先红后绿修复，补1组42检查通过；同SHA CI42757726701本次文档提交点观测in_progress，完整CI待验。负载、日志及局限见[缓行QA](../qa/20261110_demo_feedback.md#严重缓行修复)。

main集成点7def7d2的CI42751032965已核success。前Demo分支`codex/demo-playtest-fixes`的默认跟随/外墙修复87262ff：4组112检查、原生画面及一次主审通过，CI42751769110 success。独立诊断最终aa4f1a1：同未来/回调恢复、有界smoke及原生采样通过，一次主审的等候CPU漏计P2先红后绿；CI42753794423已核success。详见[QA](../qa/20261110_demo_feedback.md)。以上未合main，连续坐标迷雾仍未改。

## 完整单位行动与交互（已整合main，完整CI通过）

前版0a0b59a的CI42674488111为completed/failure，两处为休息阶段显示和旧直行测试。收尾`0856effd4b2bb135c9bae8f25cccbba0e3def8e0`先复现再修复：休息/服务运行2组88检查、最终感知108检查通过，一次Sol/custom同会话恢复静态主审无可操作发现。[CI42750266714](https://github.com/fewnfds/reol/actions/runs/42750266714)在本次试玩修复提交点精确核为completed/success；完整CI通过，不按时间轮询。

`codex/unit-actions-integration`主体`68fff8b35e90617f4e95b416cdacf73834e6bf5e`及上述收尾已按用户授权整合main；根56/区域47/内容包3/环境5。原生搜索、路线重评、共同动作投影/终态/停止及原库存搬运已接；主体一次Sol/custom主审2项P1/1项P2先红后绿，修复5组223检查通过。前版普通Main及独立停开整个检查点/未来一致，详见[行动QA](../qa/20261110_unit_actions.md)。整合不等于完整回归通过，不能沿用前阶段绿色。

## 环境跨领域组合（已随行动历史整合main）

`codex/environment-composition`承接事件/植物历史，主体`2ec88b7efec3724b065224443fbbbaa820d8f0c6`、阶段最终生产/测试`89f47163d30e172d0b858fdf8167b84ae8c208bd`已随行动历史整合main。原环境接材质传播、一房一温、容器/携物及植物照明，阶段根55/区域46/环境5。原结算、事件、空间和通用SL继续持原职责；没有新增中央世界或物理引擎。

主体完整check3600秒超时且有失败，不能算完整回归；一次Sol/custom主审的跨格时刻/空间复制两项P2已修。修复后22组3761检查通过；普通Main及独立停开整个未来相同，6株180帧P95 16.753ms，不代表密集整机验收。详见[环境组合QA](../qa/20261109_environment_composition.md)。最终HEAD337ea13的CI42659346260为completed/failure：11片通过，test(1)的`test_world_persistence`因两个phase initial末位漂移失败，coverage跳过。诊断发现Godot decimal解析不保持这些double，行动包沿原模型量化恢复修复并补反例；本结果不能算完整通过。

## 全局事件与植物（已整合main）

`codex/world-events-plants`主体`801d71e971136e52eab594f4049d2d4f6cef0856`，审查修复`e2512a18e3fcafad04fbf38ed44c2d1b2d9e010a`，阶段最终生产`45f140b90aa1fb6d4adbf3d028efac12ae25aa9c`、最终测试`13d675e6f49be9ebe42a3bd958d9d8ff3be6266b`已随行动历史整合main。阶段根54/区域45/内容包3。全局事件接运输/植物，移动/值事房/约练规则绑定会话；植物接原株/物候/残根/产物/花盆、空间/环境与最小灵智。

最终测试SHA的[CI42596694569](https://github.com/fewnfds/reol/actions/runs/42596694569)已核completed/success，**12片完整256组/126555检查/0失败**，下载报告独立覆盖校验通过。run墙钟287秒；受影响5/7/10片本机check也通过，不与旧失败run拼接。旧CI42595092906的三处fixture遗漏已修，生产代码保持45f140b。

一次Sol/custom原生静态主审的四项P2有先失败再修复反例。定向6组523检查，补移栽/待觉醒/真实年界后植物101检查、相关4组207检查均通过；原生观察及完全停开后的整个世界/clock/motion检查点和250ms未来一致。6株180帧P95 16.751ms，1024株due预算/无界同未来；单次原子工作仍可能长帧，不代表16GB/RTX3060密集世界。准确日志与限制见[QA](../qa/20261109_world_events_plants.md)，停点见HANDOFF。

## 通用存读模块（已整合main）

主体`96a6fe0ed891dd386cf455b4f389449d74f5b878`、拒绝提示收尾`d682e030a5e28dfd04a5101bb5f826e37958422b`已随行动历史整合main。统一领域capture/stage/check/install与安全保存请求/回执，阶段根53/区域44保持；原状态仍归原owner。保存定向3组188检查、补充坏档边界311检查均退出0；同一次Sol/custom静态主审完成，无可确认发现。原生Main预算1保存、同进程及独立停开checkpoint/250ms未来一致。同代码SHA的[CI42553338071](https://github.com/fewnfds/reol/actions/runs/42553338071)本次提交准备点已核completed/success，完整回归通过；[QA](../qa/20261109_save_framework.md)记录分组证据、宿主审查恢复及限制。该包当时未封闭的移动/值事房/约练规则已由事件植物包处理，证据分别归属各包。

## 共同时间过载降速（已合入main）

`codex/adaptive-world-time`基于main `2c4ea10723d8140c5ae4b5f4c599f156d2ea6e5b`，共同时间已接有限准入、负载倍率和6ms合作式宿主预算；普通显示/HUD沿同一流速。根53/区域44及原状态owner不变，宿主负载估计不入档。最终定向8组796检查/0失败、包装器退出0；原生人工负载实际速度0.162×、帧间隔P95 17.600ms，移除后准入倍率恢复1×；同进程及完全停开250ms未来hash相同。产品/永久测试`f4257e38a1665c08c8596028fe71c0cea0dbeab9`的[CI42542611182](https://github.com/fewnfds/reol/actions/runs/42542611182)已核completed/success，完整12片通过；一次Sol/custom原生静态审查退出0，无可确认修复问题；已按用户授权快进整合main。产品/永久测试保持该SHA，后续仅QA帧驱动与文档，后续推送SHA的CI另行登记，不继承为已通过。细节和限制见[QA](../qa/20261109_simulation_pacing.md)。

## 共同结算内核（已合入main）

最终生产代码`d99ac6492ad5dbe5ba1af5bcc00171b5753c28e4`、测试提交`38606ea342f09e5aadcb50112df6620ddafbe10f`；[CI42508829722](https://github.com/fewnfds/reol/actions/runs/42508829722)为completed/success，251组/125351检查/0失败。本机12片及覆盖聚合也通过。后续仅Markdown至集成点`8cc40919599680d57e1f333f1482ebab38df7e3b`，其[CI42538304156](https://github.com/fewnfds/reol/actions/runs/42538304156)已核success。

共同时间、依赖/阶段、预算续算、完整画面与完成通知、FAILED暂停和合法会话恢复已接Main。两包各一次Sol/custom静态主审的有效问题已修复；原生预算1与完整未来、独立停开、连续欠算发布通过。RTX3060普通600帧P95 17.943ms，只证明该样本。12片CI曾实测并行，run墙钟213秒；准确日志、修复、版本与限制见[QA](../qa/20261108_settlement_kernel.md)。

## 官方Actions Node24升级

代码`dc2558b219cb2fbdf164c2d63371e01b0cff8226`已合入并推送main，只修改workflow。四个官方稳定release精确提交的签名、`action.yml`均核通过；六处调用使用`node24`且输入合法，原触发/权限/引擎/Python/12片/ZIP报告语义保持。一次Sol/custom原生静态差异审查无可执行发现，日志和YAML/输入比对在`logs/actions-node24-upgrade-20261109/`。本轮未重复本机Godot全套；本包真实提交准备点已核同SHA的[CI42539000023](https://github.com/fewnfds/reol/actions/runs/42539000023)为completed/success；终态缓存复用。[维护规则](../engineering/tooling/maintenance/01-updates.md)解释运行时与升级边界。

## 通用建筑与组合空间（已合入main）

main包含建筑阶段最终受检代码`d00bac954b69cab096d580db002fb04013fa2543`：定义/实例/能力分开，多格/朝向、多工地/用途，独立空间事实、操作位/桌椅、原库存储藏、工作台接原生产、耐久/防护/损毁已接普通Main。13类定义、两种材料，框架出口和实际限制见[本阶段QA](../qa/20261108_building_framework.md)及[建筑合同](../engineering/construction-contract.md)。

准确代码本机4片顺序完整check **250组/126290断言/0失败**，各worker结构、导入、脚本错误/超时及退出码均通过，独立覆盖汇总核250组无遗漏；总墙钟约3282秒，最慢片约1185秒，没有放宽单片1800秒门禁。首次单进程全量因夹具/非热通知错误及1800秒超时未通过，修复与证据保留在QA。一次Sol/custom原生静态审查的3项P2/1项P3均已修复并用反例验证。

最终d00bac普通Main多格施工、座位使用、存箱三案均在完全停止游戏进程后独立恢复，checkpoint、原截止时间与整个联合未来SHA相同；RTX3060原生1280×720界面已查看。[CI42457788038](https://github.com/fewnfds/reol/actions/runs/42457788038)已在本轮整合检查点核completed/success，完整headSha与d00bac一致。此后至主线集成点只有Markdown差异，受检代码/数据/测试保持不变；本轮未重复游戏验证。

## 已合入main的前序基线

共同空间、建筑及结算的准确提交、完整CI和集成记录分别见[空间QA](../qa/20261107_world_space_actions.md)、[建筑QA](../qa/20261108_building_framework.md)、[结算QA](../qa/20261108_settlement_kernel.md)。当前main与开发分支指针只看[分支状态](branches.md)；旧争环WIP和命名stash保持隔离。

## 术语与运行入口

受检代码`771a587d20a38998845331fb214cd886d361d876`：普通环境成员和调度domain统一为`RegionalSimulation.environment_fields`；区域存档键`local_heat`通过codec映射，现行schema不变。术语/真实代码映射见[唯一入口](../engineering/terminology.md)。本包import与定向10组1203断言通过，RTX3060真实HUD确认灵气文案，一次Sol/custom静态审查无发现；完整CI尚待准确SHA，证据见[QA](../qa/20261107_terminology.md)。该整理不新增游戏机制或改变main集成范围。

## 测试工作流与成本

测试优化f166cdb与受检快照2b98280完整tree一致：本机4片覆盖248组/124981断言/0失败，Python72项与错误退出smoke通过，一次主审无发现；组内1495.275→1325.163秒，不等于GitHub并行实测。计时、范围和远端状态见[优化QA](../qa/20261107_test_optimization.md)。前序计时/选组及CI42356120868 success的准确SHA与范围见[成本调查](../qa/20261107_test_cost_audit.md)，不替代后续版本。

## 顶层稀疏执行框架（已集成）

代码`ee3504d3c313aa07ac4e87caec3bd39488c725e3`在`codex/sparse-world-execution`建立通用owner-local能力参与/活跃/到期/变脏索引，普通环境与健康接入。准确代码本机完整check **248组/124980断言/0失败**，一次Sol/custom静态审查无有效发现；普通两次来源操作短样本224/221ms→8.081/7.173ms，无GPU。存档字段/版本不变、恢复重建派生索引；未把其他旧域自动迁入，不代表满密度或16GB整机验收。

本轮真实文档提交检查点核得[CI42345202281](https://github.com/fewnfds/reol/actions/runs/42345202281)，完整headSha`2f305de8efcbd8e51c290bbeae73cc5531fc2996`一致，终态**failure：测试1800秒超时（test=124）**。该head与上述本机受检代码只有文档差异；Python工具测试和导入完成，但Godot没有完整终态汇总，不能称远端通过。末条RUN为`test_terrain_edits`，不足以证明超时根因。未重跑/轮询或放宽门禁；日志与限制见[QA](../qa/20261107_sparse_execution.md)。

## 普通环境接管基线（已验收并入main）

最终代码 `6137481a07ec98b372e32ca857e546f1e1b07ee1` 已使普通Main接唯一室外冷热/五行场，原物与材料变更、人体/野药温度、共同时间及普通存档共用当前模型。保存拒绝未完成事务；旧根1–51明确拒绝，原档保留。准确SHA本机完整check **244组/124778断言/0失败**，1174源文件前后不变；同SHA双进程普通Main存读同未来、RTX3060真实画面与600帧联合负载通过。一次Sol/custom静态审查的3项有效发现均修复。普通单次生成/材料变更仍约0.22秒卡顿；不代表满密度或16GB整机验收。最终[CI42337874837](https://github.com/fewnfds/reol/actions/runs/42337874837)在后续真实调查文档提交检查点已核completed/success，完整headSha6137481一致；本包本机与CI均有准确代码证据，不重复测试。集成点`ffe7e8c705d2d7259dfb77dcfba3dd0a64c9c61c`已并入并推送main，之后仅更新文档；停止点查[HANDOFF](handoff.md)，完整证据与局限见[QA](../qa/20261107_world_engine_finish.md)。

## 采用版本与存档

- Godot **4.7.2 stable** 是这次采用和验证的版本；长期跟进最新稳定版，每次升级需核插件、CI与导出模板。当前是 GDScript、Windows 本机开发，CI 为 Linux headless；Windows 正式独立包未验收。
- 当前行动工作分支普通联合根存档 schema **56**，区域 **47**、村落 **7**、场状态 **5**（`composed_fields_v1`）、环境受体状态 **3**（climate **2**）、器物状态 **8**。内容包 **v3** 固定44份定义/开局，含会话搬运规则与digest。当前只接受根56；旧根1–55按[兼容政策](../engineering/compatibility.md)明确拒绝，原fixture只读；最终验收状态见上文。
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

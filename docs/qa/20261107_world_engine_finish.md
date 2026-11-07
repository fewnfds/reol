# 世界引擎普通接管与主线收尾

日期：2026-11-07。首代码 `d3b67a59ea11a87c4482da239649f87944cee609`。主要审查与修复已完成，最终代码`6137481a07ec98b372e32ca857e546f1e1b07ee1`完整回归通过。主线合并结果另见末节；本包不是完整游戏完成。

## 实际范围

- 普通 RegionalSimulation 的 `local_heat` 只装配 SimWorldEnvironmentFields；旧 Q 不再运行。复用既有场核、连续响应、来源索引与原身体/器物/库存/时间。
- 调度域/运行边界/推进阶段提供明确目录。原物受控生成、移动、移除和材料拆合，以及既有器物取放、设备开关/耗尽，经来源候选与原物同步提交，再通知外部。
- 人体暴露和野药生态读取同一温度；当前五行查询已接，但不宣称所有修炼生态玩法已消费它。背景按共同天气/气候推进，旧处残留保持。
- 当前普通存档：根52、区域43、内容bundle2、环境状态4。完整候选先独立校验；旧根1–51明确拒绝，原档和活世界保留。普通保存拒绝时间积压、原物提交和未完成场候选，不触碰主档/备份。
- 旧独立开发响应会话拒绝绑定普通世界，防止第二环境状态及绕过来源提交；历史专有测试按[退役登记](legacy-environment-regressions.md)退出当前入口，源码/fixtures保留。混合测试保留当前业务，部分使用当前新局重建在途过程。

当前只是室外场：墙门顶仍用于围合、通行、遮挡、遮雨等已有规则，不隔绝冷热/五行。房间均温、携物整体遮掩/尾迹、大规模动态人口、GPU玩家开关和后续玩法不是本包交付。

## 已有定向与普通入口证据

- `logs/finish-fields-drawing.log`：保存失败边界、普通场/原物/消费者/分片与恢复、既有引物业务，3组761断言0失败，无 SCRIPT ERROR/ERROR。保存测试包括主档与备份字节不变，旧独立会话不能插入第二场。
- `logs/finish-current-consumers2.log`：普通世界存读、暖身动作、显式热回执、有限设备，4组676断言0失败；包括取消、数量/成本、设备耗尽和在途恢复。
- 两独立进程普通 Main 的 `object_lifecycle_restart.gd`，`logs/finish-restart-write.log` / `finish-restart-read.log`：真实实物、3份木料、离开/返回、181000ms在途保存，完整退出后恢复，原环境值/完整场摘要以及184001ms继续结果相同；存档SHA `4c5e718c7edebd3e163b9ac33f5b2a116cbc597fa584d34d35952cc5e028287a`。此证据不是每个历史业务的跨进程重放。
- Python工具测试 `logs/finish-python-tests.log`：57项通过；其中模拟 Godot 错误/超时是故意失败样例，不是产品引擎报错。
- 第一轮全量在核历史入口时主动中止，不算通过；最终完整检查另记终态。原生主要审查只启动一次，命令 `codex -c model='"gpt-6.1-sol"' review --commit d3b67a59ea11a87c4482da239649f87944cee609`；头部确认为 Sol/custom，日志 `logs/finish-native-review.log`。

## 普通稀疏负载与真实画面

`world_fields_presentation.gd -- --tag field_load_01 --world-editor`，Godot4.7.2 stable / Windows11 / i5-13600KF / 单RTX3060 / D3D12 / 1280×720。开发机32GB，按10GiB单进程守卫运行；不能当真实16GB整机验收。

普通 Main 真实F8生成一件石板、原库存3份木料落地，60游戏秒后实际五行变化；画面观察到原物、普通界面与测试专用调试叠层。截图在 `logs/world_fields_presentation/field_load_01-{before,editing,after}.png`，不是新增玩家全知UI。

| 量测 | 结果 |
|---|---:|
| 开局场景载入/实例化/地图装配/选人 | 5144.150ms |
| 单件实物生成调用 | 227.540ms |
| 单堆木料转移调用 | 217.234ms |
| 一次推进60游戏秒 | 483.000ms |
| 暖身后采样 | 600真实帧，每帧显式推进100游戏ms |
| 推进调用 p50 / p95 / p99 / max | 3.503 / 4.006 / 6.392 / 75.329ms |
| 帧间隔 p50 / p95 / p99 / max | 15.058 / 17.903 / 20.021 / 84.181ms |
| 进程工作集峰值 / private采样峰 | 701112320 / 1039167488 bytes |
| Godot静态内存峰值 | 327614829 bytes |

负载为2地区、12人物、4鸟、1大型身体、9独特器物、8资源记录、9来源与7场块，含1个受管实物与1个材料堆。每帧clock/world/target一致且无欠算；不是满格、20Hz大量移动源或正式游戏容量证据。普通来源事务仍同步，单次约0.22秒有明显卡顿风险，不以p99掩盖最大值。操作系统和驱动/显存没有合并成游戏内存。

守卫报告 `logs/finish-native-load-01.json`、普通报告 `logs/world_fields_presentation/field_load_01.json` 保存完整量测。后续若修改影响当前路径，补相应验证并记录版本，不继承失效证据。

## Git与保护

在隔离工作树 `logs/world_engine_finish/dev` 实施；原工作区四份WIP与 `logs/world_engine_finish/protected-wip/original-sha256.json` 逐字核对后，保存在命名stash `424f956d280fb390d17e1f6dd879f3614b51a430`和原字节备份。stash四文件已再核与清单/备份完全相同，不自动应用。它们不在本包提交或回归中；温度组件的已提交版本仅加入显式、模型版本约束的锚点规范化，未采用原草稿。

真实提交检查点核前包最终修复 f641ddd 未发现匹配CI run，未轮询；本包已推隔离分支，完整验收/最终合并证据待下节登记。旧争环分支不合入。

## 最终结果

主要审查已完成，3个有效发现均已落实修复，受影响定向与最终完整回归继续验收：

1. 两组混合建筑/局部光测试仍读旧Q接口：保留实付建房、拆合、光遮挡、物品与当前存读；温度比较改用当前室外场，不再断言尚未实现的隔热或Q守恒。
2. 设备余额缺启停历史核对：按原定义opening_q、真实启用区间和有限容量复算stored_q，拒绝在容量内多/少一单位及停用后的伪造补充；计算先限额再乘法防长区间溢出。
3. 剩1Q仍报额定光：出光量改为min(rate, stored_q)，保留尾段预期4，光查询无额外扣费。

修复定向首轮 `logs/finish-review-fixes-01.log` 3组409断言0失败。full-check-02因有效问题主动停止，完整测试的部分输出并非通过；捕获的低精度JSON测试、旧瞬时气温与必惰性假设同步修订。正式存档仍使用完整浮点精度，未放宽候选校验。历史人物环境查询另修为明确unknown，避免跨时刻混合。

另修真实原物接缝：受管实物可位于固定容器，独立恢复时派生_contained索引尚未建立，来源装配从原身份/位置重建，不能漏来源而拒绝合法存档。强来源fixture也必须通过生命周期真实生成，不能绕过原物来源合同。

`finish-review-fixes-02.log` 7组1623断言0失败；`finish-review-fixes-05.log` 2组436断言0失败，含强来源/人体/历史/普通保存边界。失败的03/04及诊断日志保留，不当通过；有效修复后的05才是相关出口。

最终check-03对50af9b6运行完毕：238组通过、22失败断言、共124683断言，另有武器夹具失败后的脚本错误。日志`logs/finish-full-check-03.log`与`logs/check-test-20261107-114808.log`；此结果不通过。暴露的均为未适配的测试装配或旧档入口：

- `field_archives`三原始v40档仍要求成功加载，按既定有限退役移出当前入口，原文件不改；当前覆盖及专有缺口见[退役登记](legacy-environment-regressions.md)。
- 屋顶建床推进后才绑地图，环境已按seed0启动，恢复却给另一种子；改为首次推进前绑同一地图，不删除建造/耗材/自然光/恢复断言。
- 地形坏候选用点语法创建StringName键，被JSON文件层拒绝；改字符串下标，仍要求真实文件读写及业务加载拒绝。
- 借用在普通世界没有告诉实际看守，单次诊断`finish-loan-diagnostic.log`证实同job的warning在937250ms升级、原任务cancelled，源不扣、note不消费是正确结果。测试复用已有当面解释流程，未给NPC注入知识、改关系或放宽规则。
- 私交环与武器夹具在来源激活后直接造物，未进入原来源索引；改为普通开局先组装原物，保留原取物、私交、外观和在途存读断言。

`finish-current-fixes-01.log`屋顶、地形、借用3组1530断言0失败，无SCRIPT ERROR/ERROR。新代码只调整当前测试入口和夹具，生产保存/环境算法不因凑绿改变。修复SHA、最终完整结果及主线合并待填。

修复定向02中私交及共享连续性通过，武器纯展示另有两剑同锚点合法分排、测试雾接受越界两个旧夹具假设导致3项失败；按原行为修夹具，未改呈现或释放规则。定向03另记终态。

`finish-current-fixes-03.log`武器与原物运行时2组267断言0失败，无SCRIPT ERROR/ERROR；私交和共用连续性在02中各自通过。当前测试夹具修复收口，最终完整回归将在此修复提交上运行。真实提交检查点一次登记修复50af9b6的[CI42335595169](https://github.com/fewnfds/reol/actions/runs/42335595169)，完整headSha一致、in_progress，不视为通过、不等待或轮询。


## 最终准确版本验收

受检代码`6137481a07ec98b372e32ca857e546f1e1b07ee1`，其后仅更新记录，不再修改生产、数据、测试或工具。`logs/finish-6137481-source-sha256.json`的1174份源文件在完整回归和下述验证后逐份相同。

- `python tools/godot.py check --test-timeout 1800`完整通过：**244组、124778断言、0失败**，Import+test无SCRIPT ERROR/ERROR。日志`finish-full-check-04.log`及`check-test-20261107-121847.log`。check-03的失败证据保留，没有放宽产品校验或更改原fixture。
- 同SHA再用普通Main的`object_lifecycle_restart.gd`两个独立进程：writer45916在181000ms保存未完动作，完全退出后reader50364恢复并到达相同184001ms未来；环境完整摘要、原物、材料、离返及时间一致。文件`finish-restart-final-6137481.json`，SHA256 `5377c850e2260bcee9f50c7d107d0071808e2e8f278b189f01d38a47385c0155`；日志`finish-restart-final-write.log`、`finish-restart-final-read.log`及汇总`finish-final-verification.json`。
- 同SHA普通原生画面及600帧联合负载：`world_fields_presentation.gd -- --tag field_final_6137481 --world-editor`，RTX3060/D3D12、1280×720、原相同稀疏人数/来源，每帧100游戏ms且共同时间无积压。已实际查看after截图，真实F8石板、木料及五行变化可见；调试全知标注仅在该测量脚本。

| 最终6137481稀疏负载 | 结果 |
|---|---:|
| 开局装配 | 5057.293ms |
| 单实物生成 / 单材料转移 | 223.053 / 219.663ms |
| 推进调用p50 / p95 / p99 / max | 3.524 / 4.776 / 6.056 / 70.402ms |
| 帧间隔p50 / p95 / p99 / max | 15.566 / 19.054 / 31.300 / 83.976ms |
| Godot静态分配峰 | 348679769 bytes |

最终图/报告：`logs/world_fields_presentation/field_final_6137481-{before,editing,after}.png`和同名JSON；外部报告`finish-native-final-6137481.json`。此次调用console启动器，外部采样命中启动器而非实际窗口进程，其6.9MB工作集/1.4MB私有值**不作为Godot内存证据**；仅采用实际游戏报告的静态分配，前述field_load_01的直接进程内存测量保留其原范围。没有为补采样继续扩大验证。普通生成/材料同步提交仍约0.22秒卡顿，未宣称消除；未证明满密度动态大世界或16GB整机所有系统联合通过。

真实收尾提交检查点仅一次查到最终代码的[CI42337874837](https://github.com/fewnfds/reol/actions/runs/42337874837)，完整headSha匹配、in_progress。它仍待验；主验收采用上述准确SHA本机完整结果，不轮询、不把旧CI绿色代用。一次Sol/custom主要审查的修复映射与定向见前文，不重复整包模型审查。

所有本包日志、JSON、截图与指纹在工作树清理前保全到根目录`logs/world_engine_finish/validation-artifacts/`；旧失败同样保留。最终主线快进/推送结果由下一次实际操作后登记。

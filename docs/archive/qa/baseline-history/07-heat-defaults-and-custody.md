# 验证基线历史分卷 07

> 历史资料：保留原日期与结果，不是现行指令或任务；当前信息查[项目记忆地图](../../../README.md)。归档于2026-11-11。

> 历史记录：下文的版本、权限、下一步和 CI 状态只描述记录时，不代表现状。当前证据见[基线](../../../status/baseline.md)。

### C1a-2 审查修复接续

原包提交`350a715e44ba12b43919cd491beeafffcd995678`，一次原生Sol/custom静态审查结束（397.611秒，`logs/reviews/<SHA>.explicit-sol.log`），未自行启动引擎/测试/CI。发现P1：数值失败后GameClock期望时间领先物理时间，普通保存曾返回成功但候选拒绝加载。窄修复为在当前写档合同不支持的时间差出现时，save_game在同步玩家/文件I/O之前明确返回ERR_BUSY，保留原主档/备份和积压，不虚构成功或清掉时间。63项定向通过，4.024秒/峰值391241728B（`logs/thermal-v2-budget-review.json`），含真实有效主档/备份、耗尽后立即拒绝、逐字节不变/无临时产物、原档普通读取恢复。这个受限版本尚不支持将未结算时刻写成可恢复联合档。

主代理为处理该P1主动终止先前完整本机check（130组已运行，38条旧热守恒/版本投影失败；`logs/check-test-20261105-001428.log`），无完整回归结论。保留已知错误记录，不当超时/环境故障或成功。随后逐一改真实迁移比较的显式格式投影和sumQ+loss=input+ambient_in，全部原fixture保持不动；后续完整回归交相应最终SHA CI，不再本机/CI重复全跑。公共投影本身用真实v34与篡改/深拷贝用例验证，不能删除旧事实或默认值凑绿。

此窄修复实际提交检查点核前序73b765c的CI41859915825为completed/success，只覆盖该旧SHA。C1a-2及修复的最终SHA仍待完整回归。

审查修复/旧预期最终定向（每组30秒/1GiB，无引擎错误；不相加称全套）：

| 组 | 断言/失败 | 时间 / 峰值工作集 | 日志 |
|---|---|---|---|
| building | 214 / 0 | 3.260秒 / 226578432B | `logs/migration-v2-building.json` |
| capability | 71 / 0 | 6.984秒 / 447401984B | `logs/migration-v2-capability.json` |
| conflict | 171 / 0 | 12.619秒 / 444268544B | `logs/migration-v2-conflict.json` |
| perception | 180 / 0 | 13.379秒 / 433684480B | `logs/migration-v2-perception.json` |
| drawing | 76 / 0 | 6.981秒 / 435818496B | `logs/migration-v2-drawing.json` |
| field | 40 / 0 | 6.230秒 / 437788672B | `logs/migration-v2-field.json` |
| herb_history | 430 / 0 | 9.860秒 / 411803648B | `logs/migration-v2-herb_history.json` |
| private | 88 / 0 | 8.201秒 / 438661120B | `logs/migration-v2-private.json` |
| loan | 106 / 0 | 10.870秒 / 442675200B | `logs/migration-v2-loan.json` |
| care | 230 / 0 | 22.494秒 / 450854912B | `logs/migration-v2-care.json` |
| history | 345 / 0 | 10.062秒 / 441991168B | `logs/migration-v2-history.json` |

### C1a-3 单次默认背景复用（审查及最终回归接续）

原默认生产路径与自定义Callable分别测量。只在每次冻结重建和边界查询内按地区复用共同climate/weather/epoch/at_ms，返回即释放；两个自定义Callable独立保持逐格调用。不改变字段/版本/物理规则，候选历史段仍用传入anchor/segment。

同机同工作量/100倍有限脉冲/真实天气相界/40次1秒推进，默认路径优化前后：

| 实际格数 | 推进p95 前→后 | 推进p99 前→后 | JSON恢复p95 前→后 |
|---|---|---|---|
| 25 | 1.115→0.715ms | 1.141→0.930ms | 2.328→1.589ms |
| 128 | 4.998→2.923ms | 5.160→3.469ms | 10.738→7.520ms |
| 512 | 19.051→11.255ms | 19.459→12.134ms | 42.287→33.529ms |

日志`logs/thermal-default-before-*.json`、`thermal-default-after-*.json`，每样本30秒/1GiB，分片与JSON恢复守恒都通过。这里只是组件单次配对测量，非渲染帧时或长期/大世界保证；源patch数25/128/512格分别1/8/28。原自定义模式保留，不能用其旧18.251ms当默认19.459ms基线。

定向纯热269、独立导入71、数值拒绝/保存保护63项通过（`logs/thermal-reuse-pure.json`、`-import.json`、`-budget.json`），分别1.795/2.806/3.909秒，峰值214499328/237170688/391041024B，无引擎错误。普通原生read在完全新进程读取先前保存并推进相界后完整摘要仍为`a97bc2b15bcdda76bafd3a1d4c4a6ea631b0fc212d7f9d54c9673620233a3689`，6.628秒/工作集436432896B/私有662740992B（`logs/thermal-reuse-native-read.json`），截图重新核对尺寸1600×900。真实逐格Callable/默认等价专项接续；最终SHA全回归与原生静态审查尚待。

C1a-2窄修复最终已提交推送`e62dee5`，未重复原包静态审查；当前尚未查询其CI，留下一次实际提交准备。

C1a-3实际提交准备一次查得C1a-2修复SHA `e62dee50361c56654db6ecb4ef1986e6c71aa87c` 的CI `41869387451`仍in_progress，登记后留下一次真实提交，不启动等待/轮询。自定义512格模式另实测p95/p99 18.287/19.698ms，守恒与分片通过（`logs/thermal-custom-after-512.json`），该路径按设计不做地区合并。

C1a-3默认/两个独立Callable及混合接入专项113项通过，1.596秒/峰值213270528B（`logs/thermal-reuse-query.json`），覆盖双气候边界、边界前后1ms、非零天气epoch、图外邻格fallback、历史冻流独立JSON恢复并续同未来、自定义同地区不同格底量与各格不同边界。测试不读取或构造缓存内部结构。

C1a-3性能代码提交`9438291bddd0b7d8b676a9b90e1340a2f0cee51e`，一次原生Sol/custom静态审查84.539秒结束，无可操作发现（`logs/reviews/<SHA>.explicit-sol.log`）；审查未运行引擎/测试/CI。导入与结构检查通过（`logs/import-20261105-005042.log`）。最终SHA完整回归仍待CI，下次真实提交集中核对，不主动等待。

### A1b-0 原容器归处与数量查询（审查/最终回归接续）

`SimStorageQuery`只读原village/avian账本及真实身体/地点/工程材料锚点，独特器物非野外位置查询复用；无新实体ID、库存、持久状态或版本。引用严格domain/region/container，数量增加item；报告来源时刻/stale与world backlog，数量含原可用/托管，不提供免费转移。自然虚拟资源、粗粒度货运/嵌套箱等首包明确不支持，不默认原点。

主代理顺序有界定向均通过（30秒/1GiB，无引擎错误），表中数量分别表示覆盖范围，不相加声称完整回归：

| 组 | 断言/失败 | 时间 / 峰值工作集 | 日志 |
|---|---|---|---|
| entity | 76 / 0 | 2.918秒 / 226783232B | `logs/storage-query-entity.json` |
| large | 104 / 0 | 2.211秒 / 223920128B | `logs/storage-query-large.json` |
| artifacts | 91 / 0 | 2.565秒 / 225116160B | `logs/storage-query-artifacts.json` |
| storage | 86 / 0 | 2.050秒 / 221671424B | `logs/storage-query-storage.json` |
| special | 59 / 0 | 3.166秒 / 227028992B | `logs/storage-query-special.json` |

覆盖实际native预约/取货/连续搬运/托管中断/独立JSON恢复后续送同一完整未来、双地同名仓库、陈旧远区/目标积压、不改原账本/输入与返回值隔离；原工程材料取料后仍归project容器、随原身体、中断落material_cell；真实鸟域投食求药/衔药飞行及独立恢复，原库存和高度保持。首次新增测试直接用Dictionary比较JSON托管数值int/float导致一条失败，已统一完整JSON规范值比较，产品账本未放宽。新runner原先引用未注册函数导致临时脚本解析失败，已改动态指定测试，正式runner同步注册。普通画面和玩家功能未改，纯规则定向不代替大世界或视觉性能。

本包doctor/导入通过（最终导入控制台`logs/storage-query-final-import-console.log`）。提交准备时核前序e62dee5的CI41869387451为completed/cancelled，非通过；一次发现前序完整SHA `2102ce8a23aac2222911ecad9e0f8c0945d4ca56` 的CI `41872018227`仍in_progress，登记留到下一真实提交，不等待/轮询。

A1b-0已提交`e5fd27e802137fb997ecc198fa8247e968397764`。主原生Sol/custom审查错误地递归启动另一审查后被主动中断，原日志`logs/reviews/<SHA>.explicit-sol.log`不算完成。恢复同一主审查会话`01a1a784-9f11-79e2-8bd1-93a71095e0c8`，显式固定Sol/custom，禁止再派审查或运行验证；114.306秒后正常退出、无可操作发现（`logs/reviews/<SHA>.resume-sol.log`及`.resume-final.txt`）。未修改代码或运行引擎/测试/CI。AGENTS及审查流程已补防递归职责；最终SHA完整回归待CI。证据补包提交检查点核前序2102ce8同run仍in_progress，不等待。

### A1b-1 器物归处的事务边界（定向通过，审查/最终回归接续）

`SimArtifactTransfers`是world持有的会话钩子，无新物品、位置、历史或写档字段；原位restore保留，独立候选隔离且不补发通知。原take/place/draw在完整原条件后可拒绝预检，实际移动并完成原记录/active释放后通知。私交割只在器物、钱、收据及工作终态全部完成后通知，预检前仍为原物/原钱/预约。已付时间/qi不回滚；draw引用目标剑，不把环当被搬物。守卫是受信任规则，传副本并拒绝相应操作重入，不是运行任意玩家脚本的沙箱。当前未接native/施工/鸟域的完整事务、持续热源/跨格或可搬箱。

主代理顺序有界定向（每组30秒/1GiB，无引擎错误/泄漏）通过：

| 组 | 断言/失败 | 时间 / 峰值工作集 | 日志 |
|---|---|---|---|
| 原器物 | 91 / 0 | 2.703秒 / 225001472B | `logs/artifact-transfer-original.json` |
| 取放/拒绝/重入 | 50 / 0 | 2.007秒 / 227815424B | `logs/artifact-transfer-stone.json` |
| 远引/在途独立恢复 | 31 / 0 | 3.771秒 / 228048896B | `logs/artifact-transfer-draw.json` |
| 私交割完整提交 | 25 / 0 | 2.814秒 / 227840000B | `logs/artifact-transfer-buy.json` |
| 私交割拒绝/释放 | 22 / 0 | 2.812秒 / 228335616B | `logs/artifact-transfer-reject.json` |

含守卫/监听载荷修改不改原物、false/非bool拒绝、取消/另一人begin重入拒绝、1ms未到期无通知、同刻重复结算不重发、同world恢复替换器物域后保留钩子、实际远引拒绝后继续并独立恢复同未来，以及交割回调看齐双钱包/收据/锁。原drawing整组曾触及30秒组件额度而有界停止，无断言/引擎错误输出，不当产品失败或通过；之后只跑上述相关窄组，未重跑整套。本包doctor、导入及结构检查通过（最终导入`logs/import-20261105-011913.log`），没有可见变更，不以headless证明视觉/性能。

实际提交准备核前序2102ce8的CI41872018227为completed/cancelled；一次按完整SHA发现已推送的审查证据补包`9753ed264d9c51a9793b880203bb82dfef39fc82`的CI `41875594099`仍in_progress，留下一真实提交检查，不轮询。该补包包含e5fd27e代码；完整回归仍待对应SHA。

A1b-1原包`c977827627c23490038354d90492b77d7542e5da`一次Sol/custom静态审查204.415秒结束（`logs/reviews/<SHA>.explicit-sol.log`），未运行引擎/测试/CI。两项P2均已窄修：完成监听取消后续动作时逐项核active仍存在；signal载荷的顶层及entity/from/to均make_read_only，监听者需先duplicate再改，避免修改污染后续监听者。API依据Godot官方4.7 Dictionary文档经Context7核对。新增第二监听者及真实双温石同刻取物、首回调取消后动作的回归；既有4组重验58/31/25/22项，加取消18项，最终154项0失败，无引擎错误/泄漏，分别1.897/3.761/2.805/2.802/2.001秒，峰值工作集228454400–229441536B，每组30秒/1GiB（`logs/artifact-transfer-final-{stone,draw,buy,reject,cancel}.json`）。取消专项临时runner先误拼函数名，30秒守卫停止后已纠正并成功，不计产品失败或通过。原91项证据仍为此前版本，完整回归交最终SHA CI，不重复整包模型审查。修复提交准备再次一次核前序9753ed2同run仍in_progress，留下一真实检查点。

窄修复代码已提交`4ef344ee7c3b9916beefbb6da206a0b7cd1211a0`，最终导入/结构检查通过（`logs/import-20261105-012815.log`，200当前文档/358脚本0错误）。C1b规格/证据补包提交检查点仅复用前序9753ed2的CI41875594099非终态缓存，未绕冷却或再查询远端；最终推送SHA完整回归仍待下一实际提交检查。

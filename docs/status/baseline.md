# 构建、兼容与验证基线

核对：2026-11-07。这里记录采用版本与对应范围的证据；实际可操作内容见[功能入口](features.md)，任务状态和未提交工作见[接续](handoff.md)。旧的逐包原文已完整拆入[历史分卷](../qa/baseline-history/README.md)，具体测试和画面见[QA索引](../qa/README.md)。

## 本轮普通环境接管（待最终回归）

首代码 `d3b67a59ea11a87c4482da239649f87944cee609` 已使普通Main接唯一室外冷热/五行场，原物与材料变更、人体/野药温度、共同时间及普通存档共用当前模型。保存拒绝未完成事务；旧根1–51明确拒绝，原档保留。3组761断言、4组676断言、双进程普通Main同未来和单3060普通负载已有证据；完整check与一次Sol/custom静态审查正在进行，主线尚未合并。准确范围与待验见[本轮QA](../qa/20261107_world_engine_finish.md)、[HANDOFF](handoff.md)。

## 采用版本与存档

- Godot **4.7.2 stable** 是这次采用和验证的版本；长期跟进最新稳定版，每次升级需核插件、CI与导出模板。当前是 GDScript、Windows 本机开发，CI 为 Linux 无头；Windows 正式独立包未验收。
- 当前普通联合根存档 schema **52**，区域 **43**、村落 **7**、场状态 **4**（`outdoor_fields_v1`）、环境受体状态 **3**（climate **2**）、器物状态 **8**。内容包 **v2** 固定包含38份定义及来源digest；部分动作等规则仍直接读取项目文件。当前只接受根52，旧根明确拒绝；[兼容政策](../engineering/compatibility.md)不承诺永久迁入链，真实fixture保持只读。
- 本轮起点 `2483a3771bc9f469509293a514fb0a059eefe095`。原环境缓存、温度及两测试的四WIP已备份并与原工作区字节核对，不混入隔离实现/验收。分支快照见[分支状态](branches.md)，当前操作以HANDOFF为准。

## 已有包的历史证据

以下只记录各自SHA当时的通过范围、CI查询状态和限制，不覆盖本轮普通环境接管；其中旧Q、旧schema及“尚未接Main”按历史时态解读。

2026-11-07普通接入：首代码`f7baba0279fccb8d4592dc30194ddaa50dbf7f12`补F8按定义生成/移除实物，既有面板耗时取放、取消及接触复验。最终定向4组469断言0失败；3060普通Main双进程中途存读、原身份与完整摘要相同、再取放通过。一次Sol/custom静态审查P1等待冲突已修并定向验证；最终完整回归状态见HANDOFF，不拿定向当整套通过。新环境/GPU仍未接管普通Main，详见[QA](../qa/20261107_framework_runtime_integration.md)。

### 通用对象与空间首包

代码 `98a65663e325d2a56279fcf99af2c4d991e25a81` 在独立检出完成一次完整check：**249组、97864断言、0失败**，包含来源接口、空间快照和原项目回归；不含四处环境WIP。一次原生Sol/custom审查的占地缩窄问题已窄修并定向通过。合成512²索引和真实两区接口测量单独列于 [QA](../qa/20261105_world_object_contract.md)，不代表完整大世界/实时索引已完成。最终文档head的远端CI未主动等候。

### 生命周期与动作包

主代码 `c529c96910a0ef07af5e6d720bd848f395c4fed8` 及审查窄修 `b78f3af607c3b8c798411f4945de123d1d0ebf30` 接入受控实物、地面位置、材料和共同耗时搬运。后者精确SHA在独立检出完成完整check：**254组、98467断言、0失败**，1127.369秒且无ERROR/SCRIPT ERROR。已有262144真实静态物品的同进程内存序列化/独立候选恢复、普通Main RTX3060帧时、小会话双进程和双聚落证据，范围见[QA](../qa/20261105_object_lifecycle.md)；不将它们合称满密度跨进程重开或大规模NPC通过。前一head `d0bcf3734b4b6742fe6cee9c4d19467520a9ee14` 的[CI41982168735](https://github.com/fewnfds/reol/actions/runs/41982168735)在本次真实提交检查点核为completed/success。

第一阶段A–E的联合出口已按声明范围补齐，见[最终验收](../qa/20261105_world_foundation_exit.md)：同一普通Main实际离返后在途保存并由新进程恢复、512²真实物品落盘/候选恢复与256件批量变更、满格普通场景1800帧、有限动态体恢复。受测游戏逻辑仍为b78，后续改动仅基准和文档。单3060呈现p99 8.618ms；满密度候选恢复32.685s、峰值工作集4.82GiB，是后续优化依据。16GB整机仍是目标，未在真实16GB主机验收；动态只证1/4/8大型身体。

后续基准/文档提交 `06067d300a6c0158a1f602458afca2ac80a68598` 的 [CI41994818299](https://github.com/fewnfds/reol/actions/runs/41994818299) 在环境首轮方案的真实提交检查点一次核为completed/success，headSha完全匹配。该证据仍不包含四份本机环境WIP。

### A1地面环境来源

代码 `8bf7aa2a012af393fbc1b96fea6220aa18825833` 提供显式schema/digest、真实ground实物/材料堆投影和有界局部基础目标查询；不改变普通内容包和schema51/区域42。定向147断言/0失败，Sol/custom原生只读审查无可行动问题；真实512²地面物品复测局部查询p99 11.619ms、峰值进程工作集约1.39GiB。同一精确SHA独立检出完整check通过：**255组、98618断言、0失败**，1094.512秒，无ERROR/SCRIPT ERROR。[CI42008084331](https://github.com/fewnfds/reol/actions/runs/42008084331)在随后A2a方案的真实文档提交检查点核为completed/success，完整headSha匹配；没有轮询或重复本机完整回归。支持范围、源码哈希和测量口径见[来源QA](../qa/20261105_environment_source_bindings.md)；不涵盖响应残留、每帧全图更新或Main接管。

### 后续历史包

### 性能有限接续与停止点

A代码`9467cb9790229284ee24edd61cc48a45d809d1f0`复用原占用格索引，128²真实材料落地创建4.178→2.695秒；512²创建44.027秒、装配10.980秒、场2.930秒，峰工作集约2.015GiB，同10GiB守卫。4组定向9666断言0失败，Sol/custom审查无发现。B代码`603cdff7a65672e486b831453ec9114a71ea1ade`只保留显式存读分项工具与编码测试；两条无明显收益的运行改动撤回。4组定向298断言0失败，Python守卫8项通过，审查无发现，64²候选完整存读通过；不称大档优化成功。范围见[接续QA](../qa/20261107_world_performance_followup.md)。

A的[CI42269548713](https://github.com/fewnfds/reol/actions/runs/42269548713)收尾检查为in_progress，B的[CI42270554012](https://github.com/fewnfds/reol/actions/runs/42270554012)为pending，完整headSha一致，**本轮完整CI待验**；前包760cf7e的CI42223048834本轮已核completed/success。C多移动源未实施，Goal按用户条件暂停讨论；16GB整机、普通Main接管和完整游戏仍未验收。

### 基础场初建的局部上界优化

首代码2291ab9、审查修复`760cf7ed5c613ed2643b4dae1b6fb5c96277746e`增加来源块逐通道等级计数和有界局部上界，原场规则/候选/普通存档不变。最终6组定向10541断言0失败，Python守卫8项通过；一次Sol/custom静态审查的均匀场work回退已修，均匀场5124→5128 work，仅增加块汇总。最终[CI42223048834](https://github.com/fewnfds/reol/actions/runs/42223048834)在收尾实际提交检查点核为pending、完整headSha一致，**完整CI待验**，不继承前包绿色。

同环境128²基础场14.041→1.927秒；最终512²真实262143来源装配10.823秒、CPU场2.916秒、完整测试世界创建/校验等共83.652秒，峰工作集约2.062GiB（32GB开发机，同10GiB守卫）。最终16份代码指纹匹配，不含四WIP。范围/前后口径/失败与未验项见[初建QA](../qa/20261106_environment_cold_build.md)；未优化存读、未接Main或移动携源，也不代表真实16GB整机联合通过。

### 来源候选与紧凑存读优化

首代码`992acf06f7ef19e7a379d5ed01585e1165b300f9`及最终代码`8ce9e031e03d706285a5bce2b5657ec4bf30d22e`增加可下降来源上界、复用气候/潮汐编译、packed响应/流式文件、可发现中断恢复点和原账本材料紧凑回执。14组定向25944断言0失败；一次Sol/custom静态审查P2已修。[CI42181067921](https://github.com/fewnfds/reol/actions/runs/42181067921)在收尾实际提交检查点核为completed/success、完整headSha一致：**268组、134155断言、0失败**，Python57项通过，Import+test无SCRIPT ERROR/ERROR；未本机重复整套。30份代码指纹前后一致，不含四WIP。

最终512²真实262142材料堆+1实物、32次变更及完整独立存读通过，同10GiB守卫内峰工作集5.734GiB。单变更p99 0.350s（旧3.634s），但环境初建576.936s、文件写137.336s/读85.143s/原世界stage103.481s/重建599.413s仍慢，不是常时可玩吞吐。首轮新文件恢复OOM保留，最终靠紧凑原回执降低峰值。两进程完全停开至相同9000ms未来、RTX3060实际图像及64²GPU基础场复核通过，见[优化QA](../qa/20261106_environment_optimization.md)。本包限定优化出口完成；普通schema51及Main旧Q未改，完整接管/动态规模仍未完成。

该包真实代码提交检查点一次核得前HEAD `d4ea4df9b7a4da2773df3a863ef6bc35cc2fb290` 的[CI42054570393](https://github.com/fewnfds/reol/actions/runs/42054570393)为completed/success、headSha完全一致。这是前包代码和文档的证据，不代表新优化提交通过；无轮询。

### 静止来源连续响应

首代码`98e713590f29348c94823674bc58618162ec53bf`与审查修复`0d8c03545d9e6f4b3094cb725b14eb14a1bb3f23`接单实物联合来源/温度/五行候选、封闭开发会话、事件待算/取消和独立验收存读。修复SHA独立检出一次完整check **264组/108331断言/0失败**，约1099s，无SCRIPT ERROR/ERROR，31份代码指纹前后不变、不含四WIP；定向348断言0失败，工具Python57项通过；RTX3060真实渲染及完整双进程恢复到同一未来通过。64²/128²近满格真实来源的32次变更已测；512²修复SHA纯计算32次通过，激活264.520s、变更p99 3.634s、峰工作集3.837GiB。CPU候选吞吐仍不足，普通Main未接管。512²联合快照解析触及10GiB自建进程守卫，已停止并记失败，不外推小档存读结果。功能接缝已验收，全部计划性能出口仍未达标；详见[响应QA](../qa/20261105_environment_response.md)。

### 真实来源CPU/GPU接入

首代码`3e91b28ed27a082fd341ff47c5fbc68d14718357`和一次Sol/custom只读审查修复`9b3e724ce7e405d01b885e9b3e477b8afa09b226`接通真实ground缓存的计算租约、来源待同步准备、快照发布复验及取消/重绑回收。修复SHA独立检出定向9513断言0失败；真实RTX3060的10案例/6144格/43008通道通过。512²满密度半径16同负载CPU目标初建20652.613ms、GPU615.952ms；来源装配仍约7.4秒，GPU主线程请求5.585ms、进程峰工作集2.534GiB。同修复SHA独立检出一次完整check：**258组、107976断言、0失败**，1105.781秒，无ERROR/SCRIPT ERROR，不含四份保护WIP；本包在声明范围完成。详情和失败证据见[计算QA](../qa/20261105_environment_ground_compute.md)。未接普通Main/实际响应/移动携源，无新玩家开关或存档域；该代码远端CI未另等，主验收取本机准确SHA。

### A2a真实来源缓存

代码`4c1a2e9cd64ed89948f374008f6bcd9c35aa1b23`及一次Sol/custom审查窄修`3636dc37ea498fa1f57c1d970fca6e50289aff93`接通真实地面原物的预算装配、16×16基础目标缓存、通知前失效和epoch/所有者重绑。修复SHA独立检出完整check：**257组、99000断言、0失败**，1291.078秒，无ERROR/SCRIPT ERROR；原四份环境WIP未混入。定向1685断言0失败；512²真实262144来源全域冷建约19.26秒分片累计、advance p99约2.06ms，1024热读p95约10ms，未达初始5ms目标；离线进程峰工作集约2.2GiB，不是整款游戏容量或动态场FPS。证据见[缓存QA](../qa/20261105_environment_ground_cache.md)。

首代码SHA的[CI42025370605](https://github.com/fewnfds/reol/actions/runs/42025370605)在收尾实际提交检查点核completed/success；修复SHA的[CI42026400068](https://github.com/fewnfds/reol/actions/runs/42026400068)在后续GPU包的真实提交检查点核为completed/success，完整headSha匹配3636dc3。本机同SHA完整check亦通过；该证据不覆盖后续GPU接入代码。普通Main、实际环境响应和移动携源未由该服务接管。

| SHA、范围或案例 | 已有证据 | 不覆盖 |
|---|---|---|
| `bbd4303eb2ae477015dd1d9a40b170562c40a4d8` 的共同时间修复 | 普通 Main 先结算世界再发布时间；定向回归含暂停、真实在途与完全停开接续，细节见[共同时间QA](../qa/20261105_clock_world_commit.md)。 | [CI 41968678863](https://github.com/fewnfds/reol/actions/runs/41968678863) 于本轮真实提交检查点核为 `completed/success`，精确 headSha 为左列完整 SHA；不表示新环境场已接入。 |
| `923a95b18c8f127819d48e6397896125f9942d01` | [CI 41963564648](https://github.com/fewnfds/reol/actions/runs/41963564648) 曾核 `completed/success`，覆盖此前 packed/bulk。 | 不覆盖后来的源场联合候选和共同时间修复。 |
| `0920d28d50124cc561ad465d89f62360b84d2fd0` | [CI 41966563221](https://github.com/fewnfds/reol/actions/runs/41966563221) 本轮真实提交检查点核为 `completed/success`。 | 只覆盖该 SHA，不覆盖后续修改或未提交 WIP。 |
| 源场/温度联合候选 | 定向与独立两进程证据见[源场与温度](../qa/20261105_source_temperature_transition.md)。 | 仅隔离候选；真实原物、普通 Main、动态密集规模和完整房间未验。 |
| GPU/CPU 场服务 | 有真实 GPU 逐格对照与局部规模测量，见[计算加速](../qa/20261105_field_compute_acceleration.md)。 | 不能把静态或局部样本当完整世界容量、FPS 或玩家可用开关。 |

更早按准确 SHA 的成功、失败和修复记录保留在[历史分卷](../qa/baseline-history/README.md)；较早绿色、模型审查、截图或定向断言都不能代替目标 SHA 的完整回归。

## 主要边界

普通Main已经接入当前室外冷热/五行场、原物/材料、人体/野药和普通存读；最终本包验收仍以上方当前状态为准。完整房间均温与隔热、携物辐射/遮掩/尾迹、大规模动态人口与GPU玩家开关尚未实现。普通稀疏场景的3060测量不代表512²等满密度联合负载、16GB整机或完整游戏。45–60分钟完整切片、正式美术与Windows独立发行未验收。

历史成绩按所记硬件、数据量与路径解读，不外推所有地图或未来代码。工具版本与配置见[工具套件](../engineering/tooling/setup.md)，基线文档不复制工具清单。

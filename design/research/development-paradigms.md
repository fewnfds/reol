# 模拟开发范式与工具取舍

2026-11-18。研究基点main `a3b5f9a`，游戏代码/宗门包仍对应`1f28f79`。本页记录一手依据、适配与没有采用的路线；实际方法归[模拟设计与实验](../../docs/engineering/simulation-methods.md)，技能/工具现状归[setup](../../docs/engineering/tooling/setup.md)，实施与未修项仍归原主计划/问题页。本轮没有新增社会玩法、施工C01或重新验收游戏容量。

## 从当前实现出发

Reol已经具备唯一World/领域owner、Packed身体、Runner/Frame、个人认识、持久目的、有限方法选择、P5持续执行、社会事项/责任份额、Resource定义编译和正常百人源耗检查。`agency_selection.gd`已有当前意图加权/切换门槛，`agency_planner.gd`按原方法生成有关候选；不能把效用、迟滞、认识隔离或后台规划说成待从零引入。

此次主要缺口是**把规则正确性连接到玩法模型、社会行为的因果解释和恰当实验**。技能能够提醒取消/恢复、避免全扫，却不会自动回答新规则产生什么有价值的处境、玩家怎样看见与干预、哪种证据足以支持结论。补方法也不代表现有玩法已经无趣或AI一定有缺陷。

源码依据是原`kernel/{agency_selection,agency_planner,knowledge,society}.gd`的有关入口、`definitions/operations/library.gd`、`scenarios/settlement_opening.gd`及当前技能/工程合同。验证依据核了`settlement_cycle_smoke.gd`及继承的统计入口、`settlement_opening_smoke.gd`坏配置反例、现有`godot.py/check_structure.py`与性能工具的职责；不是全项目逐行审查或全测试重跑。

## 一手方法与适用边界

以下链接可核正文；阅读范围限定到本轮实际使用部分，不以顾问书单替代阅读，不复制论文/书籍全文。游戏资料描述机制不证明其私有引擎源码。

| 来源 / 实际核查范围 | 采用的方法 | 在Reol的边界与接入 |
|---|---|---|
| [Tynan Sylvester：The Simulation Dream](https://tynansylvester.com/2013/06/the-simulation-dream/)，2013-06-02，正文全文 | 从玩家能感知的因果选择模型的细节；少量清晰事件可支持玩家赋予人物意义 | 反馈围绕真实对象/行动/结果；不把作者的故事密度观点变成每个数值必须即时可见或必须制造灾难的硬门槛 |
| [Tarn Adams：Simulation Principles from Dwarf Fortress](https://www.gameaipro.com/GameAIPro2/GameAIPro2_Chapter41_Simulation_Principles_from_Dwarf_Fortress.pdf)，Game AI Pro 2 Ch.41，三页全章 | 逐步运行并迭代，拆基本要素与相互作用，借现实类比纠偏，避免无效细节 | 可复用领域能力与实际纵切共进；不先规划完整人类/宇宙，也不以“不要过度设计”为理由接受已知全局放大 |
| [Hunicke / LeBlanc / Zubek：MDA](https://users.cs.northwestern.edu/~hunicke/MDA.pdf)，2004，概念/设计者与玩家视角部分 | 区分规则、运行中相互作用与期望体验，来回验证三者的联系 | 自动规则通过、NPC都在移动和玩家有自主社会感分别成立；MDA不是能算出趣味的公式 |
| [Evans / Short：The AI Architecture of Versu](https://versu.com/wp-content/uploads/2014/05/versu.pdf)，作者公开稿，第1～3节 | 重复社会情境与扮演者分开，情境提供行动机会，角色按自己判断选择；界面解释重要关系/情绪的起因 | 复用Society/Institutions/原Operation与个人认识；不移植Praxis求解、统一Practice事实表或多动作回滚打分，也不据此宣称已有复杂情绪/关系后果 |
| [David “Rez” Graham：An Introduction to Utility Theory](https://www.gameaipro.com/GameAIPro/GameAIPro_Chapter09_An_Introduction_to_Utility_Theory.pdf)，Game AI Pro Ch.9，效用/曲线/选择/惯性部分 | 分数须能比较，选择政策与紧急优先、连续偏好及保持承诺分别处理 | 已有迟滞继续使用；分桶是可选工具，不能将职责和个人抱负永久分成绝对等级；不为增加随机性让NPC选择明显不可行方法 |
| [Grimm et al.：ODD Second Update](https://www.jasss.org/23/2/7.html)，2020，目的/状态/过程、设计理由、代码关联与POM段落 | 声明模型目的和可核行为模式；用不同尺度/不同条件约束同一模型；保留未满足模式 | 采用轻量问题与相关反例，不导入完整学术ODD/TRACE模板，不追求现实社会预测精度；单样本不支持统计结论 |
| [Factorio FFF-421](https://factorio.com/blog/post/fff-421)，2024-07-26，正文全文 | 空闲休眠/相关唤醒、共享覆盖登记、按数据依赖选择并行；电网并行实验揭示内存带宽限制 | 延续原owner/局部查询/顺序热批；收益须本机量，不照搬机器人低频位置到有碰撞ACT身体，不把能开线程当有收益 |
| [Space Station 14：ECS](https://docs.spacestation14.com/en/robust-toolbox/ecs.html)，Systems与定向/广播事件章节 | 状态变更通过负责系统，定向事件限制订阅范围；有需要才指定处理顺序 | 借边界与扇出控制，不替换成RobustToolbox/ECS，不把Godot全局Signal总线当免费局部通知 |
| [Widelands economy.cc](https://github.com/widelands/widelands/blob/29753773d9c130e2a6a835ee6a14ad2bf317371d/src/economy/economy.cc)，请求/供给登记、定时、匹配/提交与balance函数 | 变化触发域内再平衡，未来重试与当前供需区分，提交前重核请求/供应仍存在；域内顺序批不必消灭 | 仅阅读GPLv2源码思路，未复制；不是Reol性能收益证据，不迁全经济匹配器或凭此保证无死锁 |
| [Godot 4.7线程安全API](https://docs.godotengine.org/en/4.7/tutorials/performance/thread_safe_apis.html)，Context7目标版本正文查询 | 活SceneTree不跨线程直接访问；共享Resource/容器结构变化须遵守线程边界 | 保原脱离输入/owner复核，引用可跨线程不等于共享可变数据无竞争；`call_deferred`仍在主线程执行，并不会消除工作量 |

扩展线索：[Qud的2017历史生成论文摘要](https://pcgworkshop.com/database.php)及[作者GDC摘要](https://gdcvault.com/play/1025379/Procedurally-Generating-History-in-Caves)说明历史文本生成可以不等同完整历史模拟；本轮PDF直取受限，未把摘要外细节当证据，也未采用“生成事后理由”覆盖正在运转的真实世界。[Mesa的采样与批实验文档](https://mesa.readthedocs.io/stable/overview.html)可参考实验条件/模型与个体观测分离，不安装另一套Python模拟世界。

## 外部skills与工具的具体取舍

检索不能证明某库最好或覆盖全网。本轮在前次[33项覆盖审查](../../docs/engineering/tooling/skill-coverage.md)基础上补查下列作者仓库，固定HEAD与许可留本机，未运行其安装器。外部指令先按本项目范围裁剪，不因流行度或数量采用。

| 候选 / 核查版本 | 结论与理由 |
|---|---|
| [pbzona/godot-skills](https://github.com/pbzona/godot-skills/tree/0ad8f3c58d54580a57a1a6de3cd345a1d9376e3d)，MIT；读game-systems-design、game-balance正文及目录/许可 | **局部改写采用**：提炼体验→规则/反馈、存量流量、机会/分母与证据层次，形成一个Reol窄技能`simulation-game-design`，保留MIT声明。不整套安装，不照搬其多份必交设计文档/表格/遥测流程；API仍查本版本官方文档 |
| [setcodes/gamedev-skills](https://github.com/setcodes/gamedev-skills/tree/096c224aa498a789fa99d476583029fcb9f538e1)，MIT；读Godot总入口及许可 | **参考不安装**：观察行为、原owner和相关验证的指导有用，现有AGENTS/领域技能已覆盖；再装宽入口没有明确新增职责，未声称审完全部库 |
| [bgrenat/godot-game-dev-studio](https://github.com/bgrenat/godot-game-dev-studio/tree/bcb8419fc0c0360fb9f3b0952b5fc740be6cc7c6)，LGPL-3.0许可文本；读入口/许可 | **不整套采用**：总router指向94项领域和ALL Godot入口，与项目按需发现重复；这只说明当前组织不适配，不评价未读子技能质量，也不把许可解释成不能学习 |
| 已采用awesome-gamedev-agent-skills | **保留现有改写与pin**：18项复核不重置，再加缺失的玩法方法成为19项；未将本轮搜索HEAD当升级指令 |
| Godot AI / Context7 / Coding-Solo备用 | **保留现状，无新MCP**：本轮Context7成功查询4.7线程正文；Godot AI成功列session但为0，未观测编辑器操作/截图握手。备用仍关闭，不增加多个连接叠写或修改全局配置 |
| 新BT/GOAP/ECS、情绪求解器、运行时LLM、GUT/GdUnit替换 | **当前不采用**：原框架可表达本轮任务，没有已证实的工具缺口值得迁移。不是这些产品必然慢、与Packed技术上不兼容或永远不可用；若新任务有明确收益重新比较 |
| 新定义linter / 通用实验平台 / C01诊断框架 | **不另造**：已有compile/assemble和坏开局反例；局部访问与未服务年龄在相关owner实际整改时接，避免先为未知实现预建平台。现有长测驱动、benchmark/capacity/cpu_sample继续使用 |
| `tools/settlement_report.py` | **本轮新增**：将临时终点摘录补为可复用的只读分窗工具；已有日志直接用，零运行期更新/采样成本，无第三方运行依赖。统计不覆盖其未记录的因果/队列/FPS |

## 顾问如何参与，哪些建议没有照做

首轮同题双模型均完整回答，提供了模拟可读性、社会情境、POM、作者校验与性能反证等替代视角。顾问主要收到合同/当前技能与工具/宗门测试，没有拿到全内核；其源码缺口推断必须由开发者核查。后续方案/实现复核与实际检查的结果见[证据](../../docs/status/baseline.md#开发范式与离线工具验证)，原答留`.local/advisor/paradigm-alignment-20261118/`。

共三轮双模型六份完整答复：开工研究、具体方案反证、实际工具/技能与三个后续任务应用。第二轮的有效提醒已落实为编译/空间装配区别、执行结果/规划落选区别、居民编制/空间库存区别、前缀最低点与采样覆盖的明确标注；不采其基于旧附件的“技能缺链接”结论，也不因“暂未用BT”删除条件式guard备忘。第三轮两答均无阻塞项；补强错误日志前缀、坏字段拒绝和测试开销提示后做相关验证。顾问没有独立运行本机项目，不能以六答一致替代工具实测。

采用有关情境角色、可读因果、个人目标冲突、恰当实验和避免工具重复的方向，纠正以下建议后才写入方法：

- “两层深”不成为每个数值必须有图标+策略分叉的硬门禁；稳定供养不等于无聊，院落不必为均衡或不对称而重造。
- 概念上的Social Practice不是缺失的通用事实表；先用原社会/职责/操作合同表达，复杂归因/转介等仍是候选。
- 两答均建议再做定义静态工具，但原编译/装配已覆盖多类语义错误；理论来源/容量只说明假设下界，不保证AI必达/任意无死锁，也不拒绝刻意赤字开局。
- 50ms时间轮/FIFO不能直接替代当前整数到期和可变优先级/原等待年龄合同；沿原C01候选，不接受零维护开销或固定32批必服务等未经推导承诺。
- 消融要隔离因素；不同处境/机会集合可能使相同倾向得出同动作，不能以一段无差异否定整个机制。恢复后也不默认后台完成顺序或行为轨迹与直跑逐位一致。
- 不因版本/安全传闻加新的MCP/Mod沙盒或升级要求；插件已有采用版本/来源，工具能力以实际调用为准。运行期诊断、静态引用、规则正确、体验及性能是不同证据。

后续若要验证范式是否真的减少返工，应记录真实任务的访问形状、缺陷与必要检查，而非只数skill数量/格式。此次真实任务应用复核属于静态方案审查；没有把顾问答应或格式通过称作独立编码行为验收。

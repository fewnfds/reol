# 当前构建与验证

更新：2026-11-15。能力归[FEATURES](features.md)，状态归属归[架构](../engineering/architecture.md)，阶段归[主计划](../plans/foundation-priorities.md)。本页保存当前证据，完整历史由Git追溯。

## 当前构建

Godot 4.7.2 stable（ed1daf0bf），GDScript，Windows release，D3D12 Forward+，1280×720。正式入口`scenes/main.tscn`。当前为P5共同单位决策试玩版；根目录[启动.cmd](../../启动.cmd)选3运行`build/windows/act-p5/reol-act.exe`＋同目录pck，选1为最新源码战斗、选2为普通世界。

| 项目 | 当前值 |
|---|---|
| exe SHA256 | `3d19ee4a764e8bb153bfa7f811f98e0dfb0139c9e0c8bc6b76b93d3ed09185bf` |
| PCK SHA256 | `af806ddac1b890f78cf814f6cfc0481ec63d4e504f5b457c998b107857239410` |
| 战斗规则签名 | `04042c8edd9719b61192e5932f02a6346dfd643f280714a330d8e8f3e063a928` |
| 决策签名 | `6c536ed02eafd75d319b6b1ac664ccd7ca3e4235b66139aae125fb732efca332` |
| 内容 | 40动作、24配置、7套Policy；原生Resource/Inspector制作 |
| 存档 | reol-world-12；默认`user://act-p5-quicksave.reol` |

P5新增决策布局/签名，不迁移P4 format11开发档；旧包、原档及备份保留，不覆盖。exe是相同Godot模板，游戏变更主要在PCK；只核exe哈希不足以识别游戏版本。生成物/日志/本机咨询不入库。运行和制作入口归[usage](../engineering/tooling/usage.md)。

## P5实施与验证

共同Decisions接入原生活/工作、战斗、逃离及临时身体跟随；策略模板和个体参数/任务分开，保存待唤醒与持续自主输入。原host/run提交实际后果；发现威胁不先停工，手动明确交接，有限序列允许原合法取消。轻敌闪步三连、重敌承诺/收招和射手拉距共用执行器。

两轮双顾问均完整返回，原件在`.local/advisor/p5-implementation-20261115/stage-1/`与`stage-2/`；代码取舍归[研究](../../design/research/action_editor_references.md#84-p5实施复核)。按实际反例修复退避早醒、旧run/序列、buffer失效、手动/合作抢权、目标消失失醒、需求原因合并丢失、远处旧设施线索、移动/跟随交接及恢复校验。顾问不替代运行证据。

| 验证 | 结果与本机证据 |
|---|---|
| P5规则/恢复 | `p5-decisions-final-20261115-214152-62338800.log`，约8秒完整退出，DECISIONS_SMOKE errors=0。覆盖策略隔离、采集—威胁—重选、合法取消、序列中途恢复/失败/替换、手动、需求/失效目标、陈旧认识、buffer/跟随、坏候选拒载，详见[tests](../../tests/README.md) |
| 原核心/相关专题 | `smoke-kernel-20261115-214225-204690400.log`，KERNEL_SMOKE errors=0；features/sight/control分别为`smoke-features-20261115-214225-206210700.log`、`smoke-sight-20261115-214254-296888900.log`、`p5-control-20261115-214225-187397700.log`，均完整退出。ACT为`p5-act-20261115-213633-353163200.log` |
| P4相关执行 | MELEE、SPATIAL、ABILITIES最终检查均完整退出、errors=0：`p5-melee-final-20261115-214530-944672800.log`、`p5-spatial-final-20261115-214530-984891100.log`、`p5-abilities-final-20261115-214530-944118800.log`。未把其他无关专题自动串成长矩阵 |
| P5真实GUI | `p5-decisions-ui-final-20261115-214324-197734800.log`，DECISIONS_UI_SMOKE errors=0。原生练习切换、三类敌人出招、交战中实际文件存读、任务/参数保留、F12 decisions和读取后闪步/移动/出招通过；截图`logs/decisions-ui/`已观察 |
| 原ACT/生活GUI | `p5-act-ui-final-20261115-213736-509279300.log`，ACT_UI_SMOKE errors=0；`p5-life-ui-20261115-213038-470796600.log`，UI_SMOKE errors为空，覆盖普通取放、施工/取消、换装/卸下、人物/背包/迷雾界面；截图沿原目录 |
| 原生Inspector | `p5-authoring-20261115-213023-105014300.log`，COMBAT_AUTHORING_EDITOR errors=0。Policy/Library/规则引用及评分范例可编辑，坏距离字段提示有效；`logs/decisions-authoring-editor.png`已观察。第三方插件退出连接提示不当作游戏错误 |
| 导出包恢复 | `export-20261115-214413-827156200.log`完成；`p5-source-fixture-20261115-214346-408258000.log`生成同一P5混战/在途fixture，源码与PCK分别恢复并推进到1601ms，`p5-pack-restore-final-20261115-214418-862917500.log`完整持久状态一致，P5_PACK_RESTORE errors=0 |
| 结构/工具 | `check_structure.py --audit-code`为93份当前文档、224个Godot源文件、15个注册类，0错误；Python tool_smoke通过。新Resource与UID已导入；最终提交前再核diff和结构 |

过程中的失败保留，未作为通过计数：首次metrics重名/同步work交接见2105段；早期新测试的父helper清接触及只看瞬时移动字段见2107段，随后修正fixture/观察合同。原生Inspector曾等待后台窗口不产生的`frame_post_draw`而超时，日志`p5-authoring-20261115-212357-71911400.log`、212602与212714段；改为显式force_draw后完整退出，未放宽时间上限。

GUI失败`p5-decisions-ui-20261115-212318-460585800.log`显示攻击实际启动后立刻被打断；`p5-decisions-ui-final-20261115-214254-283248300.log`是在硬直中请求被合法拒绝。测试改为核启动事实并先闪步拉开，未修改战斗准入迁就测试。原ACT GUI在`p5-act-ui-20261115-213719-761847800.log`将合法buffer误当立即启动，改为等待真实启动/CD，后续通过。最终陈旧线索测试隔离原人物已知候选并在选择边界核意图，后续不可达由原导航反馈，不能将地图寻路失败说成查询隐藏库存。

首次源码/PCK探针误用不存在的`World.Scenarios`已修正；之后全状态对比差异仅在恢复会重建的`environment.revision`和`perception.next_ms`。最终比较两端分别恢复同一候选后的完整状态，不以源码未恢复世界与恢复世界的缓存版本差异冒充游戏结果不同；原失败日志`p5-source-fixture-20261115-213806-424182500.log`、`p5-pack-restore-20261115-213825-479112000.log`及213841段保留。

## P5相关性能短窗

i5-13600KF/RTX3060，D3D12，1280×720，玩家迷雾，1×，60FPS限帧，3秒预热＋5秒采样。仍为同World的持续星焰动作/耐久三敌与后台生活；P5敌人/生活选择已改变，**不与旧P4窗直接作纯算法提速百分比**。24人串行、512人两页/两worker，真实图形串行测量。

| 人数 | 全窗步均 | 步p99 | 帧p99 | 实际世界流速 | 交付/命中 |
|---|---|---|---|---|---|
| 24 | 1.174ms | 3.139ms | 16.878ms | 1.0001× | 23/69 |
| 512 | 8.517ms | 14.097ms | 16.867ms | 1.0001× | 409/59 |

证据`logs/p5-final-{24,512}.json/.log/.cpu.json/.png`。两窗无脚本/引擎错误、无死亡、木料守恒、零过载；5秒内协调求值324/1528次，累计46.668/414.056ms。它包含生活候选等嵌套成本，不是单个规则解释器耗时。早一版P5的`logs/p5-release-*`因后续因果修复重导出后复测，各人数共两次，未挑最佳窗。

这些短窗说明当前选定负载仍有可玩余量，不证明密弹极限、所有倍率、长局、主观手感或目标16GB整机。世界512²、近场60Hz和现有慢域精度保持，没有为P5降世界精度或新增LOD。

## 基础框架优化交付

以下为整理前`fe4fdcf`优化的有效短窗，不是本轮重新测量。实现与原生/自研取舍见[研究](../../design/research/large_simulation_optimization.md#godot原生能力与本轮实施取舍)。地图512²、60Hz和现有生活/环境/植物精度保持；索引仍完整重建，没有每格人数截断、流场或LOD。

同i5-13600KF/RTX3060/D3D12/1280×720/迷雾/1×60FPS限帧，3秒预热＋5秒采样。`framework-combat-v1`为同World中的星焰连发/焰种/控制与耐久三敌、普通后台生活；24人一页串行，512人两页自动两worker。前后每档各一次最终窗，中间更好值不取代最终值。

| 人数 | 模拟步均：前→最终 | 步p99：前→最终 | 帧p99：前→最终 | 世界流速：前→最终 |
|---|---|---|---|---|
| 24 | 1.161→0.752ms | 5.394→2.236ms | 16.742→16.709ms | 1.0001×→1.0001× |
| 512 | 9.182→8.341ms | 15.884→14.533ms | 16.859→16.720ms | 1.0001×→0.9967× |

证据为`logs/framework-{before,final}-{24,512}.json/.log/.cpu.json/.png`。步均使用全窗累计差，分位数用样本窗，不强行统一；各窗无错误、资源守恒、零过载。512人索引累计787.874→658.091ms，full发布301→62，但总发布194.554→200.232ms，**没有512人总发布成本下降结论**。主线程process均24人为0.864→0.642ms，512人为3.060→2.586ms。

步均约降35%/9%仅是这些短窗观察，不保证所有玩法。中间512人窗7.94ms、最终8.34ms，说明单窗波动；峰值仅观察到10弹/4状态，不证明密弹容量或设备延迟。命中/交付窗口端点有差异，规则等价另验。`logs/framework-final-equivalence.log`对24/512人各360个固定16/17ms步核对逐步outcomes/motion/move_scales与最终持久状态一致。

实际P4普通24人血刃无操作短窗`logs/framework-final-normal.json`约0.9999×、帧p99 16.812ms、步均0.503ms、主线程process均0.524ms、零过载。不能据此宣称持续施法/全部场景锁帧。

## 历史数值与限制

[performance.json](performance.json)保留02958cc、旧20Hz的capacity-v1样本，供同负载/同条件对照，不被ACT或本轮短窗覆盖。旧900人ACT高密交战曾约0.748×，属于当时特定版本/负载，不当作当前容量断言。更早各阶段构建/失败与日志路径见[整理前基线](https://github.com/fewnfds/reol/blob/bd1971c/docs/status/baseline.md)。

- 正式后撤/侧移/三连素材、主观混音、完整敌人花型、成长平衡、长局、极密弹幕和目标16GB/RTX3060整机没有由这些工程检查验收。
- 普通主场景在Godot 4.7.2 headless的Population着色器路径仍有已复现的`custom_samplers`错误；规则脚本与真实D3D12运行正常。本轮不把普通场景headless启动算通过，也不为此改动正常渲染。
- 满帧率不等于世界倍率达成，历史好窗不覆盖移动/探索/拆建尖峰。新增功能沿开发循环做相关检查，有对应瓶颈才再测性能。

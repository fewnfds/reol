# 当前构建与验证

更新：2026-11-15。当前能力归[FEATURES](features.md)，状态归属归[架构](../engineering/architecture.md)，下一主题归[主计划](../plans/foundation-priorities.md)。本页保留当前证据，不维护历轮施工日志。

## 当前构建

Godot 4.7.2 stable（ed1daf0bf），GDScript，Windows release，D3D12 Forward+，1280×720。正式入口为`scenes/main.tscn`。当前是经过基础框架优化与项目整理的P4试玩版，根目录[启动.cmd](../../启动.cmd)选3运行`build/windows/act-p4/reol-act.exe`及同目录pck；源码入口和独立快照的区别见[usage](../engineering/tooling/usage.md)。

| 项目 | 当前值 |
|---|---|
| exe SHA256 | `3d19ee4a764e8bb153bfa7f811f98e0dfb0139c9e0c8bc6b76b93d3ed09185bf` |
| PCK SHA256 | `7e639d64c2848d7c0c41a1166fa78a8f8f197536c3985d577d06a37524af2e56` |
| 战斗规则签名 | `04042c8edd9719b61192e5932f02a6346dfd643f280714a330d8e8f3e063a928` |
| 内容目录 | 40动作、24配置，公共Resource和ACT Resource共用原生制作工具 |
| 存档 | reol-world-11；默认`user://act-p4-quicksave.reol` |

本轮不改合法内容签名或格式，整理前有效P4混合过程可恢复。旧缺来源快照的开发档仍拒载，原档和备份保留。整理前成品归档在`build/windows/act-p4/archive/project-before-20261115-1755/`；源码/构建/日志与本机档案分开，生成物不入库。

## 本轮审查与验证

清除236个退役文件，包括未读取的旧JSON/开局/兼容库、退役人形样本与生成器、重复战斗提案、旧内核QA/工具报告和无引用的CombatEffectDef兼容别名；当前素材源稿、有效Resource与第三方许可保留。公共合同和战斗规格按源码收敛，删除把点击操作、未实现触发链、盾优先级/掩码、任意条件类型等当作现状的表述。旧内容由[Git历史](../archive/README.md)追溯。

修正了制作/恢复校验分叉：Resource拒绝的超额格挡比例可以进入在飞弹体候选。`ActionEffectDef.valid_values`现在显式核字段类型并复用Resource.errors，冷加载构造临时Resource，热命中不构造。合法载荷通过；超额格挡、零防御时长、非法状态标识和坏嵌套状态整份拒载，活世界不变。复现日志为`logs/review-payload-before-20261115-174109-613414200.log`。

顾问复核后补齐实际宿主的阶段校验，拒绝当前不会执行的作用配置；emit的弹/区域模板政策在制作与恢复共用，生成入口也先拒绝非支持类型。另修复零前摇技能从缓冲启动时晚交付/漏交付，复现为`logs/review-zero-windup-before-20261115-180500-10942500.log`；在原身体循环内交付新启动动作，direct仍走同刻桶。最终`logs/review-abilities-final-20261115-180514-58127700.log`与`logs/review-reactions-final-20261115-180514-58203900.log`均完整退出、errors=0，覆盖缓冲召剑只在启动时刻交付一次、合法反应恢复与坏模板/阶段拒载。

| 验证 | 结果与证据 |
|---|---|
| 原生导入/工具/结构 | Godot import、Python工具短检查及语法检查通过；结构检查覆盖92份当前文档和207个Godot源文件/资源，含标题锚点、字面引用、UID和项目Inspector资源边；无缺失或静态不可达提示 |
| 干净检出 | 本轮代码在无本机`.godot`缓存、无私有顾问入口的detached工作树重新导入，结构/工具检查、默认kernel和abilities全部正常退出；原日志复制为`logs/project-review-clean-{import,kernel,abilities}.log`。验证后移除一次性工作树，保留证据 |
| 默认kernel与独立专题 | `logs/smoke-kernel-20261115-174648-66843600.log`约8.5秒完整退出，KERNEL_SMOKE errors=0。features/sight/equipment分别正常退出，日志为`logs/smoke-{features,sight,equipment}-20261115-1747*.log`；原断言保留，均沿原15秒watchdog |
| 制作/载荷/在途 | `logs/review-abilities-20261115-174141-33666200.log`：原生定义、八套范例、弹/区/状态/器物及新增坏载荷拒载通过 |
| 相关领域规则 | ACT、CONTROL、MELEE、ACTION_FOUNDATION、DOMAINS、RESOURCES、REACTIONS、SPATIAL、COMBINATIONS、FRAMEWORK、EXPERIENCE、RESPONSE分别通过；原日志`logs/review-*-20261115-1749*.log`与1750段，索引`logs/project-review-rules.json` |
| P4真实GUI | 最终`logs/project-review-p4-ui-pointer-fixed-20261115-180933-288443000.log`，D3D12/RTX3060；两套组合、左右键/近战E/C、分裂/传播/脚本、狼/图腾/双剑和四次实际文件存读通过，ACTION_COMBINATIONS_UI_SMOKE errors=0。位置技能用不落盘的临时原生鼠标侧键映射，结束恢复，未冒充键盘指针自动化；`logs/abilities-ui/p4-*`截图已观察 |
| 普通生活GUI | `logs/project-review-life-ui-20261115-175304-869936600.log`：取放、施工/取消、真换装/卸下、人物/背包/缩放与迷雾相关界面通过，UI_SMOKE errors为空 |
| 原生Inspector | 最终`logs/project-review-authoring-final-20261115-181000-327581800.log`，实际编辑器的资源/引用/预览/错误定位检查通过，COMBAT_AUTHORING_EDITOR errors=0；插件连接关闭提示不作为游戏脚本错误 |
| 实际导出PCK恢复 | 最终导出`logs/export-20261115-181040-104622200.log`；`logs/project-review-pack-restore-final-20261115-181100-391184000.log`使用当前成品PCK恢复整理前原始混合fixture，弹、区、状态、器物、池、防御、反应、实体及HP后续相同，40/24签名一致。独立exe真实图形启动/180帧正常退出见`logs/project-review-release-final-20261115-181101-662456600.log`，无脚本/引擎错误 |

旧默认kernel把多个专题串行塞进一个15秒入口，曾在打印0错误后退出超时；本轮拆成可选择的独立入口，不放宽上限或删除断言。另一次误把RefCounted的tile模块用`--script`独立启动而超时，日志保留为失败；该模块已由features入口执行通过，未重跑求绿。短检查调用关系见[tests](../../tests/README.md)。

最终GUI首次复查的`logs/project-review-p4-ui-final-20261115-180702-937557600.log`失败：合成运动未移动Window实际读取的系统指针，E的位置请求落墙并被`target_blocked`拒绝。短探针证实parse_input_event不改变系统鼠标；修改测试的指向输入方式后才通过上述最终窗，没有改游戏目标校验来迁就测试。失败日志保留。

本轮静态双顾问复核原件留`.local/advisor/project-review-20261115/`，结论由源码和反例裁决，不替代运行证据。没有开展新的性能容量测量，也没有启动P5。

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

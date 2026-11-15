# 当前接续

ACT＋弹幕改版已交付P0试玩底座、P1直接操控、P2单剑切片，以及P3原生技能框架/八套范例。旧A攻击移动、S停止、H警戒、点击追击与射击模式开关已移除；A/S保留WASD语义。当前能力/键位只查[FEATURES](features.md)，构建与规则/GUI/短窗证据只查[BASELINE](baseline.md)。

P3框架与多技能范例已完成，独立包在`build/windows/act-p3/`。根目录唯一[启动.cmd](../../启动.cmd)：选1源码战斗、选2源码普通世界、选3当前P3成品、选4编辑器。默认火术＋混战，顶栏可切剑/弓/枪/火/冰/雷/毒/御剑和轻敌/重敌/混战；切换新开整个练习世界，不写存档，死亡也可重练。format10默认`user://act-p3-quicksave.reol`，P1/P2程序与旧档保留。

P2帧表/受击/反馈在[规格](../../design/systems/combat_framework/act_and_barrage.md)第3/4/5/8节。P3编辑方式、机制语义与后续新增机制接缝在第10节；实施状态在[主计划P3](../plans/foundation-priorities.md#p3方案技能制作与远程样例同步推进)。资源集中`data/definitions/combat/`，类型在`scripts/sim/definitions/combat/`；`combat.gd`保动作与统一HP提交，新弹体帮助模块、`combat_effects.gd`、`combat_areas.gd`、`implements.gd`按机制分工，仍在唯一World中运行。

原生Inspector现有阶段/范围预览、字段校验和“工具→Reol 战斗技能库”入口。保存内容后必须关闭并重新运行游戏，练习重置不重载定义；逻辑签名不符的旧档拒载并保留。没有安装YARD或第三方战斗运行时，没有万能脚本图/任意触发链。飞剑是独立器物领域里的唯一绑定练习件，已闭合去回程、耐久、掉落/损毁及恢复，普通背包转赠/拾取/维修经济尚无入口。

双顾问选型/上游核查原件在`.local/advisor/combat-authoring-20261115/`，本轮实现与生命周期审查在`.local/advisor/combat-framework-implementation-20261115/`；采纳/拒绝见[研究](../../design/research/act_barrage_references.md#p3实现与生命周期审查)。规则/新技能GUI/P2 GUI/真实Inspector/最终release已验证；图形测试的偏好与测试档已清理。正式后退/侧移/施法素材、混音、主观手感/平衡、目标低配机和长局仍未验收。

P4目标是技能、工具、制造与交互共用能力，支持后续大量扩展。用户的“采矿像施法”“特殊场景通用化”是方向类比，不能固化为所有过程必须cast或每个实例必须新建机制类。[AGENTS](../../AGENTS.md)顶部已加显著提示，要求提炼意图、专业化命名并区分目标/解释/候选/实现/证据。**P4已获完整实施授权，A1已完成，A2实现与验证已落地、顾问复核进行中。用户授权持续推进完整P4。**

[主计划P4](../plans/foundation-priorities.md#p4方案通用行动基座与战斗组合)采用公共执行协议＋可复用机制＋有限数据组合＋宿主内专用脚本。A1共同准入/占用/一次终止及P3载荷→A2所选交互/跨域时间接缝＋手工照料/引水术同源小样→B属性/池/状态/防御＋料理→C触发/分裂/传播→D位移/召唤/自主器物→E近远组合交付。原十类战斗样例保留；不先重写全部生活，不新增完整矿业/天气燃烧。

公共合同唯一归[行动与作用框架](../../design/systems/action_effect_framework.md)，战斗特有合同归[规格13](../../design/systems/combat_framework/act_and_barrage.md#13-p4通用战斗基座方案未实施)。各领域唯一持运行事实，共同占用只索引owner/run；取消/时刻/成本/恢复共规，原高频/批量算法保留。有限效果列表不含通用控制流、跨步结果引用或任意事务；独特算法使用受信注册脚本，状态随宿主验证/保存。照料首样单目标、领域起手预检，实物水有效提交时消费；保P3起手箭/CD与原配方/进度语义。收到实施指示从A1接续，不再重复一般资料研究。

最新能力架构再审与环世界作者样例、PoE开发者说明、DevilutionX固定SHA及D4官方资料原件留`.local/advisor/p4-capability-review-20261115/`，裁决归[能力架构研究](../../design/research/action_editor_references.md#6-能力架构再审与开发者裁决)。先前编辑器与战斗咨询分别留`.local/advisor/universal-actions-20261115/`、`.local/advisor/p4-combat-foundation-20261115/`。来源性质/许可明确，未移植第三方运行时；顾问重复意见不作证据。保留Runner会话epoch；旧ready携run、交互/接触按实际时刻提交、仍有后代的链不按固定寿命清除。

用户明确性能检查适量、先看成品；当前只做过24人release短窗，不追加900人或100/500弹门槛，也不把24人当架构上限。512²地图与生活/环境/植物精度保持，尚无远区LOD/粗算；只按真实瓶颈决定让步。本轮只改AGENTS与方案/研究/接续文档，未改游戏代码或生成P4构建，P3成品仍是当前试玩入口。

## 找当前信息

- 能玩什么、键位和缺口：[FEATURES](features.md)。
- 当前构建、实测及失败边界：[BASELINE](baseline.md)；历史数值原件：[performance.json](performance.json)。
- 状态owner与调用边界：[架构](../engineering/architecture.md)；实施方向：[主计划](../plans/foundation-priorities.md)。
- 开发/验证：[开发循环](../engineering/workflow/testing.md)；工具语法：[usage](../engineering/tooling/usage.md)。

## 受保护内容

- 保留分支codex/field-contest及已有工作分支、stash 424f956d280fb390d17e1f6dd879f3614b51a430。
- 用户自己的AGENTS.md改动、存档、凭据、原始素材与第三方addon；本机问答、日志和构建产物不入库。

## P4实施接续（2026-11-15）

活动goal覆盖A1～E，不能因A阶段完成结束目标。已交A1：派生`action_gate`绑定、领域run编号、`end_run/clear_navigation/clear_input`、有限共享效果包与独立弹体载荷、基本起手成本。A2：工作/接触按时刻共同提交、候选绑定域/run/运动代次、新生短工作继续采用、事件时刻空间采样、手工与引水术共用植物操作/实物水；伙伴等待归Society宿主。format11默认`act-p4-quicksave.reol`独立于P3档。源码顶栏多了引水法杖，普通世界背包可换；未导出P4。

证据：A1 ACT/MELEE/ABILITIES/ACTION_FOUNDATION/KERNEL短检查及八套真实GUI/存读通过；A2 ACTION_DOMAINS/KERNEL、引水术真实右键GUI通过（`logs/p4-a2-ui.log`、`logs/abilities-ui/p4-tending*.png`）。严格门禁恢复检查发现初始化工作模式残留，已修复后kernel通过。A1双顾问完成，采纳连段正常收招、弹组字段、坏载荷、时间基准/身份/模式校验；A2审查`.local/advisor/p4-implementation-20261115/a2/`仍待答，不重发。继续B前读取已完成答复并核查。

后续B属性/资源/状态/防御，C有界反应，D空间/实体，E组合试玩/制作/导出全部待做。A的时间归并不是B/C的同刻防御/派生流水线完成证据。根目录不增入口；保留用户AGENTS编辑。临时内容制作助手与研究均在忽略的`.local/advisor/p4-implementation-20261115/`。

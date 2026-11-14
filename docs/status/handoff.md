# 当前接续

ACT＋弹幕改版已交付P0试玩底座、P1直接操控、P2单剑切片，以及P3原生技能框架/八套范例。旧A攻击移动、S停止、H警戒、点击追击与射击模式开关已移除；A/S保留WASD语义。当前能力/键位只查[FEATURES](features.md)，构建与规则/GUI/短窗证据只查[BASELINE](baseline.md)。

用户本轮授权先实现框架并多做技能范例，开发疑点与本机顾问讨论；当前已完成，独立包在`build/windows/act-p3/`。根目录唯一[启动.cmd](../../启动.cmd)：选1源码战斗、选2源码普通世界、选3当前P3成品、选4编辑器。默认火术＋混战，顶栏可切剑/弓/枪/火/冰/雷/毒/御剑和轻敌/重敌/混战；切换新开整个练习世界，不写存档，死亡也可重练。format10默认`user://act-p3-quicksave.reol`，P1/P2程序与旧档保留。

P2帧表/受击/反馈在[规格](../../design/systems/combat_framework/act_and_barrage.md)第3/4/5/8节。P3编辑方式、机制语义与后续新增机制接缝在第10节；实施状态在[主计划P3](../plans/foundation-priorities.md#p3方案技能制作与远程样例同步推进)。资源集中`data/definitions/combat/`，类型在`scripts/sim/definitions/combat/`；`combat.gd`保动作与统一HP提交，新弹体帮助模块、`combat_effects.gd`、`combat_areas.gd`、`implements.gd`按机制分工，仍在唯一World中运行。

原生Inspector现有阶段/范围预览、字段校验和“工具→Reol 战斗技能库”入口。保存内容后必须关闭并重新运行游戏，练习重置不重载定义；逻辑签名不符的旧档拒载并保留。没有安装YARD或第三方战斗运行时，没有万能脚本图/任意触发链。飞剑是独立器物领域里的唯一绑定练习件，已闭合去回程、耐久、掉落/损毁及恢复，普通背包转赠/拾取/维修经济尚无入口。

双顾问选型/上游核查原件在`.local/advisor/combat-authoring-20261115/`，本轮实现与生命周期审查在`.local/advisor/combat-framework-implementation-20261115/`；采纳/拒绝见[研究](../../design/research/act_barrage_references.md#p3实现与生命周期审查)。规则/新技能GUI/P2 GUI/真实Inspector/最终release已验证；图形测试的偏好与测试档已清理。正式后退/侧移/施法素材、混音、主观手感/平衡、目标低配机和长局仍未验收。

用户明确性能检查适量、先看成品；只做24人最终release短窗，不追加900人或100/500弹门槛。512²地图与生活/环境/植物精度保持，尚无远区LOD/粗算。当前没有待完成的P3实施项；下一步先根据八套范例的试玩反馈选武器风格/敌人节奏或确有需要的新机制，不自动扩成所有职业和技能。

## 找当前信息

- 能玩什么、键位和缺口：[FEATURES](features.md)。
- 当前构建、实测及失败边界：[BASELINE](baseline.md)；历史数值原件：[performance.json](performance.json)。
- 状态owner与调用边界：[架构](../engineering/architecture.md)；实施方向：[主计划](../plans/foundation-priorities.md)。
- 开发/验证：[开发循环](../engineering/workflow/testing.md)；工具语法：[usage](../engineering/tooling/usage.md)。

## 受保护内容

- 保留分支codex/field-contest及已有工作分支、stash 424f956d280fb390d17e1f6dd879f3614b51a430。
- 用户自己的AGENTS.md改动、存档、凭据、原始素材与第三方addon；本机问答、日志和构建产物不入库。

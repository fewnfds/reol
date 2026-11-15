# 当前接续

ACT＋弹幕改版已交付P0试玩底座、P1直接操控、P2单剑切片，以及P3原生技能框架/八套范例。旧A攻击移动、S停止、H警戒、点击追击与射击模式开关已移除；A/S保留WASD语义。当前能力/键位只查[FEATURES](features.md)，构建与规则/GUI/短窗证据只查[BASELINE](baseline.md)。

P3框架与多技能范例已完成，独立包在`build/windows/act-p3/`。根目录唯一[启动.cmd](../../启动.cmd)：选1源码战斗、选2源码普通世界、选3当前P3成品、选4编辑器。默认火术＋混战，顶栏可切剑/弓/枪/火/冰/雷/毒/御剑和轻敌/重敌/混战；切换新开整个练习世界，不写存档，死亡也可重练。format10默认`user://act-p3-quicksave.reol`，P1/P2程序与旧档保留。

P2帧表/受击/反馈在[规格](../../design/systems/combat_framework/act_and_barrage.md)第3/4/5/8节。P3编辑方式、机制语义与后续新增机制接缝在第10节；实施状态在[主计划P3](../plans/foundation-priorities.md#p3方案技能制作与远程样例同步推进)。资源集中`data/definitions/combat/`，类型在`scripts/sim/definitions/combat/`；`combat.gd`保动作与统一HP提交，新弹体帮助模块、`combat_effects.gd`、`combat_areas.gd`、`implements.gd`按机制分工，仍在唯一World中运行。

原生Inspector现有阶段/范围预览、字段校验和“工具→Reol 战斗技能库”入口。保存内容后必须关闭并重新运行游戏，练习重置不重载定义；逻辑签名不符的旧档拒载并保留。没有安装YARD或第三方战斗运行时，没有万能脚本图/任意触发链。飞剑是独立器物领域里的唯一绑定练习件，已闭合去回程、耐久、掉落/损毁及恢复，普通背包转赠/拾取/维修经济尚无入口。

双顾问选型/上游核查原件在`.local/advisor/combat-authoring-20261115/`，本轮实现与生命周期审查在`.local/advisor/combat-framework-implementation-20261115/`；采纳/拒绝见[研究](../../design/research/act_barrage_references.md#p3实现与生命周期审查)。规则/新技能GUI/P2 GUI/真实Inspector/最终release已验证；图形测试的偏好与测试档已清理。正式后退/侧移/施法素材、混音、主观手感/平衡、目标低配机和长局仍未验收。

用户把P4方向进一步上提为全游戏可引用的行动/条件/作用/反应能力，例为采矿、工具与技能共用执行。**当前仍是方案，P4未实施。** [主计划P4](../plans/foundation-priorities.md#p4方案通用行动基座与战斗组合)安排A1公共行动/作用合同＋P3战斗迁移→A2所选交互/参与者适配＋照料法术跨域小样→B公共属性/池/状态/防御＋料理增益→C触发/分裂/传播→D位移/召唤/自主器物→E整合交付。原十类战斗样例与近远两套组合保留；不先重写全部生活，也不顺便实现完整矿业/天气燃烧。

公共合同唯一归[行动与作用框架](../../design/systems/action_effect_framework.md)，战斗特有合同归[规格13](../../design/systems/combat_framework/act_and_barrage.md#13-p4通用战斗基座方案未实施)。公共运行头＋策略状态、类型化领域操作、小提交与结果/反应复用，原owner/批量计算/共同时间保留。收到实施指示从A1接续，不再重新收集一般资料。

本轮三轮双顾问六份完整答复，以及War3/SC2官方编辑器资料、War3Net社区源码与哈希原件留`.local/advisor/universal-actions-20261115/`，裁决归[编辑器研究](../../design/research/action_editor_references.md)。此前战斗三轮双顾问原件仍在`.local/advisor/p4-combat-foundation-20261115/`，取舍归[战斗研究](../../design/research/act_barrage_references.md#p4三轮双顾问收敛与开发者裁决)。不引入第三方运行时，不赠隐藏无敌，不承诺任意step全世界同未来；P3起手成本/CD与既有生活物资/进度语义先保留。

用户明确性能检查适量、先看成品；当前只做过24人release短窗，不追加900人或100/500弹门槛。512²地图与生活/环境/植物精度保持，尚无远区LOD/粗算；P4也只按真实瓶颈决定世界精度让步。本轮只改方案/研究/接续文档，未改游戏代码或生成P4构建，P3成品仍是当前试玩入口。

## 找当前信息

- 能玩什么、键位和缺口：[FEATURES](features.md)。
- 当前构建、实测及失败边界：[BASELINE](baseline.md)；历史数值原件：[performance.json](performance.json)。
- 状态owner与调用边界：[架构](../engineering/architecture.md)；实施方向：[主计划](../plans/foundation-priorities.md)。
- 开发/验证：[开发循环](../engineering/workflow/testing.md)；工具语法：[usage](../engineering/tooling/usage.md)。

## 受保护内容

- 保留分支codex/field-contest及已有工作分支、stash 424f956d280fb390d17e1f6dd879f3614b51a430。
- 用户自己的AGENTS.md改动、存档、凭据、原始素材与第三方addon；本机问答、日志和构建产物不入库。

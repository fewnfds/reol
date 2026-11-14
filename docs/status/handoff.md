# 当前接续

当前主题是近远双路线的ACT＋弹幕战斗改版，当前进入主计划P0，已加入显式开启的合成移动响应测点并测完旧20Hz基线，尚未改变模拟频率或实现WASD/连招。设计与候选参数在[改版规格](../../design/systems/combat_framework/act_and_barrage.md)，来源/基线在[专题研究](../../design/research/act_barrage_references.md)，工作包只维护在[主计划](../plans/foundation-priorities.md)。

下一实现入口仍为P0：核查50ms/0.05与按步分组假设，做60Hz统一心跳＋到期慢域候选，再与旧链路同负载比较，补小型高频姿态发布、直接移动/瞄准与移动弹相位。已完成的两窗只说明普通背景未出现明显响应恶化，不证明新ACT负载达标。用户允许实测必要时牺牲次要世界精度/频率，边界只查规格9.3；未测不预先缩图。之后按主计划进入单剑灰盒与远程循环。

测量入口为benchmark.py的`--response-probe`；原件在`logs/act-p0-response-20261114/`，隔离构建在`build/windows/act-p0/`，均不入库。正式试玩包没有覆盖；正式构建状态仍见BASELINE。

## 找当前信息

- 能玩什么、键位和缺口：[FEATURES](features.md)。
- 正式构建与已接受测量：[BASELINE](baseline.md)；数值原件：[performance.json](performance.json)。
- 状态owner与调用边界：[架构](../engineering/architecture.md)；实施方向：[主计划](../plans/foundation-priorities.md)。
- 每轮怎样开发/验证/交接：[开发循环](../engineering/workflow/testing.md)；工具语法：[usage](../engineering/tooling/usage.md)。

## 受保护内容

- 保留分支codex/field-contest及已有工作分支、stash 424f956d280fb390d17e1f6dd879f3614b51a430。
- 用户存档、凭据、原始素材与第三方addon；本机问答、日志和构建产物不入库。

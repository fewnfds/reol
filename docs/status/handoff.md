# 当前接续

ACT＋弹幕首个可操作灰盒已接入正常World，旧A攻击移动、S停止、H警戒、点击追击与射击模式切换已移除。源码入口为根目录[ACT试玩.cmd](../../ACT试玩.cmd)与[开发试玩.cmd](../../开发试玩.cmd)，能力/键位只维护在[FEATURES](features.md)。完整方案仍按[主计划](../plans/foundation-priorities.md)推进，不能把灰盒交付写成P0～P7全部完成。

下一动作：先交付当前可玩版本，让用户实际体验剑/弓的移动、出招、接敌与脱离，再依据反馈收敛动画、音画和敌人节奏。用户已明确性能测试到此为止，不要求本轮达到900人压力标准，不再以此延迟试玩。密集交战的候选/几何瓶颈和100/500活跃弹验收保留为后续事项，只有目标玩法确受影响时再推进；不自动扩测。P0/P3/P7的未完成出口见主计划。

源码/短检查与真实图形输入已验证；音效只验证合成占位流和播放器触发，尚未做主观混音/正式听感AB。测试日志与测量事实只查[BASELINE](baseline.md)和[专题研究](../../design/research/act_barrage_references.md#13-60hz灰盒与密集交战实测)。存档仅支持format8，默认新的act-quicksave.reol；旧文件保留。

ACT独立release在`build/windows/act-preview/`，当前测量原件在`logs/act-preview-20261114/`、图形截图在`logs/act-ui/`；旧20Hz包和原正式Demo未覆盖，均不入库。用户允许有证据时让次要世界精度为战斗让步，边界见改版规格9.3；本次尚未实现远区LOD或战斗粗算。

## 找当前信息

- 能玩什么、键位和缺口：[FEATURES](features.md)。
- 正式构建与已接受测量：[BASELINE](baseline.md)；数值原件：[performance.json](performance.json)。
- 状态owner与调用边界：[架构](../engineering/architecture.md)；实施方向：[主计划](../plans/foundation-priorities.md)。
- 每轮怎样开发/验证/交接：[开发循环](../engineering/workflow/testing.md)；工具语法：[usage](../engineering/tooling/usage.md)。

## 受保护内容

- 保留分支codex/field-contest及已有工作分支、stash 424f956d280fb390d17e1f6dd879f3614b51a430。
- 用户存档、凭据、原始素材与第三方addon；本机问答、日志和构建产物不入库。

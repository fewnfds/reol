# 当前接续

ACT＋弹幕首个可操作灰盒已接入正常World，旧A攻击移动、S停止、H警戒、点击追击与射击模式切换已移除。源码入口为根目录[ACT试玩.cmd](../../ACT试玩.cmd)与[开发试玩.cmd](../../开发试玩.cmd)，能力/键位只维护在[FEATURES](features.md)。完整方案仍按[主计划](../plans/foundation-priorities.md)推进，不能把灰盒交付写成P0～P7全部完成。

P0按试玩范围收口，P1已完成输入生命周期、键鼠改键闭环、瞄准/空间一致和贴地方向提示；新独立包在`build/windows/act-p1/`，源码入口不变。能力与键位见FEATURES，原生Alt-Tab、规则/GUI与导出证据见BASELINE。下一包是P2近战节奏/取消/命中反馈与敌人窗口，按[主计划](../plans/foundation-priorities.md)和用户试玩反馈推进；P3远程循环与P7正式动画尚未收敛。

用户已停止扩展性能测试，不要求900人或100/500弹达标；只有目标玩法确受影响才再查成本。完整硬件延迟/权威提交间隔和高压规模仍为非阻塞证据缺口，P1没有新增性能测量或远区LOD。

源码/短检查与真实图形输入已验证；音效只验证合成占位流和播放器触发，尚未做主观混音/正式听感AB。测试日志与测量事实只查[BASELINE](baseline.md)和[专题研究](../../design/research/act_barrage_references.md#13-60hz灰盒与密集交战实测)。存档仅支持format8，默认新的act-quicksave.reol；旧文件保留。

旧ACT预览包`build/windows/act-preview/`、20Hz包和原正式Demo未覆盖，均不入库。P1截图在`logs/control-ui/`，P0测量原件保留在`logs/act-preview-20261114/`。用户允许有证据时让次要世界精度为战斗让步，边界见改版规格9.3；尚未实现远区LOD或战斗粗算。

## 找当前信息

- 能玩什么、键位和缺口：[FEATURES](features.md)。
- 正式构建与已接受测量：[BASELINE](baseline.md)；数值原件：[performance.json](performance.json)。
- 状态owner与调用边界：[架构](../engineering/architecture.md)；实施方向：[主计划](../plans/foundation-priorities.md)。
- 每轮怎样开发/验证/交接：[开发循环](../engineering/workflow/testing.md)；工具语法：[usage](../engineering/tooling/usage.md)。

## 受保护内容

- 保留分支codex/field-contest及已有工作分支、stash 424f956d280fb390d17e1f6dd879f3614b51a430。
- 用户存档、凭据、原始素材与第三方addon；本机问答、日志和构建产物不入库。

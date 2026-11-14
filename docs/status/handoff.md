# 当前接续

ACT＋弹幕改版已交付P0试玩底座、P1直接操控与P2单剑战斗测试包。旧A攻击移动、S停止、H警戒、点击追击与射击模式切换已移除；A/S保留WASD移动语义。当前能力/键位只查[FEATURES](features.md)，构建与规则/GUI/短窗原件只查[BASELINE](baseline.md)。

用户已授权完成P2并在实现后与顾问审查，由开发者核实取舍。本包已完成，独立包在`build/windows/act-p2/`，入口为`P2练习场.cmd`；根目录[ACT试玩.cmd](../../ACT试玩.cmd)读取最新源码，[开发试玩.cmd](../../开发试玩.cmd)进入普通生活开局。顶栏可分别重开轻敌、重敌或混战，死亡也可重练；重练新开整个练习世界，不写存档。format9默认`user://act-p2-quicksave.reol`，P1档/包和旧档保留。

P2实现帧表/缓冲/受击/敌人/反馈只维护在[规格](../../design/systems/combat_framework/act_and_barrage.md)第3/4/5/8节；实施范围与十分钟试玩路线见[主计划](../plans/foundation-priorities.md#p2方案先交付一把有性格的剑)。两位顾问实现静态审查及取舍见[研究](../../design/research/act_barrage_references.md#p2实现审查与交付取舍)，原件留本机`.local/advisor/p2-implementation-20261115/`。不采用让失衡绕过控制预算/必定额外延长原收招的建议；没有新增倒地起身、累计破势条或攻击者权威卡肉。

接下来先收集用户对第三刀价值、推步是否抢走走位及重击重量的反馈，再决定P2参数修订或收敛P3独立远程循环；尚未授权直接扩建武器库或跳到正式全套动画。现有整身八向动作和程序合成音仍占位，主观听感/混音、目标低配机/长局未验收。P1完整改键GUI本轮受系统游标定位失败影响未取得新通过，排查证据与其他已通过范围见BASELINE，不把旧记录算作本轮通过。

用户明确性能检查适量即可，先看成品；本包只做24人最终release短窗，未追加900人或100/500弹门槛。512²地图、生活/环境/植物精度保持，只有目标玩法确受影响才定位成本并考虑必要让步；尚无远区LOD/粗算。

## 找当前信息

- 能玩什么、键位和缺口：[FEATURES](features.md)。
- 当前构建、实测及失败边界：[BASELINE](baseline.md)；历史数值原件：[performance.json](performance.json)。
- 状态owner与调用边界：[架构](../engineering/architecture.md)；实施方向：[主计划](../plans/foundation-priorities.md)。
- 开发/验证：[开发循环](../engineering/workflow/testing.md)；工具语法：[usage](../engineering/tooling/usage.md)。

## 受保护内容

- 保留分支codex/field-contest及已有工作分支、stash 424f956d280fb390d17e1f6dd879f3614b51a430。
- 用户自己的AGENTS.md改动、存档、凭据、原始素材与第三方addon；本机问答、日志和构建产物不入库。

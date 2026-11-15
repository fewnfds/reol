# 当前接续

**战斗框架完成到P5：共同单位决策与持续任务已接入生活、工作、战斗和随从。** 本轮交付main并推送origin（GitHub），实际同步以Git指针为准。没有待补P4施工或必须续跑的极限压测。

根目录唯一[启动.cmd](../../启动.cmd)：选1源码战斗，选2源码普通世界，选3独立P5成品，选4编辑器。当前包`build/windows/act-p5/reol-act.exe`与同目录pck，生成物不入库。F5/F9用format12的`act-p5-quicksave.reol`；旧P4包、旧档/备份保留，不自动迁移。键位查[FEATURES](features.md)，构建/实测查[BASELINE](baseline.md)。

## 已交付与下一主题

P5以共同Decisions协调策略绑定、独立参数/任务、手动交接、唤醒与自主输入。生活沿原候选/宿主；战斗用原生规则/有限序列和受信评分脚本。轻敌连段、重敌承诺/收招、射手拉距；采集→威胁应对→脱离后重选已验证。制作/绑定归[单位决策合同](../../design/systems/unit_decision_framework.md)，咨询裁决归[研究](../../design/research/action_editor_references.md#8-可编排单位策略p5研究与实施)。

日常事件/到期，战斗默认50ms，运动/结算仍60Hz及细分边界。发现只更新线索，交接由原gate准入；强制受击/死亡原时刻清理。任务引用原run，原owner处理占用/费用/效果。存读保留任务、唤醒与自主输入；诊断不参与决策。F12输入`decisions`看选择和当前任务。

下一主题等用户试玩反馈再选，不自动续做P6/P7。新增预警系统明确后置。图编辑器、公开任意脚本、运行时LLM、全生活数据化、完整Boss和新弹幕花型未作为P5交付要求。

扩展沿[实际owner](../engineering/architecture.md)，先判断配置、局部脚本、共享机制或新领域。公共合同归[行动与作用](../../design/systems/action_effect_framework.md)，战斗归[ACT规格](../../design/systems/combat_framework/act_and_barrage.md)。用户类比与顾问意见不自动成为术语/功能/验收断言，按根AGENTS核查意图与证据。

## 当前边界

两条近远组合、机制范例和三类敌人可玩；正式动作/混音、主观手感/平衡、完整构筑与长局仍待选题。地图512²、近场60Hz；未为P5降低世界精度，没有远区LOD、人群避让或流场。相关性能短窗及限制查BASELINE。

## 受保护工作

- 本机顾问资料、凭据、存档、素材源稿及第三方addon不覆盖。
- 保留工作分支，尤其`codex/field-contest`及stash `424f956d280fb390d17e1f6dd879f3614b51a430`。
- 临时探针/咨询归`.local/`，日志归`logs/`，成品归`build/`，不新增根目录启动脚本。

# 当前接续

**战斗框架完成到P4；基础框架优化与项目整理已收口，下一阶段尚未实施。** 本轮交付分支为main，远端为origin（GitHub）；实际提交与同步状态以Git指针为准。没有待补的P4施工片或必须继续的性能选题。

根目录唯一[启动.cmd](../../启动.cmd)：选1源码战斗，选2源码普通世界，选3独立P4成品，选4编辑器。当前包为`build/windows/act-p4/reol-act.exe`与同目录pck，生成物不入库。F5/F9使用format11的`act-p4-quicksave.reol`，旧档/备份保留。能力和键位归[FEATURES](features.md)，构建/证据归[BASELINE](baseline.md)。

## 下一主题

用户明确将新增预警系统后置；P5候选扩大为[通用单位决策与战斗策略](../plans/foundation-priorities.md#下一阶段候选)，将生活、工作、战斗选择与持续任务接入共同协调能力，尚未开始实现。用采集→威胁应对→脱离后重选验证跨域交接，用轻敌、重敌、射手及有限多步任务验证战斗策略。弹幕新花型/精英不作为默认清单，不按旧P5～P7计划自动续做。

候选职责归[单位决策与持续任务](../../design/systems/unit_decision_framework.md)，顾问与公开来源核查归[研究](../../design/research/action_editor_references.md#8-可编排单位策略p5研究未实施)。策略模板、个体参数与独立记忆分开，原P4执行与各领域owner继续处理实际后果；发现威胁与开始交战需拆清，不能把执行的区间内回调一律延到区间末。普通游戏无需编程界面，未制作图编辑器或运行时策略层。现有世界/存读接入仍有效，新决策状态随实施补齐。

扩展先判断配置、局部脚本、共享机制或新领域，沿[实际owner](../engineering/architecture.md)修改。公共合同归[行动与作用](../../design/systems/action_effect_framework.md)，战斗合同归[ACT规格](../../design/systems/combat_framework/act_and_barrage.md)。用户类比和顾问建议不自动成为类名、功能或验收断言；根AGENTS要求提炼意图并核查证据。

## 当前边界

P4有两条完整组合和机制范例，尚无成长构筑/完整敌人花型/正式动作与混音验收。地图为512²，近场60Hz；没有为性能降低世界精度，没有远区LOD。流场/分块等仅按实际瓶颈选题。

本轮清除退役JSON/旧开局/兼容库、技术样本、重复战斗提案与旧QA报告；没有保留等待迁移的影子框架。历史由[固定Git版本](../archive/README.md)追溯。制作与恢复共用效果/阶段和emit模板校验，修复零前摇缓冲召剑的交付；默认短检查与原features/sight/equipment专题独立选择，失败与本轮验证结果只归BASELINE。

## 受保护工作

- 本机顾问资料、凭据、存档、当前素材源稿与第三方addon不覆盖。
- 保留现有工作分支，尤其`codex/field-contest`及stash `424f956d280fb390d17e1f6dd879f3614b51a430`。
- 临时探针/咨询归`.local/`，日志归`logs/`，成品归`build/`；不新增根目录启动脚本。

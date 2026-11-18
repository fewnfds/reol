# 当前接续

## 当前停点

新开的百人宗门生成姓和名各一至两字的随机姓名，男女使用各自的八向动作贴图。姓名贴近脚下，地图绿名覆盖全部直接与间接下属。左下角「图鉴」或 F8 可查看单个精灵和原图集。职责人员页标明当前部门和分组，状态半圆暂隐。围合房间默认遮挡天气，完工墙的「加装屋檐」消耗木材并修改原墙。该版用启动菜单选 2。原有 format33 屋顶场景按[存档合同](../engineering/compatibility.md)迁移。

基层部门管理与生产协作D01～D06已完成，分支`codex/department-workflow`，游戏源码提交`90c3968`。该阶段的独立包已通过冷启及 F5 保存、完全退出后 F9 读取。后续源码增加人物姓名与关系色、四角选择标记和仓储斜俯视贴图，使用启动菜单选 2 试玩。实施边界归[主计划](../plans/foundation-priorities.md#基层部门管理与生产协作)，真实证据、源码/包身份和未通过项只归[BASELINE](baseline.md#部门管理与生产协作)。部门管理、最新启动入口和人物图鉴随本次合并进入主线。

正常 main 是青禾宗100人（玩家1＋99自主）。根目录[启动.cmd](../../启动.cmd)只提供当前项目入口，选1为能力练习、选2为源码宗门、选3为编辑器。过期宗门成品已退役，历史 P5 仅作性能比较。源码使用 format33 的`user://sect-quicksave-v33.reol`。

玩家可为掌门、员工或自定义身份；头衔不决定权限，能力和部门/子部门/工作组范围决定面板与命令。当前消费是厨房、仓务及原田务等已有工作，不表示已实现任意战斗/探险/财务业务。部门与订单归Institutions，库存仅Objects.stock，跨take/put运输沿原公物受托；NPC与玩家共用管理命令。重叠组/兼职不复制身体，工位与台内单批排他；完成才转换原料，暂停保工时、取消整批清工时，两者不耗料/不产物。日常厨房不再装配巡库发榜/领榜/报工，私人交往、教学和有限认识保留。现行合同归[社会系统](../../design/systems/social_system.md#当前部门目标与运输合同)及[宗门生活](../../design/systems/sect_life.md#已接入的生产合同)。

开工、各阶段与收尾均已咨询并独立核查；最终`closure-focused/`、`final-evidence/`双答均无本轮阻断项。全部本轮咨询及验证进程已结束。最终相关规则、真实GUI/125%/自定义授权/员工视图、百人1800000游戏ms跨日及文件恢复、当时的独立release均通过。最新源码验证与仍未通过的检查见[BASELINE](baseline.md#人物姓名与素材图鉴)。

## 尚未做或未通过的事项

- 日目标100是配置，未证明四院各达100或全年平衡；本轮跨日只证明真实供料/加工/搬运/进食与目标续期。不得用初始餐库存或无饥饿替代稳态证据。
- `kernel_smoke`的development100人/4×/220ms窗口650ms推进断言仍未通过；独立干净`cbf020a`也失败。650ms及15秒上限均未放宽，不能写成kernel全通过或“因不读UI停止世界”。旧abilities聚合超时未重新验收。
- C02本人任命/服务和C03作业位查询已随新流程收窄；C01～C06完整性能整改仍未完成。现有跨步服务/后台纯规划仍在使用，关键身体页安全join仍保留。后续按[成本方案](../plans/foundation-priorities.md#系统组合成本审查)与[问题清单](issues.md#系统组合成本)选题，不因为面板完成就关闭旧成本问题。
- 复杂技能/速度优先级、排班、真实盘点/报工、完整继任/市场/外交、远区LOD、全年供养均后置。不自动开启新战斗/预警/透视或万人极限任务。

## 已有基础与开发接缝

T01～T13生命/角色/个人认识/目的/责任/教学/田务底座保留；三日历史供养证据归BASELINE，不覆盖本轮修改后的长期平衡。日常WASD、Tab战斗、可见NPC活动卡片/真进度保留；当前练习与宗门共用Combat，差别是配装。固定斜俯视、Camera2D直接绘制、脚点分层；三维/透视shader探索已撤除。

19项领域技能与[模拟设计实验方法](../engineering/simulation-methods.md)已接，技能覆盖纠偏与OpenCode清理不重置；入口查[工具配置](../engineering/tooling/setup.md)及[技能覆盖](../engineering/tooling/skill-coverage.md)。不恢复退役包装器，也不按“本轮没用”删除领域约束。新增工作继续接原owner，先核访问集合与上层倍率，不另造第二World、库存账、JobBoard或统一全事实事件总线。

## 本机证据与受保护工作

- 本轮咨询/探针/失败与最终证据：`.local/advisor/department-management-20261118/`；最终原生包日志`release-{save,load}-final.log`、汇总`package-delivery-final-messages.log`，原生GUI`ui-delivery-final.log`，正常跨日`autonomy-delivery.log`；实际包哈希和细数归BASELINE。
- 前次复杂度、调度、范式与技能研究分别留`.local/complexity-audit-20261117/`、`.local/scheduling-implementation-20261117/`、`.local/paradigm-alignment-20261118/`、`.local/skill-coverage-20261118/`及对应advisor目录；正式结论已回原主题，不凭顾问重复引用替代源码/实测。
- 保护当前用户存档/偏好、顾问凭据、素材源稿、第三方addon和历史P5包。保留分支`codex/field-contest`与stash `424f956d280fb390d17e1f6dd879f3614b51a430`，旧`.local/playtest-before`工作树保留。本轮独立干净基线检出已核路径/内容并移除；不重复删除或覆盖用户工作。

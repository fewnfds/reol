# 公共行动与作用框架

**P4当前实现合同。** 本页描述已落地的公共能力，战斗时序见[战斗规格13](combat_framework/act_and_barrage.md#13-p4通用战斗基座)，状态owner见[架构](../../docs/engineering/architecture.md)。采矿与施法等玩家类比用于说明复用意图，不意味着所有世界过程都必须cast。

## 1. 复用范围与事实归属

共用准入、占用交接、多成本、有限作用和实际结果反应；各领域保留自己的数据、算法和生命周期。身体位置/HP归Units，物资归Objects，植物和环境各有owner；公共层不复制它们。

| 当前能力 | 实际入口/宿主 |
|---|---|
| 准入与占用 | `action_gate.gd`的可重建owner/run索引；ACT相位归Combat，交互归World.actions，采集/旅行归work_runs，伙伴等待归Society.waits |
| 合法终止 | World的`end_run`、导航清理、输入清理与死亡清理分工，旧run通知不得覆盖新动作 |
| 成本与领域操作 | `action_costs.gd`归并别名并全量验资；`domain_effects.gd`目前注册照料操作，复用Nature提交 |
| 状态/属性/资源 | Effects维护来源状态，Equipment重建热属性，Pools持蓝/怒等可选池；HP/精力/qi保留原owner |
| 结果反应 | Reactions接收实际结果，管理有限链、计数/ICD和后续请求；World.emit与UI日志只作输出 |
| 空间与持续生产 | Combat/Projectiles/Areas/Implements/Entities各自推进，原World统一提交 |

原手工照料与引水术共用同一次水消费和植物资格；料理在真实食物消费后应用公共增益；采集回能使用实际采集结果。完整矿业、物流、无人设施经济不属于已实现能力。

## 2. 扩展方式

| 新需求 | 做法 |
|---|---|
| 现有机制的参数或组合变化 | 复制/组合Resource，登记library并绑定Loadout |
| 宿主生命周期已存在，仅局部算法特殊 | 在原机制注册受信项目脚本；状态随宿主保存 |
| 多种内容需要相同算法和生命周期 | 提炼共享函数或参数化机制，不按实例数量机械划分 |
| 新持久事实、守恒或空间算法 | 扩实际所属领域；职责确实独立才新建领域 |

不要求每种机制都有Manager/Autoload，也不要求每个特例新建通用类。复杂脚本不进入战斗主循环的技能名分支；稳定共性再上提。

## 3. 原生制作与有限载荷

作者数据使用Godot Resource/Inspector，编译成递归只读值。当前实际类型为`ActionEffectDef`、`ActionEffectBundle`、`ActionCostDef`、`ActionPoolDef`、`ActionStatusDef`、`ActionReactionDef`；ACT专有类型仍在`definitions/combat/`。没有独立的通用ActionDef、ConditionDef、TargetQueryDef或脚本图执行器。

作用种类为damage、control、slow、dot、domain、status、heal、shield、guard、resource、dispel，按activation/contact阶段解释；伤害与控制由战斗桶投影结算，其他作用交回对应owner。有限列表不是通用事务，不承诺失败回滚，也没有可配置的任意分支或跨步骤结果引用。交易、配方和照料保留具名整体提交。

阶段由宿主能力限定：ACT的direct/blink只消费activation，近战/弹/区域/器物只消费contact，evade/recall/entity的主bundle为空。反应bundle和实体光环/周期作用使用contact；direct/blink与实体周期作用不接受damage/control，它们没有直接数值伤害结算出口。编译拒绝无法执行的组合，不让制作配置静默失效。光环另限持续属性/移速状态，伤害生产使用现有攻击交付。

### 3.1 生命周期与成本

行动意图先检查存活、控制、当前动作承诺、目标和成本，再取得运行身份。当前普通ACT在合法启动时原子支付全部成本并启动CD，取消不返还。成本支持规范物品、可选池及原HP/精力/qi；别名先归并，HP成本保留至少1点生命，支付不冒充受伤。

领域材料不一律提前扣除：照料在有效提交时检查并消费水，施工和交易依原领域合同处理。动作预检不保留资源、不制造物资，实际提交仍须复核。

共同占用只记录owner/run。阶段、到期、已交付和剩余进度留在原宿主；终止一次，清自身预约/贡献，不撤销已经离手的攻击或已完成物资转移。移动、工作和交互命令不能绕过ACT不可取消段或硬控；现有即时药水和修行回春命令保留即时使用政策，不取得新的行动占用。

### 3.2 程序员怎样接入特殊行为

当前专用策略是Reaction宿主中的`reaction_scripts/owned_marks.gd`：本次激活留下有限标记，在满足条件后引爆，状态有schema，算法有显式LOGIC_VERSION并参与规则签名。它证明脚本出口可用，不等于已有任意轨迹/多阶段脚本注册平台。

新增策略须接宿主的时间、结果、取消/销毁与恢复边界；代码由项目显式注册，存档只保存种类、版本与值，不从文件加载任意Script。原owner继续写HP/物资/位置。延时和周期用World时刻推进，不依赖Node Timer、await或墙钟。普通GDScript不是不受信脚本的安全沙盒。

## 4. 状态、属性与资源

状态种类为slow、dot、root、stun、haste、modifier、mark。支持refresh、stack并刷新、replace、independent，按source/chain/activation隔离，并限制层数与实例数。周期寿命为`[born,until)`，续期保原节拍，恰好到期不跳伤。

属性从基准/装备与活跃修饰重建：`(base + add之和) × multiply各项之积`，再钳制/取整；状态增删与装备变化使缓存失效。不靠撤销时除回倍率，不让身体槽复用继承旧身份属性。

当前有近远攻击、护甲、最大生命与移速修饰；移动加速不改变动作/CD/周期。没有独立increased乘区、完整抗性/暴击/伤害转换、通用公式或完整WoW控制递减分类。盾层/定向格挡和吸血结算归战斗合同，不能把它们泛化成已实现的任意免疫系统。

## 5. 实际结果与有界反应

当前事件为hit、damaged、killed、blocked、shield_broken、gathered、timer、expired、stack_max；模式为bundle、emit、request、spread、script。条件包括所选事件/接收方、概率、每N次、间隔、传播范围及链限额，没有任意标签查询或属性表达式语言。

结果保留来源、目标、激活、实际时刻与必要结算分量。吸血读取实际损血；打盾、过量和失败采集不能虚构有效量。规则是局部索引，不全图广播所有装备。

派生兄弟共享因果预算、深度、次数与访问集；仍有在途后代时保留链。命中/定时分裂处理出生后的残段，传播继承声明的来源与剩余寿命。完整出招的request在严格下一50ms网格联合准入，接受后才扣规则CD/预算/动作成本，不占玩家下一招缓冲。具体空间先后见[战斗13.6](combat_framework/act_and_barrage.md#136-触发链分裂传播与持续生产)。

自主器物与临时身体按合法自身周期产生新攻击；事件触发的额外输出仍继承祖链。不能用重新定时或更换名义owner洗掉生产上限。

## 6. 共同时间、恢复与表现

World使用整数毫秒，Runner默认60Hz心跳；动作、工作到达/到期、弹体接触和周期边界在共同时间排序。更早死亡/打断使较晚工作提交失效，已经较早完成的交付不被撤销。整个16ms/50ms区间不是一个同刻桶。

原状态在一致边界捕获；加载先验证独立候选，再重建属性/占用/空间索引。制作和在飞载荷共用作用字段校验，坏状态拒载而不修剪承诺。规则签名、输入恢复与文件政策见[兼容说明](../../docs/engineering/compatibility.md)。

表现消费不可变Frame和可靠结果，不写世界真值。DEV可选追踪最近64条采用规则；诊断缓冲不进档。玩家观察、NPC本人认识与全图开发视图分开。

## 13. P4实现映射与制作出口

实际文件映射见本页第1节与[架构](../../docs/engineering/architecture.md)。新增常规技能的完整编辑/校验/试玩步骤归[制作流程](combat_framework/act_and_barrage.md#102-制作者新增技能的实际流程)，不维护另一套模板操作说明。

交付依据是：已有跨域调用确实共用规则，生活指令不能绕过动作承诺；成本/物资与在途过程能恢复；八套基础范例和两条组合可玩；特殊标记策略使用原宿主。工程证据归BASELINE，可玩范围归FEATURES。未来能力按真实内容需要扩展，不从本文概念名称推断已有类或功能。

# War3、SC2编辑器与公共能力层研究

核查日期：2026-11-15。研究起点为P3当前代码与`d663d3d`的P4战斗方案。用户随后要求上提技能抽象，使采矿、工具、设施等可引用同类能力。本页记录来源、证据限制和顾问取舍；采用合同归[行动与作用框架](../systems/action_effect_framework.md)，实施只有[主计划P4](../../docs/plans/foundation-priorities.md#p4方案通用行动基座与战斗组合)一处。此前PoE/WoW/LoL/War3/王者的战斗研究仍见[原研究](act_barrage_references.md#p4公开机制与源码研究)。

## 1. 成熟编辑器真正提供的分工

| 材料与性质 | 本轮直接核查的内容 | 对Reol的启示与限制 |
|---|---|---|
| 暴雪官方[Revisiting the Warcraft III Editor](https://news.blizzard.com/en-gb/article/23395649/revisiting-the-warcraft-iii-editor)，2020 | 对象编辑器管理单位/能力/建筑，触发编辑器管理脚本/自定义事件；AI与资源也有各自入口 | 统一制作工具可以覆盖不同系统，但能力、脚本和AI不必成为同一种运行过程。官方概览不公开原厂引擎源码 |
| 社区工具War3Net：[`TriggerFunctionType`](https://github.com/Drake53/War3Net/blob/5f6f7bac26ed7ce7d0db83ceb4fb9ce59f918ff8/src/War3Net.Build.Core/Script/TriggerFunctionType.cs)、[`TriggerRenderer`](https://github.com/Drake53/War3Net/blob/5f6f7bac26ed7ce7d0db83ceb4fb9ce59f918ff8/src/War3Net.Build/TriggerRenderer.cs#L28) | 实读Event/Condition/Action/Call分类、参数类型校验与触发注册/条件/动作的脚本生成 | ECA制作建立在可调用代码与类型库上。应提供参数化操作包及具名扩展口，而非把所有功能做成监听回调。它是地图工具，不是War3权威模拟内核 |
| 暴雪官方[SC2 Data Module教程介绍](https://news.blizzard.com/en-gb/article/10040333/new-maps-and-mods-tutorial-data-module)，2013 | 数据模块可改单位数值、能力与武器；另有触发模块教程 | 数据定义与流程编排相互配合，不从“数据驱动”推导无需领域代码 |
| 暴雪官方[SC2 5.0补丁](https://news.blizzard.com/en-us/article/23482838/starcraft-ii-5-0-patch-notes)，2020 | 明列`CAbilHarvest`采集容量字段、`CAbilBuild/Train`相关字段；建造向表现发送开始/取消/完成/暂停/继续事件；Data Collection便于组织关联数据 | 采集/生产可属于能力体系，同时保有专用执行语义；不能据此说采矿都是普通伤害树。成套数据与可定位生命周期能改善制作效率 |
| SC2教程存档[Data Editor Introduction](https://s2editor-guides.readthedocs.io/New_Tutorials/04_Data_Editor/058_Data_Editor_Introduction/) | 分开Ability、Behavior、Effect、Requirement、Validator、Unit、Actor等目录，并提供关联导航和原始XML视图 | 借鉴有类型的定义和依赖导航，不照搬数十种目录；一份Resource不等于一种全能单位 |
| 同存档[Validators](https://s2editor-guides.readthedocs.io/New_Tutorials/04_Data_Editor/071_Validators/) | 效果执行、持续行为停用/移除等位置可使用条件，宿主决定失败后的处理 | 复用条件谓词，同时显式声明检查时刻与失败政策；不能把起手通过视为最终必定成功 |
| 同存档[Actors](https://s2editor-guides.readthedocs.io/New_Tutorials/04_Data_Editor/060_Actors/) | 教程明确区分游戏逻辑与本地异步表现；Actor按事件控制音画，表现不应决定玩法 | 保留World权威与脱离表现，不用动画事件驱动伤害或物品产出。Reol是单机，不搬SC2联网模型 |
| 同存档[Action Definitions](https://s2editor-guides.readthedocs.io/New_Tutorials/03_Trigger_Editor/038_Action_Definitions/)及[Trigger Editor](https://s2editor-guides.readthedocs.io/New_Tutorials/03_Trigger_Editor/032_Trigger_Editor_Introduction/) | 可把重复动作组成带参数的可复用定义，触发系统背后有Galaxy脚本 | “通用代码层”的有效出口是可复用的操作/条件和组合，而不只是技能模板。Reol先做有限组合，复杂算法用GDScript领域扩展 |
| CDDA项目[Effect On Condition文档](https://docs.cataclysmdda.org/JSON/EFFECT_ON_CONDITION.html) | 可将对话条件/效果用于其他入口；有事件/周期激活，支持不同上下文主体及无需主体的作用 | 旁证跨系统条件/作用库可行；也提醒上下文角色要显式。Reol不照搬其对话语言或每个角色的周期规则副本 |
| Godot 4.7官方[自定义Resource](https://github.com/godotengine/godot-docs/blob/4.7/tutorials/scripting/resources.rst)、[类型化导出](https://github.com/godotengine/godot-docs/blob/4.7/tutorials/scripting/gdscript/gdscript_exports.rst)、[Inspector插件](https://github.com/godotengine/godot-docs/blob/4.7/tutorials/plugins/editor/inspector_plugins.rst) | 经Context7核对原生资源类、类型化资源数组和Inspector扩展 | 可延用P3制作资产，不必另装战斗运行时。编译成只读值是本项目选择，不把Resource共享可变对象当实例存储 |

War3可概括为对象数据/原生能力与指令、ECA脚本共同提供能力；SC2进一步展示Ability/Effect/Behavior/Validator等数据分工和Actor表现。这里借鉴的是可观察的编辑接口与公开代码结构，不宣称掌握暴雪C++内部实现。商业编辑器中的采矿、训练等专属能力也不能证明Reol必须照搬其流程。

## 2. 来源归属、版本与取回记录

SC2教程当前由[SC2Mapster/blizzard-tutorials](https://github.com/SC2Mapster/blizzard-tutorials)维护；README说明保存原暴雪托管教程，首页进一步区分原官方教程与暴雪赞助、社区专家编写的完整指南。本页称“教程存档”，不把社区托管站或每页内容一概当作暴雪原厂实现文档。本轮按master快照`d0b3a884db5e33cdbf42d62f6490fcd3e55da1e3`取回选定Markdown。

War3Net按master快照`5f6f7bac26ed7ce7d0db83ceb4fb9ce59f918ff8`取回上述分类、数据结构、渲染器、初始化代码与[LICENSE](https://github.com/Drake53/War3Net/blob/5f6f7bac26ed7ce7d0db83ceb4fb9ce59f918ff8/LICENSE)，许可为MIT；没有编译/运行或移植C#。此前Warsmash的AGPL许可与独立社区引擎性质沿原研究，不因讨论编辑器改变依赖选择。

官方HTML、固定SHA源码、URL/文件哈希清单留`.local/advisor/universal-actions-20261115/sources/`。SC2Mapster wiki.gg的Harvest/Build/Train页面本轮被工具403拒绝，几个猜测的教程路径也不存在；它们不作为已读证据。关键采集/建造结论由实际取得的官方5.0原文支持，未采信顾问的具体采矿阶段数、内部类实现或冲突细节。

本轮没有取得War3/SC2原厂完整游戏源码，也没有找到已经证明适配Reol各领域与存档的可直接嵌入Godot内核。选型是借鉴原生实现，未新增运行依赖；不是声称所有Godot插件都不可适配。

## 3. 现有Reol接口核查

| 当前事实 | 对方案的影响 |
|---|---|
| `World.begin_interaction/settle_action/release`已有接近/预约/耗时/完成/中断，`actions`按人物索引；Combat另有动作/意图/CD | 提取公共生命周期与准入，ACT/交互采用不同策略；不在两份表重复持有同一动作事实 |
| `settle_action`在开工/完成前调用`facilities.in_range`，对移动目标读取当前`combat.position` | 撤回顾问“交易没查实时距离”的断言；新的参与者协议解决同意/占用/新命令交接，不虚构旧bug |
| `Combat.request`成功起手扣物品并起CD；做饭完成时验料/扣料；建设材料/剩余工期在蓝图 | 付款/退款/进度属于明确业务政策，框架不能自动改为出手付款或取消全退 |
| `Objects.transfer`可部分搬运；`exchange`先验双方最终容量再一次交换 | 共同结果须表达实际量，原子交换保留为具名领域操作，不能拆成两次独立搬运 |
| 当前灶台默认沿`Objects.create(capacity=-1)`；地板定义与阻挡建筑的检查条件也有区别 | 不能仅因看到`add`就宣称存在“满台溢出”，也不能把两个条件分支的先后当成已复现的半提交漏洞；新增有限容量/复合占地仍需完整预检 |
| `Facilities.interrupt`代管`construct/sow`进度，Society在发起方记录伙伴等待 | 迁移所选交互时让领域自己交接进度，参与者有明确可撤销关系；不是重写全部社会/任务系统 |
| `Society.use_ability`中的`wood_mend`目前耗气/能量，恢复执行者自身HP | 不把顾问按名字猜测的植物疗伤当事实；跨域样例另做引水术，原自疗迁移保持用途 |
| `World.emit`输出只读后果/人物记录，不是权威事件引擎；Nature按分组更新 | 新内部反应不借HUD通知反向写世界；批计算继续直接运行，离散作用/结果才共用合同 |
| resource/wood是有限库存夹具，P3没有完整矿藏领域 | 采矿是设计例，首片用已有gather/transfer和植物照料证明，不宣称矿业已经存在 |

## 4. 递进咨询与开发者裁决

本轮通过本机入口进行了**三轮递进双顾问咨询，Hydrogen与Argon共六份答复均完整返回**。原件留`.local/advisor/universal-actions-20261115/{round1,round2,round3}`，每轮独立冻结问题与附件。第一轮比较三条路线并联网研究成熟编辑器；第二轮审查候选/代码纠错，第三轮审查完整规格、主计划、战斗时序和补充源码，后两轮均为静态评审、未另行联网。正式采用内容只维护于规格和主计划；顾问没有运行游戏或测量性能，其一致意见也不是验证结果。

| 争点 / 顾问意见 | 开发者核查与决定 |
|---|---|
| 继续战斗专属；或所有事件都以单位cast实现 | 选择公共行动/条件/作用/结果/反应，领域负责实际规则。没有单位的来源、持续过程与批量自然计算均可参与，不造假施法者 |
| ACT和交互各包一层接口即可 | 一份公共运行头＋策略专属状态，准入/支付/取消不能两边各写一套；过渡旧入口也必须过共同闸门 |
| 看到`release`就断言所有生活命令都能取消战斗硬直 | 上层`World._command`已有状态门禁，不能据局部摘录直接断言已复现漏洞；迁移仍要让公共入口统一检查，防未来新调用绕过 |
| 所有起手成本移到出手，或做饭必须开工托管/取消返还 | 不采纳全局改规。迁移保原付款/进度政策，成本时机和退款需由具体定义声明 |
| 多成本只合并最终净变化 | 补充总支出可用性与最终容量两种检查；同组产出不能抵消前置成本，参数别名必须规范化；复杂操作不自动可原子准备 |
| 普通效果序列/双向交易都由通用加减节点表示 | 交易/配方/施工由具名复合操作一次提交；多目标命中、跨时间交付可独立失败，不做全局回滚 |
| 同一领域操作在起手/交付均检查成本，就等于只扣一次 | 补成本申报、具名绑定和一次性核销依据；绑定具体激活/调用/交付序号，不能只用`op_id`免单。原子准备计划与普通序列失败策略分开 |
| 原动作先清掉，新动作失败再恢复；或旧收尾直接启动伙伴新任务 | 采用只读预检→按run一次终止→复核并提交新动作→后果/反应的同刻交接；拒绝不无故清旧动作。回调校验expected_run，不能覆盖新动作 |
| 清理时按人物ID删状态，或把动作相位/到期再存Units一份 | 已迁移run为唯一原状态；页持运动任务/派生摘要，旧唤醒按run/提交序号作废。动作终止、受击保护和内容明确保留的窗口分别处理，不自动抹去全部状态 |
| 反应一律全局FIFO、收齐整段碰撞后再处理死亡 | 不采用。保持战斗按真实时间的命中桶/因果波次，较早死亡能取消较晚攻击；公共层不覆盖原P4的时序合同 |
| 步末清空队列；预算随Context复制；加载时清掉失联占用即可 | 不采用。未来交付/链预算必须保存，索引重建；原状态矛盾拒载，不能隐式删承诺。已完成零时间工作与未来承诺分开 |
| 必须零分配、增加超过10%/25%就失败、批处理改事件会慢百倍 | 不采信无测量数值。控制实际工作量并做相关短窗，当前24人是比较配置，非长期容量上限 |
| 首片顺便实现新矿业、全图燃烧/降雨和无人炉 | 选择现有收集/烹饪/施工/交易适配＋手工照料/引水术同源小样；其余用接口走查，继续交原战斗组合 |
| A2引水术先做静物飞弹扫掠，或A2保留独立旧交互表直到全生活重写 | A2显式选定植物，静物全交付查询归D；旧交互以唯一run容器＋原领域适配接续。B适配进食，C/D分清反应合同与真实生产者验证 |
| 所有反应派生召唤永远禁止自主新激活，或不同状态链取最小预算拼合 | 不采用。明确获准的有限生产者沿13.6运行，事件追加仍继承旧链；同实例续期保原链，独立/替换有明确新链，跨来源合并不隐式拼预算 |

## 5. 下一步证据

下一步是按P4-A1/A2制作并观察共同门禁、真实操作复用、原物/成本/进度守恒和ACT行为。资料研究不能证明接口成本、输入手感、实际Inspector制作效率或完整恢复已经通过。本轮只改候选方案/来源/接续，没有更改游戏代码、存档格式或P3试玩包。

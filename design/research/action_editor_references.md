# 成熟编辑器与可复用能力架构研究

核查日期：2026-11-15。研究起点为P3当前代码与`d663d3d`的P4战斗方案，继续核查War3/SC2、环世界、PoE与暗黑的制作/扩展方式。用户希望技能、工具、设施等能引用共用能力，同时保留专用脚本和效率；玩家类比不构成正式架构定义。本页记录来源、证据限制和顾问取舍；采用合同归[行动与作用框架](../systems/action_effect_framework.md)，实施只有[主计划P4](../../docs/plans/foundation-priorities.md#已完成基座)一处。此前PoE/WoW/LoL/War3/王者的战斗研究仍见[原研究](act_barrage_references.md#p4公开机制与源码研究)。

## 1. 成熟编辑器真正提供的分工

| 材料与性质 | 本轮直接核查的内容 | 对Reol的启示与限制 |
|---|---|---|
| 暴雪官方[Revisiting the Warcraft III Editor](https://news.blizzard.com/en-gb/article/23395649/revisiting-the-warcraft-iii-editor)，2020 | 对象编辑器管理单位/能力/建筑，触发编辑器管理脚本/自定义事件；AI与资源也有各自入口 | 统一制作工具可以覆盖不同系统，但能力、脚本和AI不必成为同一种运行过程。官方概览不公开原厂引擎源码 |
| 社区工具War3Net：[`TriggerFunctionType`](https://github.com/Drake53/War3Net/blob/5f6f7bac26ed7ce7d0db83ceb4fb9ce59f918ff8/src/War3Net.Build.Core/Script/TriggerFunctionType.cs)、[`TriggerRenderer`](https://github.com/Drake53/War3Net/blob/5f6f7bac26ed7ce7d0db83ceb4fb9ce59f918ff8/src/War3Net.Build/TriggerRenderer.cs#L28) | 实读Event/Condition/Action/Call分类、参数类型校验与触发注册/条件/动作的脚本生成 | ECA制作建立在可调用代码与类型库上。借鉴具名操作/条件和脚本扩展，不据此要求Reol重造完整触发语言。它是地图工具，不是War3权威模拟内核 |
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

## 3. P3起点的接口核查

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
| `settle`中的`RESOURCE/HARVEST`目前由Units模式推进，`settle_action`借页模式判断接近/工作 | 不能只扫描`world.actions`就认定全部前台占用已被收口。A1有旧模式owner适配，A2迁移交互相位/到期时清除双写 |
| `_advance_interval`先按时间排序处理身体ready/settle，再调用Combat结算该段；ready编码未携run身份 | 静态流程提示跨域更早死亡/旧ready误结算风险，A2须按真实时刻提交、候选产生时捕获run；尚未运行复现，不写成已通过或已证实的具体玩法bug |
| Runner成功读取候选/练习重置后增加epoch，并拒绝旧epoch命令 | 世界内ID随旧档可能回退；保留既有会话边界，不能以“64位ID持久化”替代 |

## 4. 编辑器咨询与开发者裁决

编辑器研究阶段通过本机入口取得**三轮递进双顾问、六份完整答复**。原件留`.local/advisor/universal-actions-20261115/{round1,round2,round3}`，每轮独立冻结问题与附件。第一轮比较三条路线并联网研究成熟编辑器；第二轮审查候选/代码纠错，第三轮审查规格、主计划和战斗时序，后两轮为静态评审。下表按当前裁决维护，进一步精简见第6节；顾问没有运行游戏或测量性能，一致意见也不是验证结果。

| 争点 / 顾问意见 | 开发者核查与决定 |
|---|---|
| 继续战斗专属；或所有事件都以单位cast实现 | 选择公共行动/条件/作用/结果/反应，领域负责实际规则。没有单位的来源、持续过程与批量自然计算均可参与，不造假施法者 |
| ACT和交互需要共享协议，所以必须合入一张运行大表 | 共享准入/支付/取消规则，各领域保留唯一运行记录；共同绑定只索引owner/run，不复制相位/CD。旧入口过同一闸门；具体精简依据见下文再审 |
| 看到`release`就断言所有生活命令都能取消战斗硬直 | 上层`World._command`已有状态门禁，不能据局部摘录直接断言已复现漏洞；迁移仍要让公共入口统一检查，防未来新调用绕过 |
| 所有起手成本移到出手，或做饭必须开工托管/取消返还 | 不采纳全局改规。迁移保原付款/进度政策，成本时机和退款需由具体定义声明 |
| 多成本只合并最终净变化 | 补充总支出可用性与最终容量两种检查；同组产出不能抵消前置成本，参数别名必须规范化；复杂操作不自动可原子准备 |
| 普通效果序列/双向交易都由通用加减节点表示 | 交易/配方/施工由具名复合操作一次提交；多目标命中、跨时间交付可独立失败，不做全局回滚 |
| 同一领域操作在起手/交付均检查成本，就等于只扣一次 | 成本归属与支付时刻必须明确。首样统一有效照料时由领域消费水，保留原起手箭矢/完成配方政策；未来提前支付仍需一次性交付证据，不先造通用凭证系统 |
| 原动作先清掉，新动作失败再恢复；或旧收尾直接启动伙伴新任务 | 采用只读预检→按run一次终止→复核并提交新动作→后果/反应的同刻交接；拒绝不无故清旧动作。回调校验expected_run，不能覆盖新动作 |
| 清理时按人物ID删状态，或把动作相位/到期再存Units一份 | 已迁移run为唯一原状态；页持运动任务/派生摘要，旧唤醒按run/提交序号作废。动作终止、受击保护和内容明确保留的窗口分别处理，不自动抹去全部状态 |
| 反应一律全局FIFO、收齐整段碰撞后再处理死亡 | 不采用。保持战斗按真实时间的命中桶/因果波次，较早死亡能取消较晚攻击；公共层不覆盖原P4的时序合同 |
| 步末清空队列；预算随Context复制；加载时清掉失联占用即可 | 不采用。未来交付/链预算必须保存，索引重建；原状态矛盾拒载，不能隐式删承诺。已完成零时间工作与未来承诺分开 |
| 必须零分配、增加超过10%/25%就失败、批处理改事件会慢百倍 | 不采信无测量数值。控制实际工作量并做相关短窗，当前24人是比较配置，非长期容量上限 |
| 首片顺便实现新矿业、全图燃烧/降雨和无人炉 | 选择现有收集/烹饪/施工/交易适配＋手工照料/引水术同源小样；其余用接口走查，继续交原战斗组合 |
| A2引水术先做静物飞弹扫掠，或为统一容器重写全部生活 | A2显式单目标提交，静物全交付查询归D；交互保原owner并纳入共同协议，旧持占用模式也须被识别。B适配进食，C/D分清反应合同与真实生产者验证 |
| 所有反应派生召唤永远禁止自主新激活，或不同状态链取最小预算拼合 | 不采用。明确获准的有限生产者沿13.6运行，事件追加仍继承旧链；同实例续期保原链，独立/替换有明确新链，跨来源合并不隐式拼预算 |

## 5. 环世界、PoE与暗黑提供的补充证据

这些资料共同支持“定义配置、复用机制与专用代码可以共存”的设计选择；不证明Reol性能已经改善，也不代表三个系列使用相同内核。

| 材料与性质 | 直接核查内容 | 对Reol的采用与限制 |
|---|---|---|
| RimWorld社区作者样例[`Example_JobDefs.xml`](https://github.com/RWDevathon/ExampleMending/blob/4f871d444bb4d1248a0915b10573228b49195e97/Defs/Example_JobDefs.xml)、[`JobDriver_Mend.cs`](https://github.com/RWDevathon/ExampleMending/blob/4f871d444bb4d1248a0915b10573228b49195e97/Source/ExampleMendingJob/JobDriver_Mend.cs) | 定义绑定脚本；脚本取得预约、复用接近步骤，再写修理计时/结束/不可接触失败逻辑。About.xml声明支持1.6 | 共享步骤与专用流程相配合；不要求所有流程改成效果图。RimWorld的Job可含接近/工作，不机械等同Reol的高层任务或单次攻击 |
| RimWorld社区[ThingComp教程](https://rimworldwiki.com/wiki/Modding_Tutorials/ThingComp) | 配置与附着实例、生命周期/保存钩子及Normal/Rare等不同更新入口 | 扩展能力应绑定合适宿主与寿命。方法清单注明旧版，不当现行完整API；本项目不照搬每实体组件对象及tick频率 |
| GGG开发者Mark_GGG的[2019年宝石/辅助答复](https://www.pathofexile.com/forum/view-thread/13707/page/30) | 区分宝石分类标签与辅助适用性；辅助改变行为可能令另一辅助适用，但不因此改宝石标签 | 分开分类、真实机制能力和组合条件，不用一个tags列表包办三者；历史PoE1机制说明，不是PoE2版本承诺 |
| GGG官方[Heist技能改版](https://www.pathofexile.com/forum/view-thread/2934377)，2020 | Intensity可内置到不同技能/辅助，技能有多弹/分裂交互，持续风暴设并存上限并说明性能收益 | 同一机制参数服务多内容，生产频率/数量是明确规则；不复制具体技能优先级、数值或推测服务端类 |
| PoB Community固定SHA的[`CalcTools.lua`](https://github.com/PathOfBuildingCommunity/PathOfBuilding/blob/6d1d39837b0d5b0f4a3ede05d06b7594bdbcc556/src/Modules/CalcTools.lua#L84)及前次已读`ModDB.lua` | 辅助匹配含require/exclude机制类型、武器和来源特例；修饰可按源集合求和/乘算 | 可借显式资格与修饰重建，但它是构筑计算器，不能据此声称读过GGG实时服务器。P4不复制完整宝石系统/伤害转换 |
| Diablo I社区重构DevilutionX：[`spelldat.tsv`](https://github.com/diasurgical/DevilutionX/blob/63809e6bbd9e840fb371bcb96ff636c56f14f60e/assets/txtdata/spells/spelldat.tsv)、[`spells.cpp`](https://github.com/diasurgical/DevilutionX/blob/63809e6bbd9e840fb371bcb96ff636c56f14f60e/Source/spells.cpp#L207)、[`missiles.cpp`](https://github.com/diasurgical/DevilutionX/blob/63809e6bbd9e840fb371bcb96ff636c56f14f60e/Source/missiles.cpp#L4208) | 表定义费用/载荷；CastSpell取表创建交付并有特例；AddFirebolt/AddTeleport保留各自算法，ProcessMissiles调用绑定的processFn | 参数表与具名处理器并用。不能照搬“传送也叫missile”的历史命名，不当成D3/4内核，也不误称当前全由大switch推进 |
| Blizzard官方[D4 2.0 PTR符文说明](https://news.blizzard.com/en-us/article/24130178/the-2-0-ptr-what-you-need-to-know)，2024 | 条件生成Offering，调用消耗Offering产生效果，有溢出及装备组合限制，部分效果替换下一次闪避 | 条件/累积/资源/效果可按明确合同组合；P4用已有资源/反应实现所需部分，不另加完整符文装备系统。历史PTR玩法资料，不是内核源码或当前版本保证 |
| GDC 2013 [Through the Grinder](https://www.gdcvault.com/play/1017794/Through-the-Grinder-Refining-Diablo)官方会话摘要 | 摘要涉及控制响应、恢复和技能/符文的反复迭代 | 支持先做可玩小样迭代；本轮未观看完整视频/幻灯，不采用顾问从演讲推导的具体放弃原因或源码结构 |

`ExampleMending`固定SHA为`4f871d4`，仓库未见明确LICENSE，仅作结构参考、不复制脚本；DevilutionX固定SHA为`63809e6`，实际读到的[LICENSE](https://github.com/diasurgical/DevilutionX/blob/63809e6bbd9e840fb371bcb96ff636c56f14f60e/LICENSE.md)为Sustainable Use License，不能按MIT/GPL组件引入。两者均未编译或运行。PoB沿前次固定SHA/许可记录，未为本轮滚动dev分支替换证据。

原件、SHA与文件哈希清单留`.local/advisor/p4-capability-review-20261115/sources/`。RimWorld教程、PoE论坛经联网工具实际取得正文，普通HTTP另取原件时403，未伪称原HTML已落盘；D4原文和选定DevilutionX源码已落盘。先前顾问引用的RimWorld反编译仓库不可用，没有寻找镜像或作为已读证据。未核查的D2函数编号/列数、PoE2补丁特例和Diablo具体Issue叙事均不进入正式断言。

## 6. 能力架构再审与开发者裁决

本次在编辑器咨询之后**新增三轮递进双顾问咨询，Hydrogen与Argon共六份完整答复均返回**，原件留`.local/advisor/p4-capability-review-20261115/{round1,round2,round3}`。第一轮比较成熟项目与原案复杂度，第二轮用当前World/Combat等源码反证精简候选，第三轮审查修订规格/主计划/战斗合同与精确源码摘录；后两轮未联网。最终正文已纳入采用项与必要修正，未追加第四轮或把审查意见本身当运行证据。

| 争点 | 采用方向与理由 |
|---|---|
| 特殊场景也应新建一种通用类 | 先判断是配置、局部算法、共享机制还是新领域；专用脚本可依附既有机制。固定“第三个实例才抽象”同样不是硬规则 |
| 共享执行一定要共享一张运行表 | 只共用必要协议；绑定索引owner/run，各策略唯一持有相位/到期。交互旧Mode需要明确owner适配，不能以不搬表为由留下影子动作 |
| 操作包增加分支、ResultRef、延时和循环可实现通用代码层 | P4采用有限同步列表；复杂数据依赖/编排使用受信项目脚本。周期/延时放在明确宿主中，不造图解释器或预建新定时队列 |
| 通用事务才能保证所有效果正确 | 多成本、交易/配方保原子提交；其他领域做自身必要整体校验。普通伤害后上毒被免疫不回滚伤害，不做任意跨域事务语言 |
| 单线程即可省略支付/交付证据 | 只省去过早的通用凭证系统。前摇/离手/保存存在时间跨度，必要已付/已交付序号仍保存；首个照料样例不要求提前消费材料 |
| 脚本白名单就等于沙盒、所有新机制注册一行即完成 | 它是受信代码扩展；原owner、时间、结果、取消/销毁与恢复必须接好，不能绕过公共规则或靠共享模板存实例状态 |
| 因果预算等于全游戏事件溯源 | 对存在派生的链按需建共享记录；分支深度/规则CD/传播范围各有归属，未完承诺保存，结束回收；诊断另用有界缓冲 |
| 持久化64位run_id就能删除会话epoch | 不采用。读取旧档可能回退世界内计数，现有Runner会话代次仍防旧命令；不把两个顾问重复建议当证明 |
| 同刻结算必须对任意人物ID交换完全不变，或链按固定寿命强制清空 | 不采用。沿战斗规格的稳定裁决，同盾争夺/归属可依稳定键；仍有后代的链不能到期洗白预算 |
| 专用算法写40行即可100%复用现有御剑能力 | 不采用行数/自动完备承诺。当前P3只有已验证去回程等语义，悬停/周期发射归D；新增脚本仍有自己的边界与恢复责任 |
| 顾问把`combat.controls`当P2抗控预算，或据此断言普通交互清掉全部保护 | 源码明确它是本地持续输入，受击/保护记录归`status`；撤回错误字段解释。仍在A1按真实职责拆清run终止、导航/输入与死亡清理，适配内部旧状态转移 |
| 所有边界新交付都排死亡后，或控制命中立刻撤姿态影响同桶后续资格 | 明确直接数值/领域交付进入基础桶；瞬移/新空间/拓扑另在后续空间阶段。同波次姿态资格冻结，桶闭合后同步终止，再处理次级反应 |
| 完整反击先扣规则CD再请求行动；新主动毒叠层可无条件换链 | 完整行动在共同网格联合准入后才采用规则CD/配额/动作成本。传播状态按链隔离或显式替换；普通P3状态不因此全改语义 |

## 7. 研究与实现边界

研究阶段提出的A1/A2～E现已实现；实际证据与未验证范围归BASELINE。以下保留来源与取舍，不将参考游戏做法当作Reol已实现事实。

## P4实施审查裁决

A1双顾问原件：`.local/advisor/p4-implementation-20261115/a1/review/`。已核查采纳正常收招保留连段窗口、弹体独立保留group_ms/重击字段、有限载荷校验、结束模式归一、旧采集预约和内部准入、候选运行/运动身份、事件时间基准。对全量演员扫描的意见通过仅处理竞争者实现；读档重建仍允许全域校验。没有把顾问给出的P0标签当项目断言。实际短例/GUI见BASELINE。A2双答已核查，采用事件时刻空间/拓扑边界、HP先不可用、伙伴唯一宿主和生命周期一次终止。

B/C/D双答原件分别在`.local/advisor/p4-implementation-20261115/b/review/`、`c/review/`、`d/review/`。已核查采用：同刻姿态快照/桶后终止、盾/状态到期、修饰重建、链归属/死亡传播隔离、完整动作FIFO与门禁无副作用、Area实际时刻采用、反应伤害来向、子弹/器物残段双端截取、光环精确到期/移除清理、地图边缘、单器物损坏、出生扩页和索引重建。所有意见按现源码重验，不以顾问优先级标签代替影响判断。

未采用/修正：period15/25ms的区域/DoT反例不满足当前定义下限50ms；不据此引入任意高频调度。防守派生仍继承原因果预算，不另起新根绕过循环上限。自主器物按合法正周期发射属于新激活，额外反应与接触继承祖链。完整行动选择严格下一50ms共同网格，更新规格而非声称达到旧16/17ms候选。静态受体的状态操作本来就检查身体能力，未照抄“必然崩溃”的假说；实际带载荷/受体测试按采用路径补充。脚本签名用显式逻辑版本，避免导出依赖源码文件。

E整合审查两份完整答复均已核查，原件在同目录`e/review/`。采纳并补反例：器物/实体读定义与载荷宿主规则快照的校验分工、受控随从仍推进周期、零方向结果形成有效派生朝向、合法新动作清旧收招惩戒、移除身体清未开始请求、旧选中目标不可见不挡方向技能、原生嵌套引用按类型校验、坏Loadout短路、同ID原生DoT周期一致性。无须弱化payload宿主的必需规则字段。

未照抄的结论：实体精确到期已在`World._advance_interval`末尾清理，现有到期恢复反例通过，未将`<=`放宽为`<`；状态寿命最小1ms，非50ms，末段光环不因短寿命天然非法；额外槽明确映射到skill窗口，不需重复加入相同唤醒时刻。普通缓冲允许等待命中回怒/回蓝，未因静态预查费用丢掉合法未来输入。静态受体不具身体动作能力，由共同门禁拒绝完整请求；不将它的所有反应配置一律禁止。器物实际发射前按需重建索敌索引，恢复也重建缓存。

最后相关规则、真实GUI/Inspector、源码→导出PCK在途恢复和独立exe短窗已完成；实际结果与失败记录归BASELINE。没有移植外部商业游戏代码或增加第三方战斗运行时。

## 8. 可编排单位策略：P5研究，未实施

用户提出开发者、模组/创造模式玩家及AI作者可制作行为程序并附加给单位；普通玩法不必提供编程界面。这个方向表达的是策略可替换与单位差异，不预先指定行为树、脚本语言、智力属性或自走棋玩法。AI可以是策略制作者，不要求运行时大模型参与决策。实施范围仍只归[主计划](../../docs/plans/foundation-priorities.md#下一阶段候选)，新增预警系统继续后置。

### 8.1 本轮核查的公开来源

| 来源 | 已核查事实 | 对当前项目的参考价值 |
|---|---|---|
| [Gladiabots官网](https://gladiabots.com/)及[开发者Steam介绍](https://store.steampowered.com/app/871930/GLADIABOTS__AI_Combat_Arena/) | 玩家构造机器人AI并观察竞技场执行；提供无需编程知识的组合和沙盒测试。官网wiki本轮不可访问，未据其推断精确节点调度 | 参考制作→运行→观察→修改的循环，不声称有原厂开源代码或照搬其竞技玩法 |
| EA官方[Dragon Age: Origins PC手册](https://eaassets-a.akamaihd.net/eahelp/manuals/dragon-age-origins-manuals_PC.pdf)，Combat Tactics | 从上到下检查条件并执行对应动作；可排序、保存策略，并另有距离/追击等一般行为偏好 | 条件—动作优先级表可以作为低代码入口，无须先制作大图编辑器；规则顺序和运行任务的关系仍需自行定义 |
| Screeps官方[介绍](https://docs.screeps.com/introduction.html)及[CPU限制](https://docs.screeps.com/cpu-limit.html) | 脚本驱动单位自主反应；脚本执行与计划行动分阶段，服务器有执行时限 | 借鉴查询/意图接口和成本边界，不引入其联机模式、CPU收费或声称GDScript具有相同强制中断能力 |
| Godot4.7官方[Resource](https://github.com/godotengine/godot-docs/blob/4.7/tutorials/scripting/resources.rst)、[GraphEdit](https://github.com/godotengine/godot-docs/blob/4.7/classes/class_graphedit.rst)、[线程安全](https://github.com/godotengine/godot-docs/blob/4.7/tutorials/performance/thread_safe_apis.rst) | 资源按路径共享缓存；GraphEdit提供图形交互但不执行图逻辑；活动SceneTree不支持从工作线程直接操作，共享Resource不能被多线程随意改写 | 原生Resource/Inspector继续作作者工具；图形编辑与模拟执行分开，单位状态不写共享模板 |
| [Beehave仓库](https://github.com/bitbrain/beehave/tree/godot-4.x) | MIT、GDScript行为树，主要在SceneTree中组合节点；README列Godot4分支和版本选择 | 有现成编辑/调试方式，但当前无每单位Node的模拟不能直接照接；没有在Reol运行或比较其性能 |
| [LimboAI仓库](https://github.com/limbonaut/limboai)、原始[BehaviorTree](https://github.com/limbonaut/limboai/blob/master/doc_classes/BehaviorTree.xml)与[BTInstance](https://github.com/limbonaut/limboai/blob/master/doc_classes/BTInstance.xml) | MIT代码、C++模块/GDExtension；定义为Resource、实例为RefCounted，实例化接口仍接agent/owner Node。README列1.8.x对应Godot4.7模块/4.6+扩展 | 不能误称其所有任务都是SceneTree节点，也不是纯GDScript依赖。采用需要适配线程/agent/存读，版本表不是本项目兼容测试 |

以上为2026-11-15本轮实际打开的官网/手册/仓库资料；移动分支仅代表阅读时内容，不是项目锁定依赖。未安装插件，未对第三方编辑器或运行时做性能实验。

### 8.2 当前落点与建议

当前事实：`combat.gd._think`在原50ms自主思考节拍内读取本人感知，靠近已观察位置并请求primary；Combat同时还负责动作与伤害，不能把整类都替换为策略脚本。生活选择归Livelihood，临时随从的跟随入口另在Entities，直接控制另有持续输入。当前没有可挂接的通用行为程序或控制权仲裁平台。

建议先确定“本人观察与记忆→策略选择→行动意图→原执行准入”的接口，再选择首个制作形式：

- 查询给本人生命/资源、实际可知目标及有限局部候选和结果，不交出活World引用；脚本中的目标身份不是可随时查询全图真相的授权。
- 程序定义/参数可以共享，每单位独立保存目标、当前决策任务、记忆和必要的下次思考时刻。已有动作run、CD、已付成本仍归原宿主，行为任务结束/放弃不等于取消已承诺动作。
- 手动控制、战斗策略与生活策略先有明确交接。移动、瞄准和出招可以同时存在，各控制通道需要明确采用来源；不把“一个思考结果”误解为每拍只能移动或出招。首版只接战斗，不让多个策略每帧争抢身体，也不把普通手动移动命令直接当AI移动API而顺带改掉autonomous/工作状态。
- 规则表、行为树、Utility评分和受信GDScript都是不同制作/选择方式，不必同时实现。首个低代码入口可用Resource/Inspector组合少量条件—动作优先级规则；复杂局部策略可用显式注册的项目脚本，沿同一接口执行。等真实多步行为需要再扩树/序列，不先造全能VM。
- 规则表须说明重评优先级、正在执行的任务如何继续、拒绝后何时重选；不能每拍重启奔跑或出招。高优先级规则还需检查行动可用性，冷却/费用不足时继续选择其他合法候选，最终提交仍走原门禁。距离带与必要的任务持续条件避免反复进退。允许声明式程序采用有界节点/候选/步骤，查询本身也要有界。受信GDScript的API约束与事后计时不构成安全沙盒，也不能终止任意无限循环；外来低代码数据和受信代码分开处理。项目内Resource可作制作入口，未来外部导入需先校验纯数据，不能把任意Resource或Script直接加载当作隔离机制。
- 沿共同World时间调度，保留现有战斗执行频率；思考按到期/相关事件选择活跃单位，不默认每身体每帧遍历整树。CPU预算是工程成本控制，不直接定义游戏里的智力。程序/参数版本与声明的单位记忆进入对应恢复校验，不保存Callable、World引用或执行中的GDScript调用栈。
- 先做两三种策略和可查看的选择/拒绝原因，验证同程序两单位的状态隔离、失视/目标消失、硬控/承诺、手动接管和在途存读。可视化拖拽编辑器、公开任意脚本沙盒和全生活AI重构不自动进入P5。

以上为候选设计，不构成已实现能力或全部必须建设的类型清单。

### 8.3 顾问核查与裁决

本机双顾问均完整返回，原答、问题及源码附件留`.local/advisor/behavior-programs-20261115/`。采纳共同窄接口、规则数据与受信代码分层、定义与独立记忆分离、可用性预检和选择追踪；按实际风格需要补少量空间行动，不先建设全能运行时或可视图工具。行为树可作为后续制作形式，当前不装插件；这不是第三方性能差或不能适配的实测结论。

没有采纳示例中的固定规则数、记忆槽数、毫秒预算、手动宽限期与升级数量门槛；这些未由项目需要或测量证明。无逐单位Node是现有实现方式，Resource仍需明确只读和线程归属；二者不写成不可改变的产品约束。沿用已有接触记忆与占用索引，不把ActionGate误写成已完成的控制来源仲裁系统。对隐藏目标的死亡事件仍按本人实际可知信息处理，不能因为宿主知道死亡就提前让策略得知。

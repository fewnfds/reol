# ACT与弹幕：成熟方案和采用理由

核查日期：2026-11-14～15。本页保留可核查的外部来源、许可和影响架构判断的理由。当前合同见[战斗规格](../systems/combat_framework/act_and_barrage.md)与[公共行动](../systems/action_effect_framework.md)，代码/验证分别归架构和BASELINE。研究不自动产生实现要求。

## 1. 历史测量边界

旧20Hz链路、P0合成移动与各阶段修复过程由[整理前研究](https://github.com/fewnfds/reol/blob/bd1971c/design/research/act_barrage_references.md)和本机日志追溯，不保留为当前源码接口。当前60Hz、世界后台取舍与原生能力选择见[大型模拟研究](large_simulation_optimization.md)。

### 1.3 60Hz灰盒与密集交战实测

早期60Hz普通24人25秒窗约1×、帧p99约16.80ms；900人ACT高密交战复核约0.748×，没有通过该规模验收。合成移动到CPU显示准备p95曾观察到18.72ms，包含的链路和构建不等于真实设备到屏幕延迟。完整负载、哈希及失败原件见上述固定版本，不与后续P4短窗混算，也不替换performance.json。

## 2. 六个游戏分别解决什么问题

以下“Reol取用”是设计推导，不是对原作代码的描述。官网商店的玩家标签不作为技术证据；未取得官方精确帧表的地方不填“原作同款数值”。

| 参考 | 本次可核查依据 | Reol取用 | 不随之移植 |
|---|---|---|---|
| **DNF / Dungeon Fighter Online** | [Female Fighter Renewal](https://www.dfoneople.com/news/updates/4289/Female-Fighter-Renewal)具体调整基础攻击动作/音效与技能准备；[Spitfire历史调整](https://www.dfoneople.com/news/updates/221/Character-Balance-Update/Male-Gunner/Spitfire)明确记录部分技能可取消基础攻击 | 多段平砍的节奏、显式技能接续、动作/音效一起调；用平面失稳/破势代替长浮空 | 国际服具体职业/历史版本不代表全部DNF；不据部分技能可取消推断所有招式随时可取消；不照搬横版X/Y/Z轴和快捷栏规模 |
| **Hades** | [2019 High Speed日志](https://www.supergiantgames.com/blog/hades-the-high-speed-update-patch-notes/)明确修正基础动作/冲刺后攻击缓冲、取消动画及招式效果与实际出效时刻；[后续官方日志](https://www.supergiantgames.com/blog/hades-updates/)仍调整相关衔接 | 输入缓冲、取消点、移动与攻击关系属于核心玩法，需要反复打磨 | 不把特定社区测得的无敌帧或dash-strike机制当官方合同；不复制死亡返家/随机祝福作为持久世界架构 |
| **暖雪** | [官方商店](https://store.steampowered.com/app/1296830/Warm_Snow/)介绍不同飞剑属性、攻击方式和圣物组合；[2022制作人访谈](https://www.gcores.com/articles/146899)谈动作制作成本、闪避反馈与过度防御构筑的问题 | 飞剑/法器能形成不同操作路线；动画长短、避伤窗口与玩家感受不能画等号；先证明基础原型再扩组合 | 访谈是当时制作人的描述，不作当前帧表；题目中的“别刮痧”不等于无限放大伤害乘算；不照搬其连续闪避规则 |
| **以撒的结合：重生** | [官方商店](https://store.steampowered.com/app/250900/The_Binding_of_Isaac_Rebirth/)将其定义为动作RPG射击，物品改变形态和能力 | 弹体的形状/射法/命中后行为可以形成可感知构筑，敌弹与自己的输出需要区分 | 官网介绍不能证明具体受击核、射击方向和公式；本项目鼠标连续瞄准由本次目标决定，不依赖原作四向限制；房间制/关门清场/死亡重开不移植 |
| **吸血鬼幸存者** | [poncle官方](https://poncle.games/vampire-survivors)与[官方商店](https://store.steampowered.com/app/1794680/Vampire_Survivors/)强调极简操作、持续生存与“成为弹幕”；[联合开发者coherence技术案例](https://coherence.io/blog/tradecraft/vampire-survivors-online-coop-case-study)说明反向弹幕/自动射击及敌人互相推挤对节奏的影响 | 研究玩家输出弹幕的节奏、不同火力形态和有限自动辅助；软分离/群体分布值得关注 | 这是自动输出/构筑主导参考，不是近战手感模板；联网迁移/分布权威方案与Reol单机owner无关；不把海量刷怪和强乘算强加给社会世界 |
| **鬼谷八荒** | [官方商店](https://store.steampowered.com/app/1468810/_/?l=schinese)确认沙盒修仙定位、修行/能力路线等产品背景 | 鼠标朝向术法与修行题材、不同射法的观感列为试玩/设计比较对象 | 本次官方文字证据不足以证明其全部弹幕/身法/CD内部规则，不拿社区流派速通视频当同规则社会模拟的证明 |

需区分四个层面：**谁决定何时开火**（手动/按住/自动）、**谁决定方向**（鼠标/观察所得目标/预设）、**谁制造空间考题**（敌方弹幕）、**什么改变攻击行为**（构筑触发）。它们可组合，但不能把所有参考作品概括成“自动发射很多弹”。

## 3. 手感与可读性的一手资料

| 资料 | 实际支持的内容 | 对本项目的限度 |
|---|---|---|
| [Maddy Thorson：Celeste & Forgiveness](https://www.maddymakesgames.com/articles/celeste_and_forgiveness/) | 开发者明确列出输入缓冲、边缘纠正和时间/位置宽容，帮助表达意图 | 可支持短缓冲思路；横版跳跃纠正不能直接搬成俯视角色穿门框的隐形瞬移，也不证明120ms是唯一正确值 |
| [Riot：Clarity in League](https://www.leagueoflegends.com/en-us/news/dev/clarity-in-league/) | 效果/判定一致，朝向与轮廓可辨，重要性层级明确，减少噪声；弹体静态外观也应表达方向 | 支持危险弹优先于友方装饰，不能提供Reol自己的形状尺寸/性能证明 |
| [Squirrel Eiserloh：Juicing Your Cameras with Math，GDC2016讲义](https://media.gdcvault.com/gdc2016/Presentations/Eiserloh_Squirrel_JuicingYourCameras.pdf) | 伤害脉冲累积/衰减、非线性震动、平滑噪声，以及保留基础相机再加表现偏移（约第10、14、16–18页） | 本次读到62页PDF文本；未观看完整演讲/动画，PDF本身也提示GIF不动。用未震动矩阵瞄准是Reol推导，不声称演讲给了本项目API |
| [Godot4.7：Fixing jitter, stutter and input lag](https://docs.godotengine.org/en/4.7/tutorials/rendering/jitter_stutter.html) | 插值增加依赖模拟tick的输入延迟；提高tick可能增加CPU成本；输入事件合并也有精度/CPU权衡 | 证实需量响应链；Reol是自定义Runner，不能只改Physics设置便宣称已提频。实际延迟取决于项目发布/插值与设备链路，不能用结构推算冒充当前端到端实测 |
| [Godot4.7：Input](https://docs.godotengine.org/en/4.7/classes/class_input.html) | `use_accumulated_input`默认合并相似输入；关闭可能提高响应但增加成本 | 先保证边沿不丢、UI/失焦清零，再实测是否值得关闭；Input轮询不能替代GUI上下文控制 |

当前没有冻结权威世界的命中停顿；射速/弹速、避伤和预警窗口仍需按具体配置试玩。音画要能解释真实规则结果；不能用强震动/爆音掩盖动作延迟或让高频小弹每发都打断视线。

## 4. 成熟方案与开源候选：能用在哪一层

推荐复用**动作阶段/缓冲模式、数据花型、空间候选、连续扫掠和批量渲染方法**。没有找到一个经本次验证、可直接替换Reol共同世界的完整“DNF＋弹幕＋持久社会”成品框架；这不表示每层都要从零研究。

| 项目/资料 | 已核查的版本/许可与能力 | 采用判断 |
|---|---|---|
| [Godot官方Bullet Shower](https://github.com/godotengine/godot-demo-projects/tree/master/2d/bullet_shower)，[具体源码](https://github.com/godotengine/godot-demo-projects/blob/master/2d/bullet_shower/bullets.gd) | 官方GDScript示例；Asset Library的4.2条目标MIT，当前master会变。已读代码以RID管理弹体、关闭弹间碰撞、集中绘制；示例常量500 | **优先学习数据弹体与集中管理**，不是完整ACT/连招/花型编辑器。示例的主线程PhysicsServer接入不能原样取代World离线碰撞，也不能用500这一常量当目标硬件实测 |
| [Godot4.7 Servers优化](https://docs.godotengine.org/en/4.7/tutorials/performance/using_servers.html)、[线程安全](https://docs.godotengine.org/en/4.7/tutorials/performance/thread_safe_apis.html) | Godot原生能力，官方提醒SceneTree并非整体线程安全、Server使用有条件，取回状态可能产生同步成本 | **可直接沿用原生批量渲染方向**；规则先保留CPU/owner。不是任何线程随时读Physics空间都安全 |
| [BulletUpHell免费仓库](https://github.com/Dark-Peace/BulletUpHell) | MIT；README区分Godot3/4，当前所见默认分支`Demo-V4.4`；花型/追踪/方程路径/激光/触发。另有[付费BLAST](https://bottled-up-studio.itch.io/godot-bullethell-plugin) | **研究花型与事件配置**，不默认安装。免费/付费能力不能混用，README的弹数建议不是Reol基准；4.7兼容未跑验证 |
| [GodotProjectileEngine](https://github.com/AzyrGames/GodotProjectileEngine) | MIT，Godot4；作者README当前明确`0.6.x-beta`，不建议生产；模板、生成器、花型、时序分工，池化与SceneTree集成 | **可参考内容表达**，不把测试版整套接入作为本次依赖 |
| [BlastBullets2D](https://github.com/nikoladevelops/godot-blast-bullets-2d) | MIT、C++ GDExtension；README要求4.5+并称已测4.7；提供池化、花型、弹/激光及示例，作者也说明逐弹Y排序等适用限制 | 功能较完整的**原生弹幕候选**，当前不引入。它带有工厂/物理/信号生命周期，接入仍需owner和存读评估；宣传弹量/帧率未经本机复测 |
| [PerfBullets](https://github.com/Moonzel/Godot-PerfBullets) | MIT、C++ GDExtension＋MultiMesh，README声明4.1/4.2、Mobile/Forward+ | 研究批渲染/池化；不能称纯GDScript即插即用，4.7兼容未验证。没有实测瓶颈前不增加原生依赖 |
| [GDQuest A-RPG demo](https://github.com/gdquest-demos/godot-make-pro-2d-games) | MIT源码，README明确Godot3.1；三连剑、两种怪、三阶段Boss、模块化命中/伤害源及完整小循环 | **最贴近三连原型的可读样本**，主要借设计/组织方式。它的旧API、节点式身体/伤害与当前页式World不同，不能整套复制 |

上述MIT按作者仓库/官方条目标示核查，不表示商用美术/音频自动具有相同许可；没有把第三方代码/资产纳入产品。正式选依赖时应固定commit、检查具体LICENSE与资产声明，并验证目标Godot版本；涉及运行时成本时才做相关负载对照。

没有新增行为树/技能树插件：当前四种敌人的观察/决定可以复用原扫描与少量显式状态；动作执行器先稳定，AI组织方式以后按复杂度选择，不把插件多等同于架构成熟。

### 4.1 可复用技能框架与内容编辑工具

用户希望持续制作技能实例，因此另行检查了下列上游的README、许可、版本记录和关键源码。**以下是2026-11-15的来源快照与接入判断，没有在Reol安装这些插件，也没有完成插件GUI、导出或存读适配实测。** 发布标签与所读主分支不是同一个版本时分别注明，不把README的“production-ready”当项目验收。

| 候选与固定源码快照 | 核查到的能力、依赖与维护线索 | 对Reol的取舍 |
|---|---|---|
| [GodotGAS](https://github.com/yulrun/godot-gas/tree/466b877d368c9fb817586992756fc8e8bbc4f67d) | GDScript；README含完整MIT许可；要求4.6+，插件与最新发布均标v1.1.2，2026-10仍有推送。`GameplayEffect`为Resource；Dashboard管理Tags/Cues及属性脚本生成。源码`GameplayAbility`为Node，ASC的`_process`推进持续/周期效果，技能执行可用await任务 | 效果定义、叠层与属性聚合值得参考；Dashboard并非完整技能行为编辑器。整包接入仍须适配身体页、共同时间、效果提交和纯值恢复，不能仅改HP入口就交付 |
| [LiGameAcademy / godot_ability_system](https://github.com/LiGameAcademy/godot_ability_system/tree/362fa1df1586ef0f39e1bd516398df26b241bc0c) | MIT、GDScript；README写4.5+，当前plugin.cfg描述4.7、版本0.0.1，未找到GitHub正式release，2026-10有推送。定义是Resource，组合Features与资源化行为树；`GameplayAbilityInstance.update(delta)`是显式更新接口，但默认组件仍在`_process`调度，实例持`owner: Node` | **运行时插件中值得优先做适配小试的候选**，因为定义/实例已分离且可显式推进。仍需检查目标接口、状态组件、行为树进度与存读，当前证据不足以认定薄适配即可。没有核实到专用技能节点图编辑器 |
| [OctoD旧GGS](https://github.com/OctoD/godot-gameplay-systems/tree/9349931cc7a5f3cb748c7f820b4073f2e31fc981) / [拆分Abilities](https://github.com/OctoD/godot-gameplay-abilities/tree/6d1ce71df494c97a84b8647e979c283d9962b624) | 均MIT。旧版GDScript，最新release0.20.5；README提示重写并建议新项目考虑拆分版。新Abilities是C++ GDExtension，最新release1.0.0rc1，2026-01有推送；Ability资源＋RuntimeAbility＋AbilityContainer，源码默认物理帧回调tick | 定义/运行实例的分工可参考；新版增加二进制构建/分发成本，旧版存在API迁移预期。两者都不是现有World的直接替代品，不默认引入 |
| [Forge for Godot](https://github.com/gamesmiths-guild/forge-godot/tree/56c55837919b852d502254569978fa0f01664ab6) | MIT、C#；最新releasev0.5.0，主分支2026-11仍更新，当前README要求Godot4.7+ .NET和.NET8 SDK。资源化属性/效果/技能、Tags工具与Statescript状态图；核心Forge自称引擎无关，Godot适配`ForgeEntity`默认在`_Process/_PhysicsProcess`更新 | **图形技能制作与规则/表现拆分的较完整参考**。核心可独立推进是优点，但当前项目接入须增加.NET与桥接，不能因图上无需写C#就称无C#依赖；本轮不选作运行时 |
| [Pandora](https://github.com/bitbrain/pandora/tree/fa48e30e6609ecd6dbd9edf25e0a26f64deb26a0) | MIT、GDScript，核查godot-4.x分支；plugin.cfg为1.0-alpha11-dev，2026-08有推送，README明确仍alpha、未生产就绪。提供分类/属性传播的RPG数据编辑器，以及定义实例化/序列化API | 接近“物体编辑器”，但**不是技能执行器**。引入其数据格式、单例与实例模型仍需到World的转换；目前只参考分类与覆写的编辑体验 |
| [YARD](https://github.com/elliotfontaine/yard-godot/tree/613ebfb67f71288e64b901cd47446552450e5d7a) | 插件代码MIT、GDScript；README标4.4+，[最新releasev1.3.2](https://github.com/elliotfontaine/yard-godot/releases/tag/v1.3.2)为2026-11-09，所读主分支已有后续改动，plugin.cfg仍写1.3.0。表格编辑原生资源，Registry存ID/UID映射，提供目录扫描、索引和下拉选择；源码还有运行期查询API及导出插件 | **可选的编辑辅助，未安装**，可避免自制全部表格UI。技能本体继续继承原生Resource；Registry不进入权威战斗状态。它不是纯编辑器零依赖：Registry类型、ID提示与导出索引若被采用，卸载前要替换；复杂嵌套效果仍宜用Inspector |

版本/推送日期只证明对应公开记录存在，不证明质量或4.7.2兼容。YARD插件许可见[addons/yard/LICENSE](https://github.com/elliotfontaine/yard-godot/blob/613ebfb67f71288e64b901cd47446552450e5d7a/addons/yard/LICENSE)；仓库示例部分素材另有许可，不能把整个示例包当MIT素材库。

源码接缝的直接证据包括：[GodotGAS效果tick](https://github.com/yulrun/godot-gas/blob/466b877d368c9fb817586992756fc8e8bbc4f67d/GodotGAS/components/ability_system_component.gd)、[LiGame默认调度](https://github.com/LiGameAcademy/godot_ability_system/blob/362fa1df1586ef0f39e1bd516398df26b241bc0c/scripts/components/gameplay_ability_component.gd)、[Forge适配节点](https://github.com/gamesmiths-guild/forge-godot/blob/56c55837919b852d502254569978fa0f01664ab6/addons/forge/nodes/ForgeEntity.cs)和[YARD Registry](https://github.com/elliotfontaine/yard-godot/blob/613ebfb67f71288e64b901cd47446552450e5d7a/addons/yard/registry.gd)。节点式运行并非天然不可适配，显式tick/引擎无关核心也是实际优点；本项目还要恢复全场接触顺序、唯一状态与候选World，因此当前判断是**不先整包替换执行器**，而非宣布这些插件不能制作ACT。

### 4.2 原生技术的实际边界与小试

| 原生能力与官方依据 | 可用于制作的部分 | 仍需项目实现的部分 |
|---|---|---|
| [Resource](https://docs.godotengine.org/en/4.7/tutorials/scripting/resources.html)、[导出属性](https://docs.godotengine.org/en/4.7/tutorials/scripting/gdscript/gdscript_exports.html) | 自定义类型、分组/枚举/范围、类型化效果数组、嵌套资源、`.tres`保存；已有基础属性编辑UI | 技能阶段、目标资格、CD/成本、叠层规则、组合执行和跨字段校验。共享资源不替每次施放保管CD/命中表；`resource_local_to_scene`也不替无场景的World自动创建实例 |
| [Inspector扩展](https://docs.godotengine.org/en/4.7/tutorials/plugins/editor/inspector_plugins.html)、[编辑器插件](https://docs.godotengine.org/en/4.7/tutorials/plugins/editor/making_plugins.html)、[@tool](https://docs.godotengine.org/en/4.7/tutorials/plugins/running_code_in_the_editor.html) | 可在Godot内增加错误定位、阶段条、范围预览与试玩入口 | 控件、撤销/重做与预览接线仍要写；不承诺几十行即得到可靠完整编辑器。真实命中试玩继续用现有World |
| [Curve](https://docs.godotengine.org/en/4.7/classes/class_curve.html)、AnimationPlayer/AnimationTree、PackedScene | 曲线编辑、动画、音效/粒子预制体与表现同步 | 曲线在装载边界转为数值采样；动画/场景用于表现，不回调另扣HP。它们不是本项目的规则时钟，这是Reol架构取舍 |
| [GraphEdit](https://docs.godotengine.org/en/4.7/classes/class_graphedit.html) | 原生画布、节点、连线操作信号 | 图的语义、校验、保存、编译与执行器均需实现。先证明阶段/效果列表不足，再为真实分支需要加图 |

[官方线程说明](https://docs.godotengine.org/en/4.7/tutorials/performance/thread_safe_apis.html)允许跨线程持有资源引用，但不支持多线程修改同一资源；活动场景树也非线程安全。**Resource→脱离纯值快照是Reol的隔离选择，不是Godot禁止一切跨线程资源读取。** 只冻结顶层Dictionary不能自动保护所有嵌套数组/字典；定义快照必须脱离编辑对象，嵌套可变容器也要受保护。

本机隔离试验使用Godot4.7.2，原件在`.local/advisor/combat-authoring-20261115/native-probe/`。一份`.tres`含两个类型化效果子资源，五项导出字段可由编辑属性元数据识别；定义保存/重载、路径缓存共享、转换后的嵌套值隔离、两个施放状态隔离及纯值二进制往返均通过。**没有用这个小试冒充完整Inspector操作、线程集成、Reol战斗存读或YARD兼容验证。** 源码/许可快照与元数据在同题`sources/`，不纳入产品依赖。

## 5. 采用理由与边界

- 近远双路线由项目目标确定。DNF的横版轴向、幸存者的自动输出、Hades的房间流程各有不同用途，不能合并成一套未经验证的现成规则。
- 阶段、缓冲、取消、真实几何和预警共同决定手感，不能只以技能数或FPS代替试玩；正式命中停顿另需明确共同时间语义。
- 原生Resource/Inspector用于制作，定义编译为只读值；运行实例由World各owner持有，Godot节点式技能插件没有直接替换当前模拟。
- 多成本、交易/配方保必要原子性；普通载荷不扩为任意跨域事务。复杂编排由受信脚本依附现有宿主，不造通用蓝图语言。
- 索敌依本人认识，物理接触与界面知情分开；不为延迟补偿添加隐藏避伤或随意漏判。
- 来源/激活/共同时间/实际结果/恢复是共享合同，不要求全部行动合表，也不要求每个特例新建通用类。

原始顾问回答、附件与实验保存在忽略的`.local/advisor/`；采用项已经落实到当前合同，静态意见不当作运行或主观手感证据。各阶段咨询次数、已修反例和旧施工顺序不继续维护为任务。

### P4公开机制与源码研究

本节记录战斗机制基座的研究。技能/工具/交互共用能力层的War3/SC2、环世界、PoE与暗黑证据归[成熟能力架构研究](action_editor_references.md)；公共合同归[行动与作用框架](../systems/action_effect_framework.md)，本节的伤害、状态和交付研究作为其战斗应用继续使用。施工以主计划P4为准。

2026-11-15从P3提交`d7f7459`检查机制接缝。P3已有原生定义/值编译/签名、动作相位、弹/区/减速/DoT与独立飞剑；缺口集中在载荷仍绑定动作名、单交付、效果种类有限，以及没有独立属性聚合、战斗池、结算结果/触发合同和召唤身体能力。结论是扩现有框架的组合能力，不是全部推倒重写。

用户列出的五款游戏提供丰富的公开玩法与技术资料。本轮没有取得可直接嵌入Godot的这五款商业游戏官方战斗内核；实际核查分为**官方规则/静态数据、社区引擎源码、构筑工具源码**。社区实现不冒充原厂内部架构，技能JSON不等于权威执行逻辑。

| 参考与本轮直接核查材料 | 能支持的取舍 | 适用边界 |
|---|---|---|
| GGG官方[Heist技能改版说明](https://www.pathofexile.com/forum/view-thread/2934377)，2020 | 文中明确分裂与其他弹行为有先后，持续风暴有并存上限；支持显式行为顺序和生产数量规则 | 历史版本设计，不把当年优先级/数值写成所有现行技能的通则，也不推测内部源码 |
| GGG官方[Game Mechanics Q&A Part2](https://www.pathofexile.com/forum/view-thread/3130696/filter-account-type/staff)，2021 | 分开每次命中的格挡、部分技能每次施放的随机范围；动画速度和独立激活频率不天然同步 | 支持明确采样/随机/频率作用域，不能直接照抄整套PoE触发和吸血规则 |
| WoW官方[德鲁伊职业页](https://worldofwarcraft.blizzard.com/en-us/game/classes/druid) | 官方列健康、法力、怒、能量等不同资源；同一资源接口可服务不同玩法 | 只说明玩法存在，不证明官方服务器的池存储结构；Reol不要求所有角色同时拥有这些条 |
| Riot官方[Data Dragon说明](https://developer.riotgames.com/docs/lol#data-dragon)与固定版本[Anivia 14.24.1 JSON](https://ddragon.leagueoflegends.com/cdn/14.24.1/data/en_US/champion/Anivia.json) | 实际读取飞球沿途伤害/减速、爆炸眩晕、状态条件增伤与持续冰暴的组合描述；可参考数据与显示文案分离 | Data Dragon明确是静态数据与素材，没有暴露服务器的碰撞/触发执行器；示例使用固定旧版本 |
| Riot工程[Unified Clock](https://www.riotgames.com/en/news/determinism-league-legends-unified-clock)，2017 | 统一游戏时钟、时间表示与暂停语义能减少分叉与转换错误 | 历史工程经验，不照搬其模拟频率/联网时钟，也不宣称Reol具备Chronobreak |
| Blizzard经典[Archmage资料](https://classic.battle.net/war3/human/units/archmage.shtml) | 同一英雄包含持续范围伤害、可驱散召唤物、回蓝光环和传送；说明这些应作为可复用能力组合 | 官方玩法资料，不是War3引擎源码；不采用马甲单位代放法术的旧引擎技巧 |
| 腾讯官方[王昭君技能页](https://pvp.qq.com/web201605/herodetail/152.shtml) | 实读护盾受伤附冰冷、破盾爆炸、第三次普攻变化、持续暴风雪及刷新护盾；支持按事件原因组合效果 | 只借组合结构，不搬版本数值；护盾/霸体/吸血等跨游戏规则不视为通用真理 |
| [TrinityCore `Unit.h`](https://github.com/TrinityCore/TrinityCore/blob/bc47ca8fe5b4a8f20272bbc0847217653cc95dc9/src/server/game/Entities/Unit/Unit.h#L443)、[Aura处理器](https://github.com/TrinityCore/TrinityCore/blob/bc47ca8fe5b4a8f20272bbc0847217653cc95dc9/src/server/game/Spells/Auras/SpellAuraEffects.cpp#L51)、[TemporarySummon](https://github.com/TrinityCore/TrinityCore/blob/bc47ca8fe5b4a8f20272bbc0847217653cc95dc9/src/server/game/Entities/Creature/TemporarySummon.cpp#L29) | `DamageInfo/HealInfo/ProcEventInfo`区分吸收、抵抗、格挡与有效治疗；有限效果handler；召唤归属/寿命/消散分开 | 社区WoW实现，非Blizzard源码；3.3.5分支快照`bc47ca8`，文件头与[COPYING](https://github.com/TrinityCore/TrinityCore/blob/bc47ca8fe5b4a8f20272bbc0847217653cc95dc9/COPYING)为GPL-2.0-or-later。本轮只研究结构，没有移植代码 |
| PoB Community [`ModDB.lua`](https://github.com/PathOfBuildingCommunity/PathOfBuilding/blob/6d1d39837b0d5b0f4a3ede05d06b7594bdbcc556/src/Classes/ModDB.lua#L136)、[`CalcTools.lua`](https://github.com/PathOfBuildingCommunity/PathOfBuilding/blob/6d1d39837b0d5b0f4a3ede05d06b7594bdbcc556/src/Modules/CalcTools.lua#L15) | 实读按名称/类型/标签/来源筛选的求和与乘算，支持从源修饰集合重建属性，避免增删次序污染 | 构筑计算器，不负责连续空间/实时ACT；dev快照`6d1d398`，[LICENSE.md](https://github.com/PathOfBuildingCommunity/PathOfBuilding/blob/6d1d39837b0d5b0f4a3ede05d06b7594bdbcc556/LICENSE.md)主体MIT，另列依赖条款；本轮未复制实现 |
| Warsmash [`humanUnitActives.json`](https://github.com/Retera/WarsmashModEngine/blob/f9e0aeed4be372d6016519d0e97b384aa873f374/core/assets/abilityBehaviors/humanUnitActives.json#L17)、`CUnit.java/CUnitAttack.java`与README | 实读阶段动作数组、类型化条件、非叠加属性buff；支持有限原语＋数据拓扑，并提醒不要把资源扩成冗长脚本语言 | 社区War3引擎；main快照`f9e0aee`，当前[LICENSE](https://github.com/Retera/WarsmashModEngine/blob/f9e0aeed4be372d6016519d0e97b384aa873f374/LICENSE)为AGPL-3.0，README明确撤回旧MIT说明；本轮不引入Java运行时/原作资源 |
| Epic官方[GAS属性与效果](https://dev.epicgames.com/documentation/en-us/unreal-engine/gameplay-attributes-and-gameplay-effects-for-the-gameplay-ability-system-in-unreal-engine?application_version=5.2) | 属性、效果定义/实例、持续/周期、标签要求、叠层与表现分离可借鉴；数据不能表达时有明确代码扩展口 | 使用5.2文档作概念参考；不搬ASC对象树、UObject、预测/复制模型，不替换Reol的World/存档 |
| Godot 4.7原生[类型化Resource导出](https://github.com/godotengine/godot-docs/blob/4.7/tutorials/scripting/gdscript/gdscript_exports.rst)、[Inspector插件](https://github.com/godotengine/godot-docs/blob/4.7/tutorials/plugins/editor/inspector_plugins.rst)、[GraphEdit](https://github.com/godotengine/godot-docs/blob/4.7/classes/class_graphedit.rst) | 原生资源数组与Inspector足以继续制作类型化定义；GraphEdit是图界面，连接请求本身不执行战斗逻辑 | Context7核对4.7文档。P4延续原生制作，图编辑后置；Godot本身不禁止资源跨线程，值编译是本项目选择 |

源码通过`git ls-remote`取得分支SHA，再按该SHA下载选定文件并记录哈希；未克隆编译这些引擎。GitHub API首次采集因限流失败，随后原始文件路径成功取回；不存在“API失败仍当读过源码”的情况。官方腾讯/Blizzard页有工具抓取限制，使用直接HTTP实际取回HTML/JSON核对。原件与URL/哈希清单留`.local/advisor/p4-combat-foundation-20261115/sources/`，不入库、不新增依赖。

插件选型沿用4.1的已核查结果：此次没有重装或重测Godot战斗插件。决定继续原生Resource＋World的原因是已有运行资产及当前接入成本；不是声称所有插件都不可适配。现成框架可提供聚合/状态/标签的设计参考，未来若确有制作瓶颈再局部评估，不为了通用名义引入第二份HP、生命周期或节点时钟。

## 6. 当前证据边界

P4机制、跨域样例、两套组合与导出已经完成。工程/GUI与恢复证据归[BASELINE](../../docs/status/baseline.md)；完整敌人花型、长局、目标低配机、密弹容量与主观手感仍需对应内容和试玩，按新需求选题，不作为未完成P0～P4清单。

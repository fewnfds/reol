# 项目技能覆盖审查

2026-11-18。本页是对一次删并的逐项审查及当前去向，不是每个开发任务的新检查模板。维护规则归[setup](setup.md#skills怎样维护)，默认开发方法归[testing](../workflow/testing.md)。

## 结论与证据边界

上一轮`0f7e15f`把项目入口从36减到3，确实删过头了。访问规模/owner/验证总则不能等效替代UI输入、Resource隔离、存档故障、音频、GPU和发布等领域约束。“内容通用”“没有运行时代码调用方”“模型应该知道”均不是单独删除依据。另一方面，原跨引擎样例、节点式人物/弹体模板及品类玩法预设不宜原样恢复。

本轮回看删除前`4b14da8`的33份SKILL及关联Markdown全文，重新评估关联工具。原33项涉及75个文件；其中30项来自导入的第三方入口，3项是项目自有指导。代码围栏不整段迁回，工具检查关键解析/UID/场景逻辑并运行CLI反例；这不代表逐个验证所有跨引擎样例。原始文件可在该Git快照逐项追溯，不将教材全文重复归档进仓库。

当前保留原3入口，恢复/重组15个，合计18个。数量没有目标或上限：分开定义隔离、工作事务、个人决策、主体数值和存档，是因为它们有不同的设计/失败/验证问题；不将所有问题隐藏到一个“模拟核心”reference中。普通数据实例、改字与小布局不因目录中有这些入口就全读。长期有益的竞争、取消、恢复与真实呈现检查保留。

以下“删后覆盖”以删除后版本为基准：**部分**表示代码/规则已有机制，但缺少显式跨任务检查；不表示该机制从未实现或当前代码一定有缺陷。新增skill是开发指导，不是新增游戏系统。

## 当前覆盖的核对位置

- 作者定义：`scripts/sim/definitions/combat/ability_def.gd`的`values/errors`、`combat/library.gd`的`compile`以及[定义目录](../../../data/README.md)。已有定义/实例分离，不依赖每单位复制Resource；缺的是后续扩展时共享与复制的检查。
- 前端：`scripts/presentation/ui/interaction.gd`、`input_bindings.gd`、`input_settings.gd`及`subject_view.gd`；已有输入代次、改键、面板白名单，`input_settings._exit_tree`也解除订阅，不能把顾问的风险清单直接当作现有bug。
- 运动/AI/工作：`scripts/sim/kernel/{motion,navigation,agency_selection,agency_planner,decisions,production,facilities,stock_rules}.gd`；现有Packed身体、私有寻路lane、个人候选与原host。已有分层不等于所有算法/事务约束都能从短架构skill中自然发现。
- 数值：`scripts/sim/kernel/equipment.gd`从源值重建热列，增上限不赠血，恢复/槽位接线已有实现；补的是新增修饰来源、堆叠与可逆校核。
- 恢复：`scripts/sim/kernel/session_io.gd`已有脱离I/O、临时/备份文件、禁对象Variant和候选采用；[兼容政策](../compatibility.md)已有格式边界。不能说此前“没有存档保护”；仍需专门检查字段、失败窗口和新格式精度。
- 表现/音频：`scripts/presentation/view_rig.gd`、`art.gd`、`impact.gd`、`combat_audio.gd`；当前已有8个voice、事件去重和显示时间调度。并非音频尚未开始，亦不意味着已经完成混音/试听验收。
- 方法：根[AGENTS](../../../AGENTS.md)、[成本范式](../simulation-costs.md)、[开发循环](../workflow/testing.md)覆盖访问规模与证据选择；原headless具体陷阱确已完整并入[troubleshooting](../../../.agents/skills/godot-verify/references/troubleshooting.md)。

以上是作者按主题定位的源码/合同依据，不是全项目逐行审查。第二轮顾问只收到定义/库、改键、冷I/O、装备、相机和战斗音频七个完整脚本，其余位置不能算顾问独立源码验证通过。

## 删除的33项逐项处置

“替代”既包括重新编写的项目skill，也包括API/算法一手资料；外部资料不能自动替代项目约束。表内资料简称在后节链接，API版本随项目采用版本核对。

| # / 原入口 | 独有价值与删后覆盖 | 本轮处置与不再沿用的部分 | 外部补充 |
|---|---|---|---|
| 1 `ai-behavior-trees-utility-ai` | Running保留、guard复核、抢占清理、冷却不被Reset绕过、效用可比/防抖；原sim只覆盖部分执行合同 | 合并到[decision](../../../.agents/skills/godot-decision-systems/SKILL.md)，保数学/状态检查；不移植C#树类或固定轮询频率 | 状态模式；算法与项目策略分开 |
| 2 `audio-design` | 总线混音、用户音量与duck分层、并发优先级、真实试听；原3技能无覆盖，但战斗音频已存在 | 合并到[audio](../../../.agents/skills/godot-audio/SKILL.md)；不强制动态配乐、固定响度或中间件 | Godot Audio buses / sync |
| 3 `camera-systems` | dt平滑、缩放视口夹紧、换档重置、震动/拾取一致；原资产入口不足 | 合并到[presentation](../../../.agents/skills/godot-2d-presentation/SKILL.md)；不恢复3D orbit/分屏产品流程 | Godot 2D transforms / Tween |
| 4 `colony-sim-systems` | 自有工作指导：请求/意愿/执行分开、工位/库存竞争、到场复核、六类失败/恢复反例；删后sim压缩过多 | **恢复改写同名入口**[work](../../../.agents/skills/colony-sim-systems/SKILL.md)，不另造JobBoard，不强迫八阶段各建类 | 本项目原owner合同优于匿名库存教程 |
| 5 `dialogue-systems` | 选择效果一次、runner/UI/世界分离、稳定行ID、图校验、禁裸eval；原无完整覆盖 | **恢复改写同名入口**[dialogue](../../../.agents/skills/dialogue-systems/SKILL.md)，只在实际分支叙事时触发；不称当前已有此系统 | Ink/Yarn为候选资料，不安装其引擎绑定 |
| 6 `game-ai` | 决策/路径/执行分离、无路/卡住结果、启发式与代价一致；原架构有实现但领域检查不足 | 分入[decision](../../../.agents/skills/godot-decision-systems/SKILL.md)与[motion](../../../.agents/skills/godot-motion-navigation/SKILL.md)；不复制造A*或每帧全树 | Red Blob A*；Godot AStarGrid2D |
| 7 `game-feel` | 真结果驱动反馈、效果去重/回稳态、身体/视觉分离、真实试玩；原verify只提示看画面 | 合并到[presentation](../../../.agents/skills/godot-2d-presentation/SKILL.md)，声音交audio；不固定每击反馈数量，不用Engine.time_scale假装Runner顿帧 | Godot Tween；体验仍需试玩 |
| 8 `game-ui-ux` | 内容缩放、焦点/模态、可理解反馈、非纯色编码、真实窗口；架构描述不能全覆盖 | 合并到[ui-input](../../../.agents/skills/godot-ui-input/SKILL.md)；不强加手机/电视/手柄全部支持或万能页面栈 | Godot Control / Multiple resolutions |
| 9 `godot-2d-movement` | 单位/时间、输入归一、身体与显示、碰撞后真轨迹；通用CharacterBody教程不匹配 | 适用检查并入[motion](../../../.agents/skills/godot-motion-navigation/SKILL.md)；不恢复逐人Node、重力/土狼跳和第二积分时钟 | Godot插值，仅按实际运动模型应用 |
| 10 `godot-animation` | 属性单写者、Tween取消/绑定、loop完成等待与场景生命周期；原无专门入口 | 合并到[presentation](../../../.agents/skills/godot-2d-presentation/SKILL.md)；UI布局竞争归ui-input；不让动画轨道结算权威伤害 | Godot Tween / Node |
| 11 `godot-audio` | dB/零值、voice/polyphony、监听点、音频时钟、loop出口；原技能无覆盖 | **恢复改写同名入口**[audio](../../../.agents/skills/godot-audio/SKILL.md)，与audio-design合并，沿现有combat_audio；不恢复3D录音样例 | Godot Audio buses / sync |
| 12 `godot-export` | 版本匹配、非Resource过滤、res只读/user写、独立包冷启；原verify只部分覆盖 | **恢复改写同名入口**[export](../../../.agents/skills/godot-export/SKILL.md)；保当前/历史包区别，不强制多平台和加密流程 | Godot Export / CLI |
| 13 `godot-gdscript` | 类型/Variant边界、整数精度、生命周期、release断言、@tool与class_name；根成本规则不足 | **恢复改写同名入口**[gdscript](../../../.agents/skills/godot-gdscript/SKILL.md)，吸收Node/信号；不禁所有类型推断或强制所有字段@export | Godot GDScript / Signal / Node |
| 14 `godot-gdscript-headless-testing` | 错误不一定非零退出、initialize时机、异步终止、导入缓存；删后已完整合并 | 继续保[godot-verify排错](../../../.agents/skills/godot-verify/references/troubleshooting.md)，无需独立重复入口 | Godot CLI；不因此安装GUT |
| 15 `godot-nodes-scenes` | 构造/ready/owner、旧树立即移出、静态UID/大小写/内引用/连接检查；工具删错 | 文字并入[gdscript](../../../.agents/skills/godot-gdscript/SKILL.md)，**恢复1262行原检查器**；不恢复每NPC/弹体Node模板 | Godot Node / SceneTree；工具局限见下节 |
| 16 `godot-physics` | layer/mask、shape与图像、查询时机/过滤、自排除与扫掠；当前几何模拟已有边界 | 适用检查归[motion](../../../.agents/skills/godot-motion-navigation/SKILL.md)，引擎物理API按需查；不恢复Jolt3D或物理世界副本 | Godot Physics / thread-safe APIs |
| 17 `godot-resources` | Resource共享、嵌套复制、UID、加载/保存边界；现有编译机制不等于显式校核 | **恢复改写同名入口**[resources](../../../.agents/skills/godot-resources/SKILL.md)；核两类duplicate差别，不每人深拷贝目录 | Godot Resource / Dictionary / threads |
| 18 `godot-shaders` | 时钟/颜色/空间、共享材质、Godot真实编译与渲染；删后缺专门检查 | 合并到[presentation的GPU参考](../../../.agents/skills/godot-2d-presentation/references/shaders.md)；不恢复spatial/3D或旧shader API | Godot CanvasItem shader / MultiMesh |
| 19 `godot-signals-groups` | Callable身份、解绑/重复连接、捕获生命周期、await取消、同步重入/扇出；原无覆盖 | 合并到[gdscript](../../../.agents/skills/godot-gdscript/SKILL.md)；不强推Events总线或get_nodes_in_group世界查询 | Godot Signal / Node；GDQuest思想仅作对照 |
| 20 `godot-tilemap` | 坐标/TileData共享、批更新、terrain邻域、Y排序成本；当前非TileMap真值 | 适用检查放[world条件参考](../../../.agents/skills/godot-world-generation/references/tilemap.md)，仅采用/编辑时读，不迁移当前Terrain/MultiMesh | Godot TileMapLayer / TileSet |
| 21 `godot-ui-control` | Container布局、Theme共享、anchors/offsets、mouse_filter、focus；删后缺明确校核 | 合并到[ui-input](../../../.agents/skills/godot-ui-input/SKILL.md)，不将所有手动布局判错或引触屏摇杆 | Godot Control / InputEvent |
| 22 `input-systems` | action映射、按住/边沿、焦点清理、改键/布局键名；原代码已有但扩展指导缺失 | 合并到[ui-input](../../../.agents/skills/godot-ui-input/SKILL.md)；保持原输入代次与配置，不强加设备/rebind新产品表 | Godot InputEvent / InputMap |
| 23 `level-design` | 空间尺度、低成本布局、可达依赖、引导/试玩；不是生成算法能替代的领域 | **恢复改写同名入口**[level](../../../.agents/skills/level-design/SKILL.md)，用于手工开局/场景；不恢复平台跳跃/线性Boss剧本 | Red Blob图模型仅补可达性，不替代体验方法 |
| 24 `open-world-2d` | 自有指导：基底/变化分离、加载顺序、接续/历史不凭读取补造；sim摘要不足 | 合并改写到[world](../../../.agents/skills/godot-world-generation/SKILL.md)，保跨区反例；不将远区LOD候选说成现有功能 | Godot RNG / 项目接续合同 |
| 25 `performance-optimization` | CPU/GPU/等待分诊、真实构建、分配/上传/合批及同条件测量；成本总则只覆盖部分 | **恢复改写同名入口**[performance](../../../.agents/skills/performance-optimization/SKILL.md)；拒绝“未测就先大扫”，不套C# GC/通用硬预算表 | Godot optimization / Profiler / MultiMesh |
| 26 `physics-tuning` | 时间/渲染拆分、瞬移重置、连续扫掠与负载观察；原有实现但skill不足 | 合并到[motion](../../../.agents/skills/godot-motion-navigation/SKILL.md)及presentation；不为防积压静默丢弃共同世界时间或叠加Godot插值 | Godot interpolation；固定步方法要适配Runner |
| 27 `procedural-gen` | RNG/state、算法版本/顺序、噪声值域/分布、生成后校验；原world提示未充分保留 | 合并到[world](../../../.agents/skills/godot-world-generation/SKILL.md)；BSP/WFC等算法查资料，不默认上自制PRNG/保底掉落 | Godot RNG / FastNoiseLite；Red Blob noise |
| 28 `roguelike` | 可见/记忆、连通、抽样、调度公平与双缓冲思想有价值；品类预设不适配 | 空间/随机检查并入[world](../../../.agents/skills/godot-world-generation/SKILL.md)，公平归原成本/调度方法；不恢复回合制、permadeath删档或强制互见 | Red Blob图模型；需要特定FOV算法时另核 |
| 29 `rpg` | 基础/派生/来源修饰、可逆装备/状态、舍入与奖励一次；原代码有机制，skill未覆盖 | 改写为[character](../../../.agents/skills/godot-character-rules/SKILL.md)，一次结果归事务/对话；不恢复DND属性/固定等级和暴击曲线 | 原Equipment/Effects及正式玩法规则 |
| 30 `save-systems` | schema/格式边界、候选验证、真实重启、失败保活档/备份、数据安全与精度；原有保护但入口过薄 | **恢复改写同名入口**[save](../../../.agents/skills/save-systems/SKILL.md)，不强制JSON/迁移全历史，不能把rename+flush称断电原子保证 | Godot FileAccess / DirAccess / JSON |
| 31 `shader-programming` | 坐标/矩阵、图集边界、smoothstep顺序与实际GPU验证；无等效领域入口 | 合并到[presentation的GPU参考](../../../.agents/skills/godot-2d-presentation/references/shaders.md)；不恢复跨引擎3D模板或“分支一定慢”断言 | Godot shader / MultiMesh |
| 32 `spec-driven-game-dev` | 自有范围收敛、防模板膨胀、不扩权、长期取舍反证；原流程大部覆盖但有遗漏 | 并入[开发循环](../workflow/testing.md)补齐防第二主计划/临时进度与反证条款；不恢复每次先写spec的入口 | 项目文档职责与开发循环足够 |
| 33 `survival-crafting` | 原子输入/产出、最终容量包含消耗腾空、需要积分/余量、建造合法性；原sim概括不够 | 分入[work](../../../.agents/skills/colony-sim-systems/SKILL.md)、[character](../../../.agents/skills/godot-character-rules/SKILL.md)与motion；不恢复强制重生/夜袭/科技树 | 原库存、生产、设施与主体规则 |

## 恢复的检查器与验证边界

[check_godot_project.py](../../../.agents/skills/godot-gdscript/scripts/check_godot_project.py)从`4b14da8`原样恢复，1262行，无新增依赖。它补充UID冲突/孤儿、大小写、ExtResource/SubResource声明、场景父节点及connection端点；`tools/check_structure.py`另核项目职责/文档链接和普通字面量路径，二者不等价。它不完整解析GDScript/动态路径，不验证方法参数或实际打包过滤，对不透明二进制资源保守报告，不能替代Godot运行。

按需命令：`python .agents/skills/godot-gdscript/scripts/check_godot_project.py .`；工具反例检查：`python .agents/skills/godot-gdscript/scripts/test_check_godot_project.py`。不把它并入每次小改的全项目必跑流程；若以后合并检查工具，应先保留这些独有能力再删入口。

## 当前外部替代的实质比较

本次联网检索与读取截至2026-11-18。比较了以下项目的正文及许可，记录当次远端HEAD；不以星数、搜索摘要、更新日期或技能数量判断质量，也未安装新包/换MCP。第三方教程与官方资料是参考，不改变本项目规则。

| 候选 | 核对范围与状态 | 可借鉴 / 本轮选择 |
|---|---|---|
| [awesome-gamedev-agent-skills](https://github.com/gamedev-skills/awesome-gamedev-agent-skills) | Apache-2.0；原采用pin `19d93f9…`，本次HEAD `c6ca6c41c839b68319ffc08430b99ab768debc32`。完整回看本地33旧项，另比对当前README及GDScript/Resources/UI三项 | 新版Resource明确外部深复制与验证，UI增加实际检查，说明原库并非全无用；仍有跨引擎/节点模板与多入口组合要求。本轮沿已许可旧内容作项目化重写，不整包升级，未审全部79项 |
| [TheMarco/godot-game-skills](https://github.com/TheMarco/godot-game-skills/blob/06c2366a90ed6f5a286583e069c8358a351696d8/skills/godot-dev-director/SKILL.md) | MIT；HEAD `06c2366a90ed6f5a286583e069c8358a351696d8`；读director全文/许可，其定位偏程序化3D | 分清数据/现场/表现，按需专家与最小实际验证的思路可取；不比现有Reol入口更全面，也不覆盖本项目事务/认识。未复制内容、未安装其router/3D流程 |
| [fernforestgames/agent-skill-godot](https://github.com/fernforestgames/agent-skill-godot/blob/e584a973fcf0590a4cbc6697fa5daa3d11585dbe/SKILL.md) | MIT；HEAD `e584a973fcf0590a4cbc6697fa5daa3d11585dbe`；读完整SKILL/许可 | 有源文件→导入→语法→真实交互链；但要求所有Godot编辑先加载、依赖两套专属MCP/Bash检查、禁止类型推断并指定GUT/子代理，不适合当前工具/按风险验证。不采用 |
| [Fromlan UI best practices](https://github.com/Fromlan/godot-mcp-connector/blob/a5bbfb607d660540d551836339907ddb149f2485/skills/godot-ui-best-practices/SKILL.md) | MIT；HEAD `a5bbfb607d660540d551836339907ddb149f2485`；读UI全文/README/许可 | 容器、输入层级与诊断形式有参考价值，但正文把`SIZE_SHRINK_END`写成0、把PASS说成向兄弟传播；官方实际为8、向祖先传播。`@onready`也不保证路径存在。没有作为“更新更好”替代品安装 |

更合适的组合是**窄领域检查＋匹配版本一手API＋原项目owner合同**。以下是核查过的关键资料及能替代的范围；不是每轮阅读书单：

- [Godot Resource](https://docs.godotengine.org/en/4.7/classes/class_resource.html)与[Dictionary](https://docs.godotengine.org/en/4.7/classes/class_dictionary.html)：核复制模式/共享边界；不能替代本项目只读编译与实例状态归属。
- [Godot Signal](https://docs.godotengine.org/en/4.7/classes/class_signal.html)、[Node](https://docs.godotengine.org/en/4.7/classes/class_node.html)、[SceneTree](https://docs.godotengine.org/en/4.7/classes/class_scenetree.html)：核连接重复/对象释放与场景时序；C#闭包文档不能当GDScript所有捕获的普遍保证。
- [InputEvent传播](https://docs.godotengine.org/en/4.7/tutorials/inputs/inputevent.html)与[Control](https://docs.godotengine.org/en/4.7/classes/class_control.html)：准确校正mouse_filter、焦点与布局；不能自动清全局按住状态或替代Runner输入代次。
- [General optimization](https://docs.godotengine.org/en/4.7/tutorials/performance/general_optimization.html)：区分持续慢/尖峰/加载慢、CPU/GPU与测量；不代替本项目对有效产出/未准入积压的计量。
- [Red Blob A*](https://www.redblobgames.com/pathfinding/a-star/introduction.html)：分开图表示、搜索和实际移动，解释代价与启发式；不要求替换Godot寻路或忽略身体净空。
- [Red Blob noise](https://www.redblobgames.com/maps/terrain-from-noise/)：值域校正、八度归一和去相关直接适用于生成审查，不把示例地貌阈值当玩法；[Game Programming Patterns: State](https://gameprogrammingpatterns.com/state.html)的正交状态/输入消费帮助避免组合爆炸，简单枚举或布尔量足够时不强制完整类体系。后者网页工具未取到正文，已从作者仓库`munificent/game-programming-patterns`的`book/state.markdown`读取相关正文核对。
- [GDQuest signals good practices](https://www.gdquest.com/library/signals_good_practices/)：通信关系/避免多层转发值得参考，但页面标Godot3.x并有旧yield示例，不能因页面更新时间较新就拿其API套4.7，也不自动引事件总线。

音频、导出、TileMap、shader、插值等精确API在对应skill直接链接官方主题；它们是按需查阅入口，未宣称逐句实测所有API。网上没有一个已核对的包能完整替代Reol的领域事务、共同时间和个人认识合同，因此这部分保留项目自己的指导。

## 顾问意见、采用与纠偏

首轮同题送双顾问，附件包括全部33项及references、原检查器和当前架构/流程/3技能；Hydrogen完整回答已核，Argon上游503失败，没有自动重发。第二轮将实际新指导与原始代码片段送回做任务应用复核。顾问有助于发现遗漏，不能充当源码/实测证据。

采用领域覆盖不能只看性能、恢复资源检查器、保工作/持久化/前端/GPU具体检查的意见。没有采用“一律压成六个入口”：资源、运动、决策、数值与工作都藏进sim会造成描述过宽、选择不精确；验证也不兼管所有性能和发布工作。

明确纠正首答中的推断：音频已经存在；原检查器1262行而非673；删33项中30项第三方而非其估计值；Resource不必有class_name才可保存，内存修改也不自动写回磁盘。固定全局效用公式、只在末尾舍入、所有视野必须互见、强制每次改键都用物理键/每次模态用某个新API等均非项目已定规则，不加入默认规范。未独立核实的4.7新增API和第三方工具维护/测试数字不落为断言。

第二轮Hydrogen按六项请求应用18个入口并提出局部修改，已经核查回写；Argon仍为上游503失败，没有重发。采用项包括导出资源枚举的重映射与ResourceLoader/FileAccess区别、普通已有定义调参免触发、模态/文本/改键独占与有效焦点、长寿命信号的Callable管理、release monitor可用性及刷新时机、quad裁切与负坐标除法。分别对照官方[DirAccess](https://docs.godotengine.org/en/4.7/classes/class_diraccess.html)、[ResourceLoader](https://docs.godotengine.org/en/4.7/classes/class_resourceloader.html)、[Performance](https://docs.godotengine.org/en/4.7/classes/class_performance.html)等核API；不采纳全HUD一律FOCUS_NONE或无条件重写输入捕获。行为树部分保留“若采用”的条件检查，未声称当前已用BT；普通调参样例只走局部修改/相关短核，不扩到全技能和全性能矩阵。

## 本轮验证与局限

验证包括skill格式、所有本地链接、恢复检查器的正反例与当前真实项目检查、项目结构检查；没有改游戏逻辑、存档、宿主/个人skill、MCP或性能C01，也无需为说明文件重新导包。

第二轮静态应用复核及实际采用修改如上，意见已回写对应正文后再做格式/链接与工具短核；这不是独立新会话实际编码，更不能证明模型以后不犯错。长期效果应看后续任务是否在写前识别风险、是否减少返工，而非以入口数、字数或格式通过替代质量。

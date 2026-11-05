# Godot 免费资源与插件候选评估

> 核查：2026-11-02，日期采用 Asia/Singapore；具体发布时间来自上游发布页。
> 状态：资源研究，不是安装清单。**本轮未安装插件、未下载素材包、未改 `addons/`；下列新候选均未在 Reol/Godot 4.7.2 中运行验证。**
> 本文负责 Godot 插件、示例和素材；完整游戏方向见 [长期方案](../../docs/plans/product/full-game.md)，更完整的素材引入流程见 [玩法参考与素材路线](full_game_reference_map.md)。现有实际功能以 [BASELINE](../../docs/status/baseline.md) 为准。

## 1. 官方资源入口已经发生变化

| 入口 | 本轮确认的状态 | 使用方法 |
|---|---|---|
| [官方旧 Asset Library](https://godotengine.org/asset-library/asset) | [旧库文档](https://docs.godotengine.org/en/stable/community/asset_library/what_is_assetlib.html)说明其中资源免费、使用多种开源许可；不是统一 MIT | 查询老资源和原始仓库，不把搜索排名或“4.x”分类当 4.7.2 验证 |
| [官方 Asset Store](https://store.godotengine.org/) | [2026-05-22 官方公告](https://godotengine.org/article/introducing-the-godot-asset-store/)已宣布上线，称 live/stable 并集成到4.7；本轮官网首页和[当前文档](https://docs.godotengine.org/en/stable/community/asset_store/what_is_asset_store.html)仍显示 beta 提示 | 可以浏览真实条目及免费资源，不能再说“官方商店还没上线”；公告与页面成熟度表述不一致，保留这一边界 |
| 新旧库关系 | 上述公告把旧库视作 deprecated，并计划转为只读；文档说仍在线，内容不会自动迁移 | 不宣称本轮已验证旧库只读；找不到新条目时回原仓库核查，并固定实际版本 |
| 付费能力 | 5月公告把买卖列为后续事项；本轮只核查免费条目，没有测试结算 | 不把“Store”名字推导成已完整开放商业结算，不在本轮购买或登记付费账户 |
| 第三方 Marketplace/镜像 | `godotmarketplace.com`、`godotassetlibrary.com` 等名称不等于 Godot Foundation 官方 | 不从站名判断授权；回到官方域名、作者仓库和具体 LICENSE。前者页面还出现2026-10-30关闭说明，不作为长期依赖入口 |

官方商店上架是分发和审核信号，不是项目适配保证。通过 Context7 的 Godot 4.7 文档核对到：[提交要求](https://github.com/godotengine/godot-docs/blob/4.7/community/asset_store/submitting_to_asset_store.rst)要求资源在声明版本可运行且许可与仓库一致；这仍不代替我们对暂停、存档、远区批算和导出包的验收。

## 2. 推荐结论

目前不需要先安装一整套“游戏开发全家桶”。现有无头测试、数据定义、人物决策和相机都已经有实现；换成插件必须解决明确的问题，并计入迁移成本。

- **立即可用于阅读和设计比对**：官方 Demo 的相关小示例。复用前选具体项目与版本，不导入整库。
- **首次大量编写剧情时优先做隔离试验**：Dialogue Manager；已有生活/交易规则仍由模拟层执行。
- **测试框架只在现有 runner 明显不够用时二选一**：GUT 或 GdUnit4；不能为“更专业”重写现有全部测试。
- **局部 AI 的条件备选**：先比较小型自有状态机/效用判断与 Beehave；确需可视行为树/HSM和性能收益时再试 LimboAI。二者不能同时管理同一人物。
- **正式表现阶段按缺口选择**：Better Terrain、Phantom Camera、Kenney；已有可用相机与地表生成不必立即替换。
- **暂不引入主线**：Pandora 的 Alpha 数据库会与已有内容DB/存档争夺职责；Yarn GDScript 的预发布和特殊许可需要单独评估。

这是一组10项相关的可用候选，加1项应保留边界的 Yarn 对照；不表示全部都适合本项目当前阶段。

## 3. 版本、许可和维护证据

“作者声明兼容”列仅记录公开声明；没有任何一项标为“Reol 已验证兼容”。维护状况以明确发布或可见变更为证据，不按星数推断质量。

| 候选 | 本轮看到的版本/时间 | 许可证据 | 作者兼容声明与维护证据 | 推荐位置 |
|---|---|---|---|---|
| **GUT** | [v9.7.1](https://github.com/bitwes/Gut/releases/tag/v9.7.1)，2026-07-10；不是随意取main | [该版本 MIT](https://raw.githubusercontent.com/bitwes/Gut/v9.7.1/addons/gut/LICENSE.md) | [README版本表](https://raw.githubusercontent.com/bitwes/Gut/main/README.md)指定9.7.1对应Godot4.7.x；main当时仍对应4.6.x；该发布修复跨系统doubles问题 | 有测试发现/参数化/mock需求时，与GdUnit4择一 |
| **GdUnit4** | [v6.2.3](https://github.com/godot-gdunit-labs/gdUnit4/releases/tag/v6.2.3)，2026-11-02 | [该版本 MIT](https://raw.githubusercontent.com/godot-gdunit-labs/gdUnit4/v6.2.3/LICENSE) | [兼容表](https://raw.githubusercontent.com/godot-gdunit-labs/gdUnit4/master/README.md)列6.2.x支持4.7/4.7.1；未逐项列4.7.2。该发布修复4.7新编辑器字体问题、日志泄漏；master已面向7.0，不能拿master代替稳定版 | 需要场景输入测试、编辑器测试浏览/报告时再试 |
| **Dialogue Manager** | [v4.2.0](https://github.com/nathanhoad/godot_dialogue_manager/releases/tag/v4.2.0)，2026-10-30 | [该版本 MIT](https://raw.githubusercontent.com/nathanhoad/godot_dialogue_manager/v4.2.0/LICENSE) | 发布标题明确for Godot4.7；[README](https://raw.githubusercontent.com/nathanhoad/godot_dialogue_manager/main/README.md)写4.6+、无状态分支编辑/运行；近期修复非.NET项目导出夹带C#文件等 | 叙事内容生产优先候选 |
| **Beehave** | [v2.9.3](https://github.com/bitbrain/beehave/releases/tag/v2.9.3)，2026-08-18 | [该版本 MIT](https://raw.githubusercontent.com/bitbrain/beehave/v2.9.3/LICENSE) | 发布说明明确Godot4.7，修复4.7.1单例冲突、加载/卸载生命周期；纯GDScript行为树路线。旧main教程与新Godot4分支不可混读 | 先做一个局部守卫/野兽行为试验，按需采用 |
| **LimboAI** | [v1.8.1](https://github.com/limbonaut/limboai/releases/tag/v1.8.1)，2026-08-20 | [该版本 MIT](https://raw.githubusercontent.com/limbonaut/limboai/v1.8.1/LICENSE.md) | [兼容表](https://raw.githubusercontent.com/limbonaut/limboai/master/README.md)区分GDExtension与引擎Module：1.8.x扩展4.6+、Module4.7；发布含4.7.2引擎构建。C++实现支持GDScript任务，不等于纯GDScript插件 | 复杂局部BT/HSM与可视调试确有收益时备选 |
| **Phantom Camera** | [v0.11.0.4](https://github.com/ramokz/phantom-camera/releases/tag/v0.11.0.4)，2026-10-28 | [该版本 MIT](https://raw.githubusercontent.com/ramokz/phantom-camera/v0.11.0.4/LICENSE) | [README](https://raw.githubusercontent.com/ramokz/phantom-camera/main/README.md)标4.4+；近期修复启用重启和单例守卫，前一补丁修复4.7.1单例注销问题 | 后期需要小队取景/镜头过渡时可选；现相机先保留 |
| **Better Terrain** | 无GitHub release；plugin.cfg版本为空。本轮远端HEAD为[`e93040e1cdd9dba0117c87f8f6b2883c83872d5d`](https://github.com/Portponky/better-terrain/commit/e93040e1cdd9dba0117c87f8f6b2883c83872d5d) | [固定提交 Unlicense](https://raw.githubusercontent.com/Portponky/better-terrain/e93040e1cdd9dba0117c87f8f6b2883c83872d5d/LICENSE.md)，不是MIT | [作者说明](https://github.com/Portponky/better-terrain)针对Godot4/TileMapLayer，多连接自动拼接。可见问题与PR，但未核最近提交日期，不能据此保证维护频率或4.7.2兼容 | 仅当原生地形拼接确有痛点再试 |
| **Pandora** | [v1.0-alpha10](https://github.com/bitbrain/pandora/releases/tag/v1.0-alpha10)，2026-07-28 | [该版本 MIT](https://raw.githubusercontent.com/bitbrain/pandora/v1.0-alpha10/LICENSE) | 发布称Godot4.7+和更早4.x，包含中文、唯一ID、数据迁移基础等修复；[README](https://raw.githubusercontent.com/bitbrain/pandora/main/README.md)仍明确Alpha、非生产就绪 | 数据编辑器研究，不替换现有权威数据/存档 |
| **Godot Demo Projects** | 不按统一插件版本；本轮远端master为[`b761b4cd5718a7118f2c95eb55f181d0a5f004f1`](https://github.com/godotengine/godot-demo-projects/commit/b761b4cd5718a7118f2c95eb55f181d0a5f004f1) | [固定提交 MIT](https://raw.githubusercontent.com/godotengine/godot-demo-projects/b761b4cd5718a7118f2c95eb55f181d0a5f004f1/LICENSE.md)；具体Demo附带内容仍逐项读版权说明 | [README](https://raw.githubusercontent.com/godotengine/godot-demo-projects/master/README.md)明确master对应下一开发版、稳定分支按同名版本；本轮未找到4.7分支，不能编造可用4.7套件。官方仍在Store分发独立Demo | 按问题阅读；运行时先核具体Demo版本 |
| **Kenney Tiny Town 等基础包** | [Tiny Town官方条目](https://kenney.nl/assets/tiny-town)；本轮未取包，未核包内版本/哈希 | 官方条目标CC0，[作者支持说明](https://kenney.nl/support)说明资产页面资源为CC0 | 素材不绑定Godot API；本轮只有网页许可核对，不能把无版本资产说成“4.7.2已通过”。不是运行库维护问题 | 玩法清楚后用于基础地形/物件样板；看风格是否合适 |
| **Yarn Spinner for Godot GDScript（对照/暂缓）** | [v3.2.0-alpha8](https://github.com/YarnSpinnerTool/YarnSpinner-Godot-GDScript/releases/tag/v3.2.0-alpha8)，2026-07-28；网页main已显示Early Access3.3，raw README缓存仍显示3.2 | [alpha8实际LICENSE.md](https://raw.githubusercontent.com/YarnSpinnerTool/YarnSpinner-Godot-GDScript/v3.2.0-alpha8/LICENSE.md)为**YSPL1.0**，不是MIT，不归入宽松开源池 | 官方已有纯GDScript版，要求4.6+；[README](https://github.com/YarnSpinnerTool/YarnSpinner-Godot-GDScript)区分免费源码与付费支持/额外表现器。alpha说明有破坏性变化、当时不建议用其发布 | 不因C#旧印象误排除，但因成熟度、许可与已有替代暂不接入 |

YSPL的限制包含竞品工具用途/再分发和AI训练等，不能把“游戏可免费商用”写成“任意用途开源”。本轮仅阅读许可，没有复制实现；若将来要把它打包进开放项目或让其他工具加工，必须针对实际版本和分发方式评审。官方C# Yarn集成是另一个项目，不适合以引入.NET为代价迁移本项目。

上述版本是**核查候选**，并未写进工程依赖；以后采用时重新核查安全/兼容信息，固定通过验证的tag/commit与下载哈希。不能把版本号表当自动更新指令。

## 4. 用途、原生替代和接入边界

| 候选 | 能替我们省的具体工作 | 已有/原生替代与最小接入要求 |
|---|---|---|
| GUT | 测试发现、断言、参数化、替身和CI报告 | 已有`tests/run_tests.gd`及headless runner。选取真实失败/异步用例比较，不迁移只为凑覆盖率；新runner失败必须退出非0，不能忽略日志中的真实解析错误 |
| GdUnit4 | 场景输入模拟、信号等待、编辑器浏览、结构化报告 | 与GUT二选一；先验证GDScript独立使用，不引入C#组件。原有纯模拟回归继续可运行，报告不可把重试后通过掩盖不稳定问题 |
| Dialogue Manager | 可编辑分支、条件、台词、本地化与对话演出 | 少量内容可用JSON/模板＋Control。对话只发Action API意图；接受/支付/授权由模拟重新校验。暂停对话不能额外冻结远处或回填虚假关系 |
| Beehave | 节点式局部行为树、复用叶节点、调试观察 | 小型状态机/现有效用判断更简单。必须手动/固定tick驱动，并定义退出/中断/预约释放；不让节点树成为离场时消失的世界AI权威 |
| LimboAI | 可视BT、HSM、黑板和调试器 | 先沿用GDScript规则。若试插件，优先隔离GDExtension路径，核Windows编辑器/导出二进制；不为装插件直接换引擎。角色的计划/身体/货物仍在sim中，由单一执行者提交 |
| Phantom Camera | 多目标构图、阻尼、镜头优先级及过渡 | 当前Camera2D＋现有平移/缩放脚本已够用。试验需覆盖暂停、滚轮缩放、越区、相机存读；不能破坏固定俯视不旋转方向 |
| Better Terrain | 道路、水岸、地表的多连接拼接和编辑工具 | TileMapLayer原生terrain连接＋现有TerrainVisuals。只改变tile选择/绘制；高度、通行、资源和存档以自身世界数据为准。自动拼接只更新脏格和邻域，不全图每tick重画 |
| Pandora | RPG定义的分类、字段、编辑器选择与查询 | 现有JSON、Resource和ReolContentDB。若评估，先用脱离主存档的小样表；必须能稳定导出/校验，不能在定义数据库中存居民实例、公账、背包或临时关系 |
| 官方Demo | TileMap、导航、GUI、输入、存读等某个引擎能力的精简用法 | 先找对应Godot4.7官方文档，按相关小例学习；教学示例不是殖民模拟框架，不能直接当性能/完整存档方案 |
| Kenney | 快速得到尺寸/版权明确的基础物件和UI样例 | 现有代码剪影/图集也是长期可用路径。CC0只解决一部分权限问题，不解决视角、国风比例、色盘和动作一致性；先小样后整包 |
| Yarn GDScript | Yarn作者工具、复杂叙事条件和本地化流程 | Dialogue Manager或小型模板更贴近当前阶段。若重评，先核具体许可、编译工具/导出、预发布格式变化和命令边界，不和另一对话运行时同时投入主线 |

插件提供某种执行/编辑工具，不能替代 Reol 的社会模型。行为树不自动拥有可信社会推理，叙事变量不自动成为公账，数据库不自动成为存档迁移方案，地形插件不自动生成持续运转的城镇。

### 4.1 补齐 UI 与音效的具体候选

以下只补资源缺口，不另建一套美术制度；许可原文、来源/哈希记录、试样→整族制作和发布署名仍由[素材路线](full_game_reference_map.md)负责。

| 具体免费包 | 官方页面已核实的信息 | 对应玩法与采用门槛 |
|---|---|---|
| [Kenney UI Pack](https://kenney.nl/assets/ui-pack) | 页面列2.0重制版、430个文件、CC0；本轮成功读官方正文，未下载包 | 面板、按钮、滑条的候选；先做一张1280×720实际界面试样，文字仍用Control和字体，不把图包当交互框架。现有ReolUITheme足够时可以保留代码绘制 |
| [Kenney Interface Sounds](https://kenney.nl/assets/interface-sounds) | 官方正文列1.0/2020、100个文件、CC0；未试听/未读包 | 点击、确认、拒绝、交付提示。先选少量不刺耳的样本，避免每个tick或每一条批算事件播放；要有独立UI音量和静音 |
| [Kenney Impact Sounds](https://kenney.nl/assets/impact-sounds) | 官方索引列1.0/2019、130个文件、CC0；直接抓取受限制，未读包 | 建造、工具敲击、物体落地/击中等基础foley；不能保证其中每个声音都适合剑术/法术，先试听、归一响度、做少量变化再接战斗反馈 |

三个包的“CC0”是官方条目层面的初筛，**具体包内许可、附带字体/其他内容、版本和文件哈希均待下载后复核**；不是把所有附带文件自动认定为CC0。没有在本轮把候选写进第三方已使用清单，也没有采购All-in-1合集。

### 4.2 先用内置能力，对照官方来源

| 实际需求 | Godot4.7官方入口 | Reol取舍 |
|---|---|---|
| 经营/RPG复杂面板 | [Container布局](https://docs.godotengine.org/en/4.7/tutorials/ui/gui_containers.html) | 内置VBox/HBox/Grid/Scroll/Tab等已经覆盖多数面板需求；先解决布局和信息层级，再加UI素材 |
| SFX/UI/环境/音乐分组 | [Audio buses](https://docs.godotengine.org/en/4.7/tutorials/audio/audio_buses.html) | 内置AudioStreamPlayer和总线路由先搭最小混音；没有必要先接第三方音频中间件 |
| 地表图集/碰撞/遮挡/导航 | [Using TileSets](https://docs.godotengine.org/en/4.7/tutorials/2d/using_tilesets.html) | 原生TileMapLayer/TileSet是首选；场景tile逐个实例化有额外开销，不能用场景tile铺满大世界 |
| 平移/缩放/跟随/限界 | [Camera2D](https://docs.godotengine.org/en/4.7/classes/class_camera2d.html) | 现相机基于内置能力；多目标取景确有需要时才评估Phantom，不为装插件重写基本相机 |
| 学习具体能力的小项目 | [Godot官方Demo仓库](https://github.com/godotengine/godot-demo-projects)、[官方Store发布者](https://store.godotengine.org/publisher/godot-foundation/) | 每个含project.godot的目录是独立例子。选相应2D/GUI/导航/存读例子，固定该例子的版本与来源；不把整套Demo或master视为已适配本项目的组件 |

## 5. 真正采用前的最小验证

未来工作包发现明确缺口后，才进行以下试验；本轮没有执行安装：

1. **单独样例**：固定Godot4.7.2、候选版本/commit、许可证和依赖；先检查是否需要.NET、原生二进制、额外工具或联网。
2. **验证它比现有方案多解决了什么**：测试框架用真实失败/场景等待；对话用真实办事请求；AI用工作中断/离场；terrain用实际脏格边界；相机用实际小队和旅行。
3. **验证生命周期和打包**：编辑器启用/关闭、重新打开、headless导入、项目测试、Windows导出；原生扩展核目标架构、动态库和导出模板。
4. **验证游戏契约**：暂停与倍速、取消/死亡、预约释放、存读、远近切换、无变化请求不重掷；插件不能绕过现有事实归属。
5. **决定留用或退回**：记录新增配置/场景/自动加载、维护和升级成本；没有足够收益就不引入。保留原生替代和可读错误，而不是把错误隐藏在插件里。

新依赖是否安装仍按项目`AGENTS.md`及当时用户授权执行；说明用途、版本、许可、维护、替代和试验结果。候选评估本身不新增全局配置、不修改已有MCP、不自动升级引擎和插件。

## 6. 本轮核查方法与局限

- 使用官方Godot公告、官方Store/Library文档，作者GitHub README/Release/固定版本LICENSE；用Context7查询Godot4.7插件分发和兼容规则。
- 对GUT、GdUnit4、Dialogue Manager、LimboAI、Pandora、Phantom Camera、Beehave读取具体版本许可和发布页时间。日期已从上游UTC换算成本地日期，不按缓存显示的“几个月前”推断。
- GitHub API因未认证限流返回403，没有用猜测填充仓库元数据。改读公开发布页、raw文本和只读`git ls-remote`；没有克隆或下载资源。
- Better Terrain没有release/版本字段，固定远端提交，维护日期未核；官方Demo的4.7分支请求404、远端分支列表也未见4.7，故不承诺已有对应分支。master是开发版例子，不能自动当作稳定4.7依赖。
- 新Store“stable”公告与“beta”页面、Yarn的main网页与raw缓存存在表述/时间差；在各条记录差异，采用时按固定实际包复查。
- Kenney直接抓取受限制，已从官方索引核CC0标记，未读包内文件；不能由此生成一份“已完成素材授权审计”。完整引入字段和署名方法沿用[素材路线](full_game_reference_map.md)。

本轮交付研究与取舍。实际兼容结果、导出成功和性能收益只能由之后的隔离试验与项目验收获得。

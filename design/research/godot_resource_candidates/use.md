# Godot 免费资源与插件候选评估：用途与接入验证

> 研究资料：记录来源与适用限制，不授予引入依赖或改变规则的权限。

> 研究与来源记录：参考与建议不自动成为游戏规则或依赖。

## 4. 用途、原生替代和接入边界

| 候选 | 能替我们省的具体工作 | 已有/原生替代与最小接入要求 |
|---|---|---|
| GUT | 测试发现、断言、参数化、替身和CI报告 | 已有`tests/run_tests.gd`及headless runner。选取真实失败/异步用例比较，不迁移只为凑覆盖率；新runner失败必须退出非0，不能忽略日志中的真实解析错误 |
| GdUnit4 | 场景输入模拟、信号等待、编辑器浏览、结构化报告 | 与GUT二选一；先验证GDScript独立使用，不引入C#组件。原有纯模拟回归继续可运行，报告不可把重试后通过掩盖不稳定问题 |
| Dialogue Manager | 可编辑分支、条件、台词、本地化与对话演出 | 少量内容可用JSON/模板＋Control。对话只发Action API意图；接受/支付/授权由模拟重新校验。暂停对话不能额外冻结远处或回填虚假关系 |
| Beehave | 局部 Behavior Tree、复用叶节点、调试观察 | 小型 State Machine/现有效用判断更简单。必须手动/固定tick驱动，并定义退出/中断/预约释放；不让节点树成为离场时消失的世界AI权威 |
| LimboAI | 可视 Behavior Tree、HSM、Blackboard 和调试器 | 先沿用GDScript规则。若试插件，优先隔离GDExtension路径，核Windows编辑器/导出二进制；不为装插件直接换引擎。角色的计划/身体/货物仍在sim中，由单一执行者提交 |
| Phantom Camera | 多目标构图、阻尼、镜头优先级及过渡 | 当前Camera2D＋现有平移/缩放脚本已够用。试验需覆盖暂停、滚轮缩放、越区、相机存读；不能破坏固定俯视不旋转方向 |
| Better Terrain | 道路、水岸、地表的多连接拼接和编辑工具 | TileMapLayer原生terrain连接＋现有TerrainVisuals。只改变tile选择/绘制；高度、通行、资源和存档以自身世界数据为准。自动拼接只更新脏格和邻域，不全图每tick重画 |
| Pandora | RPG定义的分类、字段、编辑器选择与查询 | 现有JSON、Resource和ReolContentDB。若评估，先用脱离主存档的小样表；必须能稳定导出/校验，不能在定义数据库中存居民实例、公账、背包或临时关系 |
| 官方Demo | TileMap、导航、GUI、输入、存读等某个引擎能力的精简用法 | 先找对应Godot4.7官方文档，按相关小例学习；教学示例不是殖民模拟框架，不能直接当性能/完整存档方案 |
| Kenney | 快速得到尺寸/版权明确的基础物件和UI样例 | 现有代码剪影/图集也是长期可用路径。CC0只解决一部分权限问题，不解决视角、国风比例、色盘和动作一致性；先小样后整包 |
| Yarn GDScript | Yarn作者工具、复杂叙事条件和本地化流程 | Dialogue Manager或小型模板更贴近当前阶段。若重评，先核具体许可、编译工具/导出、预发布格式变化和命令边界，不和另一对话运行时同时投入主线 |

插件提供某种执行/编辑工具，不能替代 Reol 的社会模型。Behavior Tree 不自动拥有可信社会推理，叙事变量不自动成为公账，数据库不自动成为存档迁移方案，地形插件不自动生成持续运转的城镇。

### 4.1 补齐 UI 与音效的具体候选

以下只补资源缺口，不另建一套美术制度；许可原文、来源/哈希记录、试样→整族制作和发布署名仍由[素材路线](../full_game_reference_map.md)负责。

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
5. **决定留用或退回**：记录新增配置/Scene/Autoload、维护和升级成本；没有足够收益就不引入。保留原生替代和可读错误，而不是把错误隐藏在插件里。

新依赖是否安装仍按项目`AGENTS.md`及当时用户授权执行；说明用途、版本、许可、维护、替代和试验结果。候选评估本身不新增全局配置、不修改已有MCP、不自动升级引擎和插件。

## 6. 本轮核查方法与局限

- 使用官方Godot公告、官方Store/Library文档，作者GitHub README/Release/固定版本LICENSE；用Context7查询Godot4.7插件分发和兼容规则。
- 对GUT、GdUnit4、Dialogue Manager、LimboAI、Pandora、Phantom Camera、Beehave读取具体版本许可和发布页时间。日期已从上游UTC换算成本地日期，不按缓存显示的“几个月前”推断。
- GitHub API因未认证限流返回403，没有用猜测填充仓库元数据。改读公开发布页、raw文本和只读`git ls-remote`；没有克隆或下载资源。
- Better Terrain没有release/版本字段，固定远端提交，维护日期未核；官方Demo的4.7分支请求404、远端分支列表也未见4.7，故不承诺已有对应分支。master是开发版例子，不能自动当作稳定4.7依赖。
- 新Store“stable”公告与“beta”页面、Yarn的main网页与raw缓存存在表述/时间差；在各条记录差异，采用时按固定实际包复查。
- Kenney直接抓取受限制，已从官方索引核CC0标记，未读包内文件；不能由此生成一份“已完成素材授权审计”。完整引入字段和署名方法沿用[素材路线](../full_game_reference_map.md)。

本轮交付研究与取舍。实际兼容结果、导出成功和性能收益只能由之后的隔离试验与项目验收获得。

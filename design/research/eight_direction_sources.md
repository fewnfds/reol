# 真八方向动画与纸娃娃来源核对

调研：2026-11-03。用于[八方向外观方案](../../docs/specs/presentation/eight-directions.md)，**未安装插件、未下载资源包、未验证第三方插件在本项目运行**。互联网条目可以提供方向与许可线索，不能替代包内实际文件审查。只列与本需求直接有关的来源。

## 核对结果

| 来源 | 核对到的版本/维护线索 | 许可/商用条件 | 能用在哪里与限制 |
|---|---|---|---|
| [Godot4.7 `AnimationNodeBlendSpace2D`](https://docs.godotengine.org/en/4.7/classes/class_animationnodeblendspace2d.html)与[`AnimatedSprite2D`](https://docs.godotengine.org/en/4.7/classes/class_animatedsprite2d.html) | 官方4.7文档；已用Context7的4.7分支交叉核对 | Godot内置能力，无需新运行依赖；引擎MIT，具体素材许可另算 | 可选方向、保留播放相位、统一取帧；不自动生成缺失透视或不对称装备素材 |
| [Godot官方2D骨骼](https://docs.godotengine.org/en/4.7/tutorials/animation/2d_skeletons.html) | 官方页面仍标注教程未完全更新到4.7；Skeleton2D/Bone2D为原生能力 | 内置，不需付费骨骼运行库 | 适合裙摆/手臂等平面变形；单张正面剪纸不能自动变成侧面/背面，仍需各朝向造型与遮挡 |
| [FLARE动画分层属性](https://github.com/flareteam/flare-engine/wiki/Attribute-Reference#statblock-render-layers)、[官方发布](https://flarerpg.org/2026/05/03/flare-1-15/) | 官方最新下载页列1.15；2026年5月发布，属性文档2026-10-19编辑；该版本更新Blender/EEVEE美术流程 | 引擎源码GPL3或后续；游戏素材按各文件/署名，主要CC-BY-SA3.0或后续；免费不等于无需署名或公开衍生美术 | 最贴近本需求的成熟结构参考：每个方向定义槽位层序。借鉴合同思想，自写GDScript；不将整个C++引擎或GPL代码搬入项目，不把其斜视美术当本项目已适配 |
| [Blender Spritesheet Import Plugin](https://godotengine.org/asset-library/asset/2559)、[源码](https://github.com/oddmode-studio/BlenderSpriteSheetImporter) | AssetLib列0.0.1、Godot4.2、2024-01-31；源码首页仅2提交、未列正式release；未找到4.7验证承诺 | AssetLib声明MIT；模型、动作、示例所用外部资源须另核许可 | 提供Blender8方向导出与SpriteFrames导入的参考流程。只是导出器，不是完整多部件纸娃娃/遮挡系统；维护与4.7兼容需小样复验，不直接装入项目 |
| [Quaternius Universal Animation Library官方商店](https://store.godotengine.org/asset/quaternius/universal-animation-library/)、[作者页](https://quaternius.com/packs/universalanimationlibrary.html) | 商店Standard-1.0，列2026-06-10更新；当时条目标注版本unstable；作者页区分免费/Source等档位 | 官方标CC0，可商用；免费Standard只含部分内容，不能把宣传120+全部视为免费已取得，源工程/完整Godot项目也不是免费档保证 | 3D人形动作候选，可离线重定向后按固定镜头烘焙。其“8方向移动”是3D动作类别，不等于已经给出八朝向2D衣饰图层；运行仍2D，须验证免费档具体动作与骨架适配 |
| [Universal LPC生成器源码/署名说明](https://github.com/LiberatedPixelCup/Universal-LPC-Spritesheet-Character-Generator#licensing-and-attribution-credits)、[在线工具](https://liberatedpixelcup.github.io/Universal-LPC-Spritesheet-Character-Generator/) | 社区维护，仓库当时有大量提交及测试；无本次可直接固定的统一资产版本，正式采用应锁commit与具体条目 | 工具代码GPL3；素材按件为CC0、CC-BY、CC-BY-SA、OGA-BY、GPL等，支持导出作者/许可清单，不能只看工具总许可证 | 适合研究换装分层、帧表、颜色与出处管理。标准人形素材是上/左/下/右四方向，不能声称满足真八方向；新增斜向、特殊体型和所有动作仍需生产 |

## 直接影响方案的证据

FLARE官方属性文档把`render_layers.layer`写成“方向＋槽位次序”，并允许`animation_slots.slot`绑定各槽位动画文件。这证明成熟2D换装游戏已把朝向与遮挡层序分离；本项目还要处理同一动作中层序变化和局部前后穿越，不能只复制一张固定槽位表。[原文](https://github.com/flareteam/flare-engine/wiki/Attribute-Reference#statblock-render-layers)

Godot4.7的`DISCRETE_CARRY`在切换最近方向动画时沿用旧播放位置；同页将旧`sync`标为弃用，并提供`sync_mode`。逐帧图集使用离散选择，骨骼/变换才酌情插值；不把身体两张透视贴图做线性混合当成转身。[官方API](https://docs.godotengine.org/en/4.7/classes/class_animationnodeblendspace2d.html)

`AnimatedSprite2D.animation`改变会重置帧与帧内进度，`set_frame_and_progress`可保留它们。多图层仍必须由同一相位驱动，单靠每个节点都调用play不能构成可存读的一致采样器。[官方API](https://docs.godotengine.org/en/4.7/classes/class_animatedsprite2d.html)

LPC官方仓库说明素材许可按件记录在`CREDITS.csv`，并非生成图片一律采用工具的GPL许可证；商用仍须履行选中素材的具体条款。标准方向限制也与基于LPC的Godot生成器作者提供的格式说明一致，行序为上、左、下、右。[官方仓库许可](https://github.com/LiberatedPixelCup/Universal-LPC-Spritesheet-Character-Generator#licensing-and-attribution-credits)、[RapidLPC作者格式说明](https://joeyhome.com/building-rapidlpc-a-godot-powered-character-creator-for-the-liberated-pixel-cup/)

## 没有选为项目依赖的方案

- 八方向移动控制器只解决输入/速度，不能自动生成八方向动画，更不解决左手剑、右腰挂件与遮挡。不为“支持8方向移动”的名称替换已有连续身体/共同时间。
- Aseprite/序列帧导入器主要解决切片和数据导入；没有斜向素材时不会产生合格斜向。先选内容合同，再决定是否需要工具。
- 一些商店免费角色只有整套成品动画，能作视觉对照却不能直接拆成统一衣着家族；本轮没有把未检查包内许可证的单体角色列为可发行素材。
- Spine、DragonBones等路线不因出现在Godot教程就自动成为已批准、免费且4.7兼容的依赖。本项目当前用原生2D与可替换图集即可先验证。
- 3D离线烘焙能减少重复动画工作，但外观建模、骨骼绑定、分层/遮罩导出和授权仍需处理；不能声称一个导出插件完成整套游戏角色美术。

## 采用前的具体复验

第三方候选先记录准确版本或commit、包内LICENSE/署名和资产来源，再用一名左手持剑/右腰佩玉角色导出八方向关键帧。用原生2D加载，核对脚点、层序、透明边、相位和暂停/倍速；测纹理驻留与实际draw calls。只有存在明确收益、维护与兼容检查通过，才提出具体依赖安装；当前没有此安装请求或已安装状态。

本轮GitHub API因共享未登录额度返回403，部分网页/目录抓取受限；维护判断只使用上述已读取页面的版本与提交线索，不声称审过全部commit或下载包。Blender扩展站单条页面抓取也未成功，未将其列为已核实推荐。

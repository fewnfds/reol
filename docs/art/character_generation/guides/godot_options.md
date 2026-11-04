# Godot与免费八方向资源候选

历史候选调研；当前无需安装或制作正式美术，未来采用前须重新核对当时引擎版本与资源许可。当前代码像素占位和外部提示词状态见[提示词索引](../README.md)。

检查日期：2026-11-03。只做网页、一手条目与可读取源码说明核查；没有安装插件、下载资源包、购买、调用生成API或在Godot4.7.2中验证候选。本文件不代表项目已采用这些资源。

## 结论

本轮未核实到一套同时满足「免费、Godot4.7.2已验、独立八方向、模块衣饰、左右不对称、动作内遮挡与统一相位」的完整现成包。免费工具能减少导入、分层与生产工作，不能代替缺少的朝向和动作素材。

Reol继续使用原生2D运行与共同动作相位；外观素材显式提供八个方向。右腰佩玉与左手剑始终绑定解剖侧，逐方向、必要时逐动作阶段定义前后层序。3D仅作为可选离线生产工具。已有架构依据与官方API核查见[真八方向来源](../../../../design/research/eight_direction_sources.md)和[外观方案](../../../plans/eight_direction_appearance.md)。

## 运行与制作工具

版本、日期和兼容范围是作者/平台声明，不是本项目兼容测试结果。工具许可证不自动覆盖用户导入的模型、贴图、动作或AI输出。

| 候选与一手来源 | 版本、维护线索与免费范围 | 对本项目的价值与限制 |
|---|---|---|
| [Layered Sprites官方条目](https://godotengine.org/asset-library/asset/5227)、[源码](https://codeberg.org/cookie_cherith/godot-layered-sprites) | 2.0；标Godot4.6；2026-06-10；MIT、免费 | 直接相关的分层节点：叠加纹理、各层变体/颜色、动画。官方说明未证明独立八向或动作内动态层序；本轮Codeberg读取受限，未审实现，不作为完整纸娃娃替代品。 |
| [Modular Sprite Animation Factory官方条目](https://godotengine.org/asset-library/asset/2701)、[源码与用法](https://github.com/kyboon/ModularSpriteAnimationFactory) | 1.0.1；标Godot4.0；2024-04-05；MIT、免费；仓库首页14次提交，未列正式release | 为多个Sprite2D生成AnimationPlayer轨道，支持替换纹理/调色。需要先准备分件图集；不会生成缺方向素材，未声明Reol所需的八向遮挡合同。可借鉴编辑器批量建轨。 |
| [Composite Spritesheet Generator官方条目](https://godotengine.org/asset-library/asset/5176)、[源码](https://github.com/Shaihuludus/composite_spritesheet_generator) | 0.9.1；标Godot4.6；2026-05-22；Apache-2.0、免费；仓库首页12次提交 | 用层级和偏移合成整张PNG，适合已对齐图层的预览或固定装束烘焙。合并后失去独立换装；固定整张图层序也不会自动解决挥剑时的前后穿越。 |
| [Blender Spritesheet Import Plugin官方条目](https://godotengine.org/asset-library/asset/2559)、[源码](https://github.com/oddmode-studio/BlenderSpriteSheetImporter) | 0.0.1；标Godot4.2；2024-01-31；官方标MIT、免费；仓库首页2次提交 | 明确提供Blender八向图集生成与Godot SpriteFrames导入。可作离线管线参考；没有完整模块服装、遮挡和同步系统的保证，4.7.2兼容与外部模型许可待验。 |
| [Scalable Vector Shapes 2D官方商店](https://store.godotengine.org/asset/renevanderark/scalable-vector-shapes-2d/)、[源码](https://github.com/Teaching-myself-Godot/ez-curved-lines-2d) | 3.5.1；2026-10-30；MIT、免费；商店声明Godot4.4–4.8.x，同时标为unstable | 矢量形状、Skeleton2D绑定、曲线动画与图集烘焙。适合平面形变；单面骨骼不能自动变成八个透视，更不提供成套修仙服装。当前不为此引入运行依赖。 |
| [LPCAnimatedSprite2D官方条目](https://godotengine.org/asset-library/asset/2212) | v4.4.0.1；条目标Godot4.2；2025-03-04；插件MIT、免费；LPC素材另许可 | 自动导入LPC动画。标准LPC人形为四方向，不能用导入器补齐斜向与不对称透视；本项目不以它作为真八向素材标准。 |

## AI离线制作候选

| 候选与一手来源 | 已核信息 | 采用边界 |
|---|---|---|
| [PixelDoll源码与README](https://github.com/Shilo/PixelDoll)、[包配置](https://github.com/Shilo/PixelDoll/blob/main/app/package.json) | 代码MIT；仓库首页506次提交，本轮未锁release。提供分件图层与Godot4导出，作者报告在4.7.1核过导出呈现；本项目未复验。 | 默认Top-down 8会镜像三个西侧方向并改变持物手侧；须选Unique 8/关闭镜像。作者仍列独立八向完整生成与部分盾牌动作的质量边界，不能直接宣称满足本项目验收。 |

PixelDoll的导出免费，生成依赖自备PixelLab账户与API额度。此轮未核实PixelLab现行费用和输出条款，不把代码MIT解释为所有生成物许可，也不接入账户或API。它适合作为未来离线生产试验：先做左手剑、右腰佩玉的小样，再核身体一致性、各层帧对齐和遮挡。[作者状态与导出说明](https://github.com/Shilo/PixelDoll#status)

## 免费动作与成品素材

| 来源 | 免费范围与维护线索 | 用途和限制 |
|---|---|---|
| [Quaternius Universal Animation Library官方商店](https://store.godotengine.org/asset/quaternius/universal-animation-library/) | Standard-1.0；商店更新2026-06-10；CC0；免费档只含部分内容、无Godot工程，完整120+与源档不能视为免费已取得；条目标unstable | 3D动作参考/离线重定向烘焙候选。“八方向移动动作”不等于八朝向2D图层；仍须生产模型、衣饰、固定镜头和分层遮罩。 |
| [KayKit Character Animations作者页](https://kaylousberg.itch.io/kaykit-character-animations) | 下载列Free 1.1；页面更新2026-10-25；CC0；全部动画免费，.blend源档付费；大体型动作较少 | 包含生活、工作和战斗等3D动作，可评估离线烘焙。不是现成2D纸娃娃；对非KayKit骨架需要重定向与视觉检查。 |
| [Hormelz Free 8-Directional Melee Character作者页](https://hormelz.itch.io/8-directional-melee-character) | 2025-09-10发行、2025-09-20开发日志；CC0；作者列38动作、八个方向图集 | 可作八向动作可读性对照。是成品角色，未承诺可换衣饰图层；帧尺寸、脚点和JSON仍须检查包内文件，不直接纳入生产素材。 |

本轮也排除了名称易误导的[Modular 2D Character & Node Generator](https://godotengine.org/asset-library/asset/5250)与[Modular Character Controller](https://godotengine.org/asset-library/asset/4283)：它们主要模块化运动/控制代码，并非模块衣饰素材。[Sprite Mesh Baker](https://godotengine.org/asset-library/asset/4789)合并Sprite3D为网格，也不是把3D人物烘成八向2D纸娃娃。

## 最小采用试验

先选一套身体，保留独立八方向；仅做站立/行走、左手剑、右腰佩玉和一件上衣。候选工具只有通过下列实际试验才进入依赖提案：

1. 八向均有独立可追溯源帧；转身不换手，佩玉不跳到左腰。
2. 图层共享脚点、帧时长与相位；转身、暂停、倍速和存读不造成错帧。
3. 剑、手、躯干、佩玉在各朝向与关键动作阶段的遮挡正确；需要时把同一物件拆成前后片。
4. 在Godot4.7.2实际导入、运行，记录纹理驻留、绘制调用与多人场景耗时。
5. 固定工具版本/commit，核对包内许可证与素材来源。只采用能明显节省生产工作、且不破坏本项目外观合同的部分。

这里的选择是「原生运行器＋可替换素材生产管线」。工具有现成价值，八方向的不对称美术仍是要实际制作和验收的内容。

# 俯视高低差、局部多层与大世界拓扑研究

日期：2026-11-04。范围：第一方资料、作者公开说明及现有代码只读审查；未安装插件、未运行兼容/性能试验。用户随后决定新世界先做平面地块，高低差、多层及3D暂缓；不表示已决定长期世界形状。[高度与空间备选方案](../proposals/elevation.md)为后续研究，现行总序见[世界运行与创作工具](../../docs/specs/world-engine/program.md)，当前授权见[HANDOFF](../../docs/status/handoff.md)。

## 1. 三种经常混淆的“高度”

- 画面：2D精灵和崖壁、等距投影、3D正交相机都能表现高低。画面用3D不要求模拟三维空气，画面用2D也不排除多层逻辑。
- 地表：每个水平位置只有一个地面高度`H(x,y)`，足以表达山坡、盆地与台地。它不是保存所有`(x,y,z)`格的体素。
- 多层：同一水平坐标有桥上/桥下、洞内/山顶、多个楼层。单值高度不能表达，需额外表面/楼层及连接，或完整体积模型。

没有公开样本统计可以证明“大多数top-down建造游戏都没有高差”。可以确认它们采用不同取舍，而非引擎只能做平地。

## 2. 成熟游戏的不同取舍

| 案例与第一方来源 | 实际可确认的做法 | 对Reol的启示 |
|---|---|---|
| Factorio [FFF219](https://www.factorio.com/blog/post/fff-219)、[FFF401](https://www.factorio.com/blog/post/fff-401)、[官方Cliff说明](https://wiki.factorio.com/Cliff) | 悬崖根据生成高程/等值关系布置，运行主要是墙式障碍及视觉高差；生成高程不等于通用垂直可走空间 | 平面障碍也能塑造地形、通路和攻防。不要因看见山崖贴图便推断它有完整立体物理。 |
| Factorio [高架铁路](https://www.factorio.com/blog/post/fff-378) | 地面/高架铁路用坡道、桥墩和专门规则连接；开发文讨论地下/上层的显示、交互、通行难题 | 可按特定用途加有限层，不必令整个世界有任意楼层。 |
| RimWorld [作者2013阴影说明](https://ludeon.com/blog/2013/08/sun-shadows/) | 当时无完整Z层，但仍有屋顶、遮光等规则 | 平面模拟不妨碍屋顶/温度等作用；该旧文章只证明当时设计，不当成2026版本完整清单。 |
| OpenTTD [地形编辑](https://wiki.openttd.org/en/Manual/Landscaping)、[桥](https://wiki.openttd.org/en/Manual/Bridges)、[地形源码](https://github.com/OpenTTD/OpenTTD/blob/master/src/landscape.cpp) | 可升降/整平、坡面及桥梁跨越地面设施；成熟开源实现 | 地表高程和特殊架空连接是可行路线；桥梁需要额外状态，不能用一个H值假装上下同时可走。 |
| OpenRCT2 [界面/地下显示](https://docs.openrct2.io/en/latest/playing/main_interface/)、[高度/净空查询源码](https://github.com/OpenRCT2/OpenRCT2/blob/develop/src/openrct2/ride/RideRatings.cpp) | 二维画面中地块可包含不同基础高度/净空的离散设施 | 可以只记录实际存在的多层对象，不为所有空气建立体素；还要处理隐藏/选层。 |
| Dwarf Fortress [官方功能](https://bay12games.com/dwarves/features.html)、Going Medieval [开发商页面](https://store.steampowered.com/app/1029780/Going_Medieval/) | 前者有Z层/地下与塔楼，后者采用3D地形/多层建造 | 真实多层是成熟但更宽的产品范围，导航、结构、剖视、交互均需配套。 |
| Warcraft III [战斗](https://classic.battle.net/war3/basics/combat.shtml)、[地图设计](https://classic.battle.net/mod/dev/melee.shtml) | 3D画面的俯视策略中，高地、坡道及视野有实际战术意义 | 可借鉴可读坡路/高地，不照抄命中惩罚或推断其代码模型。 |

这些来源支持“可选不同空间模型”，不证明任何一种在Reol里的帧率。OpenTTD/OpenRCT2是原理参考，本轮不复制第三方程序或资产。

## 3. 当前Godot路线与成熟度

| 工具/项目 | 可确认功能与状态 | 适用边界/取舍 |
|---|---|---|
| [Godot官方GDScript 2.5D示例](https://github.com/godotengine/godot-demo-projects/blob/master/misc/2.5d/README.md) | 混合2D/3D节点及投影编辑视口，官方演示项目 | 可参考坐标投影；演示不等于持续世界、建造或环境求解器，不直接迁入项目。 |
| [Daicon](https://github.com/arukurei/Daicon)、[1.6](https://github.com/arukurei/Daicon/releases/tag/v1.6)、[设置文档](https://daicon-docs.readthedocs.io/en/latest/getting-started/setup/) | MIT；文档面向Godot4.5+、Forward+，2D外观背后有3D身体/碰撞和GridMap、深度排序及导航接口 | 值得另建隔离原型比较；未查得足够已发布规模案例、4.7.2兼容或Reol性能证据。不是冷热/五行环境影响或远区框架。 |
| [SmartShape2D](https://github.com/SirRamEsq/SmartShape2D) | MIT，Godot4二维贴图多边形/轮廓编辑 | 可帮助不规则崖边外观，不自动生成可走高台、桥下层或环境规则；格子架构暂不需替换。 |
| [Terrain3D](https://github.com/TokisanGames/Terrain3D) | MIT、Godot4可编辑3D高度图地形，GDExtension路线 | 假如未来选择3D场景，可减少地形表现/编辑工作；高度图本身不等于任意山洞和多楼层，也不自带社会/场模拟。 |
| [Voxel Tools](https://voxel-tools.readthedocs.io/en/latest/)、[导航说明](https://voxel-tools.readthedocs.io/en/latest/navigation/) | 立体程序生成、开挖/洞穴；官方提醒其技术要求，动态/流式地形的导航需专门处理 | 适用于真正需要可开挖体积的项目。当前不为局部台地引入模块、C++构建和体积世界范围。 |
| [TileMapLayer3D](https://github.com/DanTrz/TileMapLayer3D)、[现行许可](https://github.com/DanTrz/TileMapLayer3D_Cpp_Releases/blob/main/LICENSE.md) | 旧1.x MIT且已弃用；2.x GDExtension二进制免费，C++源码不随仓库提供 | 不能把现行版当完整MIT开源依赖；地图编辑工具不替代环境传播。非首选。 |
| [Cassette Beasts官方采访](https://godotengine.org/article/godot-showcase-cassette-beasts/) | 已发布的Godot开放世界RPG，作者讲述GDScript、自有编辑工具与性能修补 | 证明Godot可交付此类探索游戏，不证明其架构适合模拟经营。作者旧[地形技术文章](https://www.cassettebeasts.com/2021/08/09/technical-look-the-park/)搜索摘要说明固定相机/3D格地形，但直链本轮404，不用不完整摘要推断其全部实现。 |
| [Of Life and Land官方介绍](https://godotengine.org/showcase/of-life-and-land/) | Godot经营模拟，有多气候地图、人与动植物环境响应、地图与场景编辑 | 与我们的运行层/编辑/内容思路接近；页面未披露高程内部模型，不据截图推断源码。 |

现有方案已能处理不同程度的2.5D/3D表现；本轮没有找到可直接替Reol包办地形、结构、导航、空间场、远区和存档的成熟即插即用方案。不是断言世界上不存在，只说明当前证据不足以支持更换底层。

### Godot内置能力的边界

[官方TileMap文档](https://docs.godotengine.org/en/4.7/tutorials/2d/using_tilemaps.html)允许多层贴图，但同一2D导航map不能直接堆叠重叠导航网格。[CanvasItem](https://docs.godotengine.org/en/4.7/classes/class_canvasitem.html#class-canvasitem-property-y-sort-enabled)的Y排序在相同z_index内作用，z_index也不决定输入处理顺序。导航过滤层不自动成为物理楼层，调绘图顺序也不会自动解决点击选层。

Reol当前自有格路不直接受上述网格合并限制；未来仍须自管表面连接或切换独立地图，不能据此认为现有BFS已经支持桥上下。任何插件的成熟度/许可与本项目兼容、性能分别核对。

## 4. 研究时的备选建议（暂缓）

研究当时建议采用二维连续地表和单值高度，再以可读崖边、明确坡道和高度感知作用支持山丘/高台；需要同坐标上下并存时才增加局部表面/地图及显式连接。用户随后选择首轮先做平面地块，上述坡道、高度传播及多层只是未来可重审方案，不是当前前置。世界大地图画成平面、球体或多个大陆是另一层决定；大地图/切换不应冻结各地共同时间与生活。

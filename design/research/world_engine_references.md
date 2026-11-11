# 世界引擎：教程、实现与工具取舍

> 研究资料：记录来源与适用限制，不授予引入依赖或改变规则的权限。

日期：2026-11-04。第一方文档、公开源码及本地只读审计；未安装插件、未测试候选插件兼容性，不是实现验收。执行方案见[世界引擎基础](https://github.com/fewnfds/reol/blob/8c3deaa972f932e999167b61ea6b166b928cfe5f/docs/specs/world-engine/foundation.md)。

运行层与编辑工具的总序见[计算接入](../../docs/engineering/execution-batches.md)。以下是方法依据；五行环境影响、灵气、气韵及灵物补给是Reol的虚构世界法则，不声称得到现实科学证明。

RimWorld、修仙模拟器、Project Porcupine及Godot从零教程的对象/空间/行动架构对照见[模拟游戏基础架构研究](colony_sim_architecture.md)，其中区分公开接口、教学实现与Reol迁入建议。

俯视山丘/高台、地表高度与局部多层、Factorio/OpenTTD及Godot 2.5D/3D候选的扩展研究见[高度与大世界拓扑](elevation_and_world_topology.md)，对应[空间方案](../proposals/elevation.md)。不能从2D/3D画面直接推断模拟维度或性能。

## 1. 可借鉴的模拟经验

### Dwarf Fortress：让基础条件共同决定环境

Tarn Adams 的原章 [Simulation Principles from Dwarf Fortress](https://www.gameaipro.com/GameAIPro2/GameAIPro2_Chapter41_Simulation_Principles_from_Dwarf_Fortress.pdf)说明：分别处理温度、降水、海拔和排水，再由这些条件决定生物群系，比直接随机分配群系更连贯；迎风降水与背风雨影也是有用的现实参照。作者同时强调逐步运行、理解组成与作用，以及只保留对体验有意义的复杂度。

对 Reol 的取舍：先有地理、环境来源、传输、建筑与受体的真实作用，再添加雨林、沙漠、寒地等内容。不是把气象学、地质学或所有仙侠设定一次模拟完；不以大量属性名代替互相影响。

### Project Porcupine：房间、储量和执行过程分开

[官方仓库](https://github.com/TeamPorcupine/ProjectPorcupine)是 quill18 的 Unity 教程衍生社区项目，README 面向 Unity 5.4.2。此次实际阅读：

- [RoomManager.cs](https://github.com/TeamPorcupine/ProjectPorcupine/blob/master/Assets/Scripts/Models/Area/RoomManager.cs)：从地块连接与洪泛重建房间，处理分割/合并事件。
- [AtmosphereComponent.cs](https://github.com/TeamPorcupine/ProjectPorcupine/blob/master/Assets/Scripts/Models/Area/AtmosphereComponent.cs)：保存气体数量和热能，由其求温度；转移气体也转移其热能。
- [TemperatureDiffusion.cs](https://github.com/TeamPorcupine/ProjectPorcupine/blob/master/Assets/Scripts/Models/Area/TemperatureDiffusion.cs)：登记热源/汇，按房间温差和传导系数交换；坐标温度实际上取房间统一温度，室外源不按 Reol 所需方式处理。

可参考结构改变后重建连接、数量与强度分离、显式源汇。不能直接满足野外局部热点、移动灵物、近远区聚合与本项目共同时间合同，不能整套移植。

许可按[仓库声明](https://github.com/TeamPorcupine/ProjectPorcupine#copyright--licensing)区分：社区程序默认 GPLv3，非代码资产默认 CC BY-NC-SA 3.0；原作者另行提供的不含社区贡献的教程工程才是 MIT。本轮只参考思路，不复制社区代码或资产，不引入 Unity/C#。

### Red Blob Games：地形、风与降水形成可解释的差异

[Mapgen4 演示与文章入口](https://www.redblobgames.com/maps/mapgen4/)提供可编辑山脉、海洋、蒸发、风、降水、河流与生物群系的组合示范。适合参考宏观地图生成和可视化调参，不是持久世界的运行框架。生成器输出和代码许可证是不同事项，使用代码须另查对应文件许可。

对 Reol 的取舍：世界宏观坐标映射到纬度、海拔和水汽来源；局部地图不要用相互独立的噪声标签硬拼气候，也不要把一个山门附近的512格直接拉成从赤道到极地。

## 2. Godot 工具与插件

| 候选 | 第一方证据、许可和状态 | 适用与取舍 |
|---|---|---|
| Godot 4.7 TileMapLayer / TileSet Terrains | [连接API](https://docs.godotengine.org/en/4.7/classes/class_tilemaplayer.html#class-tilemaplayer-method-set-cells-terrain-connect)、[TileSet](https://docs.godotengine.org/en/4.7/classes/class_tileset.html)；引擎内置 | 首选。匹配边/角并更新邻格，必须配置必要瓦片组合。可实现直墙、转角、T口、十字；不提供施工、产权、房间或温度模拟。 |
| Better Terrain | [官方库1.1](https://godotengine.org/asset-library/asset/1806)、[源码](https://github.com/Portponky/better-terrain)、[运行接口](https://github.com/Portponky/better-terrain/blob/main/addons/better-terrain/BetterTerrain.gd)；Unlicense。官方库标Godot4.3，不能据此推断本机4.7.2兼容 | 候选，不安装。源码按邻格类型给候选贴图评分，扩展更新周边并缓存TileSet资料，适合更复杂的匹配规则。待内置实际不满足后，在独立工程固定提交验证。 |
| Gaea | [官方仓库](https://github.com/gaea-godot/gaea)、[beta6](https://github.com/gaea-godot/gaea/releases/tag/v2.0.0-beta6)；MIT，2.0仍属早期/beta，官方提醒复杂项目优化不足 | 程序化生成工具，不是气候持续模拟、房间或热场引擎。现有地图已能生成，本轮无必要替换。 |
| Godot 2D 灯光 | [官方教程](https://docs.godotengine.org/en/4.7/tutorials/2d/2d_lights_and_shadows.html)；内置PointLight2D、DirectionalLight2D、LightOccluder2D等 | 可表现夜明珠、太阳、遮挡。不把GPU亮度当游戏真值：无头运行、远区及关闭特效仍需能查询同源的规则照度。 |

Better Terrain、Gaea 均只做源码/文档研究，未宣称载入、运行或性能通过。新依赖仍按项目规则说明并核对授权；当前推荐无需新增依赖。

## 3. 自动围墙的职责边界

1. 玩家拖线或框选形成逐格可施工蓝图，检查范围、地形、权限、成本和工序。
2. 模拟层保存真实已建墙、门、材质与开闭状态，给出连接、阻挡、支撑及各类透过率。
3. 表现层根据相邻已建结构选直段、端头、角、T口和十字；删改只刷新受影响格与邻格，包括跨显示区块边界。
4. 空间层依据真实连接更新围合和通行，环境层更新换热、漏气、光遮挡等。贴图正确并不代表空间或环境已经更新。

代码占位美术可以先用四邻16组合画墙，再接内置Terrains；需要转角素材时再生成图集。不同材质能否连接、门两端如何连接、拐角如何遮挡，必须由明确规则决定。

## 4. 本轮研究结论

采用 Godot 内置瓦片/灯光表现，加现有纯GDScript模拟与共同时间；补空间介质、地形变化、来源/传输/受体和局部失效。没有发现上述候选能直接替代整个自洽修仙世界运行层。先补共用接缝，不为每种宝物或房间再写一套独立环境系统。

## 5. 数值方法、太阳几何与编辑架构依据

| 第一方来源 | 支持什么 | Reol如何使用及边界 |
|---|---|---|
| NIST FiPy：[有限体积方法与离散项](https://pages.nist.gov/fipy/en/stable/numerical/discret.html) | 控制体保存量，通过相邻边界通量交换，分别处理时间变化、输运、扩散和源项 | 借鉴格/边的储量与交换账，明确容量、源汇和边界。只参考方法，不安装FiPy/Python运行时求解器；轻量求解的稳定性/误差须自行验证，不把FiPy默认求解器当性能证明。 |
| NOAA：[太阳位置与日出日落公式](https://gml.noaa.gov/grad/solcalc/solareqns.PDF)、[说明](https://gml.noaa.gov/grad/solcalc/calcdetails.html) | 纬度、太阳赤纬与时角决定太阳位置，经度参与当地太阳时；由几何判断昼夜 | 参考几何关系，为360天仙侠历法明确轨道相位/倾角，不照搬地球365天经验系数。极区先处理无日出/日落分支；NOAA网页计算器已停止维护，仅作公开方法参考，不成为运行服务。 |
| Robert Nystrom：[Command](https://github.com/munificent/game-programming-patterns/blob/master/book/command.markdown)、[Dirty Flag](https://github.com/munificent/game-programming-patterns/blob/master/book/dirty-flag.markdown)、[Spatial Partition](https://gameprogrammingpatterns.com/spatial-partition.html) | 将请求作为可传递数据、区分原状态和可重建缓存、按位置缩小查询范围 | 共用命令/查询接缝、改动后局部失效和空间索引；不代表所有世界过程可撤销，也不要求更换成完整ECS或保存所有事件重演世界。 |
| Godot：[Resources](https://docs.godotengine.org/en/4.7/tutorials/scripting/resources.html) | 资源承担数据，可共享加载，和场景节点职责分开 | 定义和运行实例分开；不改共享Resource当作改某个人物。既有JSON继续做唯一持久定义，Inspector适配不得另造第二份权威数据。 |
| Godot：[EditorPlugin](https://docs.godotengine.org/en/4.7/tutorials/plugins/editor/making_plugins.html)、[InspectorPlugin](https://docs.godotengine.org/en/4.7/tutorials/plugins/editor/inspector_plugins.html)、[EditorUndoRedoManager](https://docs.godotengine.org/en/4.7/classes/class_editorundoredomanager.html) | 可在Godot内扩展属性编辑、工具面板和编辑历史 | 按实际需要补小工具；撤销只管草稿，模拟进度用隔离快照重置。当前未创建插件；官方插件示例不代表任意既有模拟脚本无需适配便能在@tool环境运行。 |

热传导采用物理类比和可测离散方法；五行环境影响传播只借其计算结构，反应、补给和五行作用由游戏定义。风水先依据可解释空间与灵流格局表现，不给传统设定添加虚假的科学背书。实现需另记录单位、简化假设、极值和误差，引用理论不等于本项目已实现或通过验收。

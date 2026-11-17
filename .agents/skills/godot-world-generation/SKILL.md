---
name: godot-world-generation
description: 修改或review Reol的地图生成、区块接续、世界随机、地形视图与TileMap接入时使用；关卡体验设计另有level-design。
---

# 世界生成与接续

本地合并改写原open-world-2d、procedural-gen、godot-tilemap及roguelike中的适用空间检查；第三方归属见[NOTICES](../../../THIRD_PARTY_NOTICES.md)。先区分Terrain/对象事实、导航索引和表现区块，不把显示卸载当实体死亡，也不预设当前已经实现远区LOD。

- 生成规则、seed、版本和已发生变化分开。布局/掉落/个人选择与画面随机隔离；需要加载次序无关的区块应按稳定区域标识派生随机流，而非共享一个按加载顺序消耗的RNG。抽样候选的顺序也须稳定，不能只固定seed却任由不稳定的集合/插入次序改变选择；仅在相关边界排序或提供稳定顺序，不全局每帧排序。继续随机序列要存state，只有seed不足以续接中途。
- seed不保证跨算法、引擎或平台永远相同；按项目兼容范围保存生成结果或明确生成版本。噪声先核值域与采样坐标再组合，避免负数幂、相关字段、整数采样退化；直接复用FastNoiseLite等成熟支持，不因教程引入自写噪声库。
- 生成到逻辑数据，再更新可重建表现。跨区道路、水系、地标和导航使用一致边界规则；负坐标分区用正确向下取整，GDScript整数除法向零截断，不能把它或任意位运算直接视为floor分区。放置尝试有上限，失败能退出。
- 检查实际所需的连通性、安全出生、通行净空和钥匙/能力依赖。局部WFC合法不保证全局可达。权重、放回/不放回、保底各有不同分布，不能将用户举例的机制自动加入游戏。
- 当前可见、个人已知与记忆是不同状态；地形绘制或生成不能刷新全员认识。卸载/重载只改变表示时，人物、库存、在途活动及已发生后果仍由原owner保存，不能重访补造历史。
- 新建/运行编辑TileMapLayer时再读[图块接入](references/tilemap.md)，当前已有MultiMesh地形不因此迁移。远区方案须说明与当前共同时间/保存的交接，本技能不要求预建另一套远区世界。

验证选相同seed不同生成/加载次序、负坐标/边界、局部改地形后导航/外观失效、存读后重访，以及多seed分布反例。生成耗时与接续工作量按实测分片，不把单seed成功当整体保证。

依据：[RandomNumberGenerator](https://docs.godotengine.org/en/4.7/classes/class_randomnumbergenerator.html)、[FastNoiseLite](https://docs.godotengine.org/en/4.7/classes/class_fastnoiselite.html)、[Red Blob噪声生成](https://www.redblobgames.com/maps/terrain-from-noise/)；后者解释值域、八度和地形分布，不规定本项目的世界规则。

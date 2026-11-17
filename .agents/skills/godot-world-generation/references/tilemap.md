# TileMap接入时检查

本地重写原godot-tilemap相关指导；归属见[NOTICES](../../../../THIRD_PARTY_NOTICES.md)。只在本次采用/修改TileMapLayer时读取，不用来取代既有Terrain与MultiMesh。

- `TileMapLayer`持一个图层，`set_cell`使用source、atlas coordinates和alternative标识；迁移旧TileMap时核实际版本签名，不只改类名。
- `local_to_map`需要层局部坐标，先从全局/视口经正确变换进入该层；`map_to_local`给格子中心，不包含每张图的视觉偏移。atlas格、逻辑地块和画面像素不是同一单位。
- 共享TileSet的custom data通常是图块类型数据，不是每个世界格子的独立可写状态。单格水量/库存/耐久仍归原owner；临时TileData覆盖不能无意修改共享材质、shape等子资源。
- terrain connect要求所需peering组合齐全，且可能修改相邻格。运行编辑的脏集合须覆盖实际受影响邻域，不每次重新扫全地图。
- TileMap内部更新通常批到帧尾，`update_internals()`有成本，不在逐格循环强制调用；`notify_runtime_tile_data_update()`只用于相关变化。物理/导航新鲜度按真实同步边界核。
- 地图显示碰撞/导航与模拟Terrain不应各持权威障碍。Y排序还涉及脚点、TileMapLayer层级和`z_index`；单开一个`y_sort_enabled`不能自动解决所有跨批排序，当前人物/静物由共同MultiMesh排序。

依据：[TileMapLayer](https://docs.godotengine.org/en/4.7/classes/class_tilemaplayer.html)、[TileSet](https://docs.godotengine.org/en/4.7/classes/class_tileset.html)。

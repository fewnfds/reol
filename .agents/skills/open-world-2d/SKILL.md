---
name: open-world-2d
description: 修改Reol地图、区块加载、世界生成或远区接续时使用。
---

# 地图与区块变更

基础范围查[constraints](../../../docs/engineering/constraints.md)，空间规则查[objects-and-interaction](../../../design/rules/objects-and-interaction.md)，实际入口由[工程地图](../../../docs/engineering/README.md)定位。世界设计候选在[world_simulation_target](../../../design/systems/world_simulation_target.md)。

先区分要改的是原地形/对象、可重建空间索引还是视图加载。根据当前瓶颈选择生成、导航、绘制或局部失效的数据粒度，避免一次跨格迫使无关对象重算。近远区交接与保存只检查本次影响的状态/过程。

处理生成顺序或区块接续时再读[world_streaming](references/world_streaming.md)。TileMap与碰撞API按实际引擎版本查询，不预设一个Node对应一个可保存实体。

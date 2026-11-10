# 八方向外观候选与当前接线

类型：按需外观方案。当前人物使用原创代码生成的分层像素占位，正式美术与完整动作尚未完成。实际能力看[FEATURES](../../status/features.md)，不能把历史提示词当成当前制作任务。

`Player`、`Pawn`和V页复用`PawnVisuals`/`HumanoidAppearance`；`HumanoidPose`读取原身体和过程。现有资源支持有限`idle / walk / gesture`，共享方向和相位；行走周期、解剖左右、锚点和层次以当前manifest/代码为准。视觉不移动真实身体，也不拥有原物装备。

候选目标是连续换向、左右手/挂件归属正确、层间共享身体动作，按可见对象控制绘制与采样成本。具体Node结构、帧数、贴图尺寸、动画周期及预算由实现与实测选择，不永久冻结历史A1参数。

- 来源与许可：[八方向研究](../../../design/research/eight_direction_sources.md)、[当前技术素材](../../../assets/characters/humanoid_sample/README.md)。
- 旧网页模型素材生产步骤已移到[归档提示词](../../archive/art/character_generation/README.md)，只在恢复该路线时查阅。
- 历史完整方案可从[本次整理前版本](https://github.com/fewnfds/reol/blob/4bf039fe8fadf95e639ae64a077e4fc3c7bdeeea/docs/specs/presentation/eight-directions.md)追溯，不在当前页重复进度和美术验收矩阵。

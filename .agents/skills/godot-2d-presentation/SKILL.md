---
name: godot-2d-presentation
description: 修改或review Reol的Camera2D、遮挡排序、MultiMesh、动画反馈或二维shader时使用；绘制素材另用create-game-assets。
---

# 纯二维表现与时间一致性

本地合并重写原camera-systems、godot-animation、game-feel、godot-shaders、shader-programming；归属见[NOTICES](../../../THIRD_PARTY_NOTICES.md)。当前固定斜俯视Camera2D，人物/静物共同MultiMesh排序；不重开三维/全图透视探索。

- 从`view_rig.gd`、`art.gd`、`impact.gd`与原绘制入口定位世界、显示和视口坐标。遮挡按共同地面脚点和层级；贴图上沿/树冠不是身体位置，拆成不同批次前确认仍能互相穿插。不要只开Y-sort就声称解决跨批遮挡。
- 跟随相机、动画和选择采同一显示时刻/轨迹；鼠标转世界坐标前相机变换已更新。平滑用与dt一致的公式或引擎成熟支持，避免固定每帧lerp。缩放后的可视矩形才用于边界夹紧，地图小于视口要有合理中心。
- 世界姿态、展示补间、视觉偏移各有写入者；不要AnimationPlayer、Tween和自写循环争同属性。瞬移、读档、槽位换人重置插值历史；Tween绑定对象并有取消/替换出口，循环动画不能依赖自然finished作为唯一结束条件。
- 命中/受伤反馈消费实际结果，按epoch/事件身份去重并限制并发；粒子、声音和视觉震动不反过来结算伤害。真实击退仍是模拟行动，不能归入纯视觉。视觉与玩法随机隔离。
- 震动叠加于最终相机偏移并回稳态，拾取/瞄准/放置沿原含震动或排震动的坐标合同。主线程`Engine.time_scale`不能替代Runner的世界倍率/顿帧；多段效果覆盖和恢复有明确归属，不能旧回调解除新效果。
- 可读性优先于效果数量，避免密集闪白/遮挡关键动作，支持项目既有或本次需要的减弱反馈设置；这不是要求每次新做一套设置菜单。手感取决于实际输入、动作承诺、命中和反馈的时序，不能只靠加震动验收。

写shader/改材质与GPU缓冲时读[二维GPU检查](references/shaders.md)。素材切片/脚点交由素材技能，不在这里复制其制作步骤。

真实窗口核遮挡、缩放、转角/停止、连续动作反馈与取消。headless加载不能证明GPU画面或手感；同条件渲染测量仅在改动涉及性能时选用，不默认每个视觉修正跑性能矩阵。

依据：[二维变换](https://docs.godotengine.org/en/4.7/tutorials/2d/2d_transforms.html)、[Tween](https://docs.godotengine.org/en/4.7/classes/class_tween.html)。

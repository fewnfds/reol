---
name: godot-motion-navigation
description: 修改或review Reol的连续移动、碰撞、寻路、工作位置到达和坐标转换时使用；按碰撞语义和实测规模选择身体表示。
---

# 身体、路径与空间的一致性

本地合并重写原godot-2d-movement、godot-physics、physics-tuning及game-ai的导航部分；归属见[NOTICES](../../../THIRD_PARTY_NOTICES.md)。真实合同见[连续移动](../../../docs/engineering/architecture.md#连续移动与共同导航)。

- 地块占地、身体地面接触中心、可视脚点、贴图上沿和鼠标位置是不同量。身体通过`actor_slots`定位，不用ID推数组行；单位为格/秒或毫秒时明确转换，不混Godot像素/秒。斜向输入不应无故提速。
- 普通移动、突进、闪步和击退经过同一Terrain净空/扫掠与实际轨迹入口；不能先穿透再仅校终点，也不能动画位移写回第二个身体位置。人物头身贴图不扩大地面碰撞。
- 使用片内同一时刻的位置/折线做命中、占位和到达判断；旧显示Frame、步末位置及空间桶各有时效，不能混用。贴墙滑动后采用碰撞解算的真实落点与路程，重复接触须能退出，不能小误差越修越深。
- 导航只规划可行路，不代替实际身体执行。检查身体净空、对角切角、门/家具变化、工作格/接近侧和无路结果；路径代价与启发式、partial path语义一致。动态障碍失效只唤醒相关路径，不每帧全员重寻路。
- 当前Godot `AStarGrid2D`由各工作lane独占；查目标API线程限制，不能只因函数只读就并发调用同一实例。后台输入与采用期间校地图/目标/身体代次；陈旧路径复核后再用。
- 世界逻辑时间不随渲染帧率改变；身体已有自己的共同时间积分，不能照抄“所有运动放`_physics_process`”再加第二套积分。显示插值只使用一套姿态历史；瞬移/换档/身份复用时重置，提逻辑频率不是无成本修复。

相关验证选真实几何反例：斜向贴角、窄道、贴墙连续攻击、沿路途中拆/建障碍、占用的工作格及低显示帧率。Godot层/遮罩只检查本次确实使用的物理查询，不为现有几何模拟新增物理服务器副本。

依据：[AStarGrid2D](https://docs.godotengine.org/en/4.7/classes/class_astargrid2d.html)、[物理插值](https://docs.godotengine.org/en/4.7/tutorials/physics/interpolation/index.html)、[Red Blob寻路图模型](https://www.redblobgames.com/pathfinding/a-star/introduction.html)。

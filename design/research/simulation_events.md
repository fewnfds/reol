# 模拟世界的结算与事件参考

> 研究资料：记录来源与适用限制，不授予引入依赖或改变规则的权限。

核对日期：2026-11-09。本文记录公开资料能支持的工程判断，不推测闭源游戏内部实现。采用合同见[事件执行](../../docs/engineering/event-contract.md)，建设仍归[唯一主计划](../../docs/plans/foundation-priorities.md)。

## 成熟项目提供的边界

| 一手资料 | 能确认的经验 | Reol 的采用方式 |
|---|---|---|
| [RimWorld 官方介绍](https://rimworldgame.com/) | AI Storyteller 安排外部事件，生态、温度与生长季影响殖民地；公开玩法描述不能证明其内部调度算法 | 故事导演是事件请求的上层生产者。基础结算、事件队列和领域效果分别负责；本阶段不实现叙事导演 |
| [RimWorld Alpha 8 官方说明](https://ludeon.com/blog/2014/12/alpha-8-winter-is-coming-released/) | 室内外温度、衣物保护、冷热伤害、冷藏与积雪移动有相互关联的玩法 | 借鉴共享环境条件与不同受体后果的组合；不能由玩法说明断言其内部只有一个场、统一公式或事件总线 |
| [CDDA Effect On Condition](https://docs.cataclysmdda.org/JSON/EFFECT_ON_CONDITION.html) | 条件与效果分开；有显式、周期和指定事件触发；可停用，特征/仿生变化可重启相关循环 | 可信规则登记、纯载荷校验、READY/WAIT/INVALID、精确 topic 唤醒。等待条件不靠全体实体每帧轮询 |
| [Factorio LuaBootstrap](https://lua-api.factorio.com/latest/classes/LuaBootstrap.html) | 事件有注册/过滤与对象销毁通知；初始化和加载有不同生命周期 | 只有相关目标变化才通知等待项；恢复重建派生索引，不补发开局事件，不在加载时重新施加效果 |
| [Factorio DelayedActiveTriggerPrototype](https://lua-api.factorio.com/latest/prototypes/DelayedActiveTriggerPrototype.html) | 延时、重复次数/间隔、来源销毁后的取消是明确的数据合同 | 队列持久化到期、重复、重试、期限与终态回执；原领域复核目标存在及效果合法性 |
| [Factorio FFF-161](https://factorio.com/blog/post/fff-161) | 污染按区块周期处理，到期队列替代每tick遍历检查 | 持续过程可按到期/变脏集合计算；离散事件队列与连续模拟的执行索引各有职责 |
| [Factorio FFF-209](https://factorio.com/blog/post/fff-209) | 电网按设备类别组织数据，烟雾另用精简表示及固定周期 | 共享运行合同允许专门数据结构和算法，不要求每种对象进入同一更新器或拥有相同能力 |
| [Factorio FFF-270](https://factorio.com/blog/post/fff-270) | 完整停开不应改变后续可观察行为；定义变化和交叉引用会影响恢复 | 保存真实状态和必要在途因果，缓存可重建；新增房温不另建中央SL或靠重放触发器恢复 |

这些资料支持采用分层接口，不要求安装插件或复制外部源码。CDDA 的内容语言和 Factorio 的 Mod API 不直接成为 Reol 的运行依赖；RimWorld 的公开概念只作为分工参照。

## 采用的结构

`GameClock` 受理共同时间；`SimSettlementKernel` 按阶段/依赖续算；`SimEventQueue` 保存离散请求并在登记的事件阶段有界执行；原领域持有身体、库存、环境响应与实际后果。`SimWorldEvents` 是可信规则目录，首先接运输评估和植物觉醒两个消费者。

温度响应、植物生长等连续过程保留区间算法和各自采样合同。不会为了统一接口把每毫秒的生长变成一条事件，也不把所有世界事实改成 Event Sourcing。signal 用于同步派生索引，公开完成结果仍经过完整结算边界。

这些资料支持的工程推论是：统一共同时间、执行顺序、提交与恢复合同，具体机制保留明确owner。“所有抽象事物都持续散发影响”不足以描述攻击、原物转移或有时延的消息；静态来源持续有效也不要求不断生成事件。房温、光照、五行和灵气各有不同组合及消耗语义，不能从竞品的温度机制推定所有通道一房一值、守恒或相加。

灵智采用主体与身体组合：原植物仍由 `SimPlants` 持有，只在事件成立后给同一植物建立 `SimEmbodiment` 载体/主体关系。它不自动获得行走、背包或人类知识。花盆的支撑与水由建筑持有，植物只保存支撑引用；这沿用原所有者合同，而非构造植物专用的第二套实体和保存系统。

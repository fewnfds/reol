# 模拟世界的结算与事件参考

核对日期：2026-11-09。本文记录公开资料能支持的工程判断，不推测闭源游戏内部实现。采用合同见[事件执行](../../docs/engineering/event-contract.md)，建设仍归[唯一主计划](../../docs/plans/foundation-priorities.md)。

## 成熟项目提供的边界

| 一手资料 | 能确认的经验 | Reol 的采用方式 |
|---|---|---|
| [RimWorld 官方介绍](https://rimworldgame.com/) | AI Storyteller 安排外部事件，生态、温度与生长季影响殖民地；公开玩法描述不能证明其内部调度算法 | 故事导演是事件请求的上层生产者。基础结算、事件队列和领域效果分别负责；本阶段不实现叙事导演 |
| [CDDA Effect On Condition](https://docs.cataclysmdda.org/JSON/EFFECT_ON_CONDITION.html) | 条件与效果分开；有显式、循环和指定事件触发；条件不合可停用并在条件改变后唤醒 | 可信规则登记、纯载荷校验、READY/WAIT/INVALID、精确 topic 唤醒。等待条件不靠全体实体每帧轮询 |
| [Factorio LuaBootstrap](https://lua-api.factorio.com/latest/classes/LuaBootstrap.html) | 事件有注册/过滤与对象销毁通知；初始化和加载有不同生命周期 | 只有相关目标变化才通知等待项；恢复重建派生索引，不补发开局事件，不在加载时重新施加效果 |
| [Factorio DelayedActiveTriggerPrototype](https://lua-api.factorio.com/latest/prototypes/DelayedActiveTriggerPrototype.html) | 延时、重复次数/间隔、来源销毁后的取消是明确的数据合同 | 队列持久化到期、重复、重试、期限与终态回执；原领域复核目标存在及效果合法性 |

这些资料支持采用分层接口，不要求安装插件或复制外部源码。CDDA 的内容语言和 Factorio 的 Mod API 不直接成为 Reol 的运行依赖；RimWorld 的公开概念只作为分工参照。

## 采用的结构

`GameClock` 受理共同时间；`SimSettlementKernel` 按阶段/依赖续算；`SimEventQueue` 保存离散请求并在登记的事件阶段有界执行；原领域持有身体、库存、环境响应与实际后果。`SimWorldEvents` 是可信规则目录，首先接运输评估和植物觉醒两个消费者。

温度响应、植物生长等连续过程保留区间算法和各自采样合同。不会为了统一接口把每毫秒的生长变成一条事件，也不把所有世界事实改成 Event Sourcing。signal 用于同步派生索引，公开完成结果仍经过完整结算边界。

灵智采用主体与身体组合：原植物仍由 `SimPlants` 持有，只在事件成立后给同一植物建立 `SimEmbodiment` 载体/主体关系。它不自动获得行走、背包或人类知识。花盆的支撑与水由建筑持有，植物只保存支撑引用；这沿用原所有者合同，而非构造植物专用的第二套实体和保存系统。

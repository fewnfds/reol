# 模拟世界的结算与事件参考

> 研究资料：记录来源与适用限制，不授予引入依赖或改变规则的权限。

核对日期：2026-11-09。本文记录公开资料能支持的工程判断，不推测闭源游戏内部实现。采用合同见[事件执行](../../docs/engineering/architecture.md)，建设仍归[唯一主计划](../../docs/plans/foundation-priorities.md)。

## 成熟项目提供的边界

| 一手资料 | 能确认的经验 | 可借鉴思路 |
|---|---|---|
| [RimWorld 官方介绍](https://rimworldgame.com/) | AI Storyteller 安排外部事件，生态、温度与生长季影响殖民地；公开玩法描述不能证明其内部调度算法 | 故事导演是事件请求的上层生产者。基础结算、事件请求和领域效果可以分别负责；公开概念不证明Reol已有叙事导演 |
| [RimWorld Alpha 8 官方说明](https://ludeon.com/blog/2014/12/alpha-8-winter-is-coming-released/) | 室内外温度、衣物保护、冷热伤害、冷藏与积雪移动有相互关联的玩法 | 借鉴共享环境条件与不同受体后果的组合；不能由玩法说明断言其内部只有一个场、统一公式或事件总线 |
| [CDDA Effect On Condition](https://docs.cataclysmdda.org/JSON/EFFECT_ON_CONDITION.html) | 条件与效果分开；有显式、周期和指定事件触发；可停用，特征/仿生变化可重启相关循环 | 条件判断、到期与变化通知可分开；避免为等待条件全体轮询 |
| [Factorio LuaBootstrap](https://lua-api.factorio.com/latest/classes/LuaBootstrap.html) | 事件有注册/过滤与对象销毁通知；初始化和加载有不同生命周期 | 只有相关目标变化才通知等待项；恢复重建派生索引，不补发开局事件，不在加载时重新施加效果 |
| [Factorio DelayedActiveTriggerPrototype](https://lua-api.factorio.com/latest/prototypes/DelayedActiveTriggerPrototype.html) | 延时、重复次数/间隔、来源销毁后的取消是明确的数据合同 | 延迟、重复与取消需要明确语义；并不要求Reol具备同一队列平台 |
| [Factorio FFF-161](https://factorio.com/blog/post/fff-161) | 污染按区块周期处理，到期队列替代每tick遍历检查 | 持续过程可按到期/变脏集合计算；离散事件队列与连续模拟的执行索引各有职责 |
| [Factorio FFF-209](https://factorio.com/blog/post/fff-209) | 电网按设备类别组织数据，烟雾另用精简表示及固定周期 | 共享运行合同允许专门数据结构和算法，不要求每种对象进入同一更新器或拥有相同能力 |
| [Factorio FFF-270](https://factorio.com/blog/post/fff-270) | 完整停开不应改变后续可观察行为；定义变化和交叉引用会影响恢复 | 保存真实状态和必要在途因果，缓存可重建；新增房温不另建中央SL或靠重放触发器恢复 |

这些资料支持采用分层接口，不要求安装插件或复制外部源码。CDDA 的内容语言和 Factorio 的 Mod API 不直接成为 Reol 的运行依赖；RimWorld 的公开概念只作为分工参照。

## 当前使用边界

统一时间、执行顺序、提交与恢复责任，不等于统一成Event Sourcing或一条包办所有过程的事件总线。持续温度/植物过程可以按自己的采样节奏计算，实际离散后果由相应owner提交。

旧GameClock、SimSettlementKernel、SimEventQueue与SimWorldEvents已经退役；原结构说明可从[Git](https://github.com/fewnfds/reol/blob/02958cc/design/research/simulation_events.md)追溯。当前Runner、World、领域过程与outcomes/PersonEvents的分工只查[架构](../../docs/engineering/architecture.md)，不要据本页重建旧注册表或事件阶段。

灵智、身体能力和植物原身份可以组合，不要求植物继承怪物或自动取得行走/背包能力。温度、五行、光照与灵气的组合/消耗语义由[规则](../rules/environment.md)分别决定，竞品事件接口不能替项目定义世界法则。

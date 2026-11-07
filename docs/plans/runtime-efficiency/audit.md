# 代码审计范围与优先候选

静态核对基线`eff27a7dcf77031a4084258cc688bbb3616b64e4`。本页除环境单次变更引用既有计时外，**其余为代码结构/增长风险，尚无独立耗时证据**。代码行号用于定位，不构成性能证明；不会因存在for循环就安排重写。实施合同见[contracts](contracts.md)。

## 已测热点与环境广域风险

| 路径 | 实际做法/成本证据 | 统一改进方向 |
|---|---|---|
| [field_cache](../../../scripts/sim/environment_field_cache.gd) begin/step_source_change，[source_change](../../../scripts/sim/environment_source_change.gd) | 半径4物变更跨4块，1024格全部7通道重算；既有短测224/220ms，其中基础场185/183ms | 按有效覆盖/改变通道增量max；只重算真正改变的响应；不是按物品名字快通道 |
| [world_environment_fields](../../../scripts/sim/world_environment_fields.gd) next_boundary/settle/_refresh_targets（约125–176、428） | 任一响应到期可刷新全部曾触及块；来源移除残留使该集合长期保留。当前最多512²格为结构上界，不是已测常时负载 | 沿温度/五行已有earliest/count维护到期块/域，不改世界时间，不丢残留/气候/潮汐依赖 |
| [environment_source_definitions](../../../scripts/data/environment_source_definitions.gd) profile，[world_environment_source_participant](../../../scripts/sim/world_environment_source_participant.gd) | 目前16个材料/器物固有绑定均冷热0；设备可启用后动态发热。profile每次给深副本，完成操作复制排序全部曾影响块 | 静态描述共享，实际effect activation注册；只传本次/新增块；不误判所有物品都没有冷热能力 |

环境已有零源/同源no-op、来源槽位/块上界、温度/五行packed列与step。要改的是热路径未利用这些信息的部分，不能再把“增加缓存/分片”当不存在的新模块。

## 人物与调度

| 路径与频率 | 现有结构与风险 | 需要保留/建议 |
|---|---|---|
| [village_simulation](../../../scripts/sim/village_simulation.gd):249、291–313、847；每次求界/推进分片 | 多次排序全员，投影全部行动（空行动直接返回），逐活人×地点观察；需求衰减全员 | active动作/到期决策/可观察候选；需求固定点carry和阈值精确惰性/批算，不能冻结空闲者 |
| [regional_simulation](../../../scripts/sim/regional_simulation.gd):591、628、1383、741；每世界边界 | 固定域列表求界、部分运行适配再次求界；阶段调用可选域，各域内再次全员筛选 | 域/地区最早边界摘要、依赖失效和原阶段顺序。固定二十余域迭代未测，不先上复杂全局堆 |
| [health](../../../scripts/sim/health.gd):85、273、354；按人查询/每世界边界 | 每人排序全部伤病找未愈；结算扫描历史wounds/jobs；自主医疗再全员找附近对象，可能N² | actor→未愈ID/活跃诊疗、受伤候选和局部邻近查询；历史记录不参与持续求界但仍保留证据 |
| [clothing](../../../scripts/sim/clothing.gd):115、239、301，[environment](../../../scripts/sim/environment.gd):57、278 | 穿着查询每次扫全部衣物；每人环境采样多次查询，每世界边界再全员考虑穿衣；天气脉冲扫衣物 | actor→slot、湿衣/受天气集合；未穿但湿的衣物仍会干，不能只保留穿戴者 |
| [autonomous_livelihood](../../../scripts/sim/autonomous_livelihood.gd):54、81 | 已按指定成员plans注册，但每边界再全扫plans找工作 | 保留成员式设计，增加到期/资源与行程依赖唤醒；当前人数极小，不声称此处耗时很大 |
| [artifacts](../../../scripts/sim/artifacts.gd):1040、1060，健康/灵源consider | 部分每边界全员查自主机会，再筛实际手法/职责；warming已有瞬时交接集合但仍全员查 | 使用交接/能力/实际持物候选，保留原NPC优先级与失败回退；不每人轮询所有可选玩法 |

## 交互、空间和长期历史

| 路径与频率 | 现有结构与风险 | 需要保留/建议 |
|---|---|---|
| [field_opportunities](../../../scripts/sim/field_opportunities.gd):196、207、241、380 | 全purpose求界/结算；每2游戏秒角色×地点感知；随后可能扫描全部社交事件找本人知识 | active/due目的、邻近观察者及actor/site知识索引；不得用全知地理替换真实感知。当前仅一个site |
| [source_care](../../../scripts/sim/source_care.gd):103、120、501 | 每边界安排×警告搜索、每自主候选再找看守安排；当前上限4安排/128警告 | 已有source_started/finished钩子，沿其维护guard/arrangement→活跃源/警告及到期集合；观察和宽限时刻保留 |
| [avian_life](../../../scripts/sim/avian_life.gd):163、176、243，[large_bodies](../../../scripts/sim/large_bodies.gd):115、183 | 鸟每次决定排序全部站点；巨兽每格判定跨域遍历身体/地点/地面鸟，并在每步同步全地区 | 局部空间候选/多格扫掠；鸟需求仍连续变化。开局1兽、少数鸟、12站点，属规模风险 |
| [object_lifecycle](../../../scripts/sim/object_lifecycle.gd):90–99、821 | 原物变更先同步全部地区；局部器物查询已有地面桶，却仍扫描所有contained容器组和旧器物后判断距离 | 证明局部因果后再缩同步区；容器/持有者锚点空间索引，更新搬运/移动/跨区；不复制位置或删预算失败 |
| [regional_simulation](../../../scripts/sim/regional_simulation.gd):529 owns_for_scope、actor_controls等 | 每次按scope询问固定十余域，人物home多处逐region寻找 | actor→原属owner派生映射可共享；活动域候选只在测出热点后建，原owns_actor/相位复验，不能造另一权威锁 |
| [workplaces](../../../scripts/sim/workplaces.gd):108，[world_continuity_runtime](../../../scripts/runtime/world_continuity_runtime.gd):457，[structure_query](../../../scripts/sim/structure_query.gd):86 | 寻路每格问所有地区固定墙格；墙邻接显示再次问点。真实construction已有点索引 | 先复用/组合原阻行点集合，真实变更局部失效；保留阻行/遮视/屋顶差异。目前固定布局小，先测 |

## 呈现与面板

| 路径与频率 | 现有结构与风险 | 统一方向 |
|---|---|---|
| [world_objects_runtime](../../../scripts/runtime/world_objects_runtime.gd):355、523、585 | 每渲染帧queue_redraw，重新求可见对象和同点布局；源候选包含全容器组扫描，最多4096预算 | 静态候选/布局按局部变化失效，携物连续插值单独按帧；预算耗尽不能显示伪零或无限回退 |
| [village_runtime](../../../scripts/runtime/village_runtime.gd):420、468，[world_continuity_runtime](../../../scripts/runtime/world_continuity_runtime.gd):370 | 每clock提交投影所有home pawn并构建跨区域人物布局；手动步50游戏ms，可能约20次/游戏秒且积压帧多次 | 每次视图更新共用布局结果，只更新可见/真正改变身体；远区真实模拟仍正常。_process只插值可见人已有合理短路 |
| [local_light_runtime](../../../scripts/runtime/local_light_runtime.gd):27–68，[local_light](../../../scripts/sim/local_light.gd):15、90 | 每clock提交标脏，已合并至每帧一次；仍可能441格×128光源+遮挡+图像上传 | 光成员/启用/空间范围/遮挡/视野/到期亮度依赖，静态无变化不重建。不能直接移除时间依赖或静默改全局源数上限 |
| [capability_network_runtime](../../../scripts/runtime/capability_network_runtime.gd):129，[capability_queries](../../../scripts/sim/capability_queries.gd):87等 | 仅面板打开且至多每250世界ms重建；扫本人课程、方法×事件，多次寻找已知物 | 本人证据索引+相关revision，定义编译一次；UI可以展示未知技能节点，不算全员技能执行 |
| [settlement_services_runtime](../../../scripts/runtime/settlement_services_runtime.gd):248，[settlement_services_panel](../../../scripts/ui/settlement_services_panel.gd):215 | 事件/交互刷新时全批次构建本人行，之后JSON签名只能避免后续渲染，省不掉前面扫描 | 本人批次索引、先看revision再构建，动态倒计时局部更新；未证明其为每帧热点 |

## 不应误删的工作与已有基础

- 内容/开局一次性全扫描、定义校验、存档全区同步和独立候选完整验证不是每帧轮询。用户允许暂停保存，不因本方案重写存档。
- 原来源索引、固有光源ID、地面占地桶、结构层点索引、原region boundary缓存、各域active字典、范围/工作预算及部分UI dirty合帧都应保留。
- 公开Dictionary直接写会绕过任何派生索引；改动必须接齐当前真实生产入口。不能靠补一处测试fixture或加对象名判断宣称框架优化。
- 本审计未证明Godot/GDScript达到上限，未证明GPU可加速以上路径；并行前先减少工作、把数据和依赖范围弄清。

所有未测候选先记录访问量、活跃比例、被丢弃候选、每次调用成本再取舍，不能把这里的表直接变成“全部必须重写”队列。

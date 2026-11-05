# 源场接管实际环境的实施合同（F2）：引言

> 候选合同，不是已实现证据；旧 F/W 等编号、当时顺序和下一步均为历史建议。当前优先级与实施排定见[基础优先级](../../../plans/foundation-priorities.md)。

更新：2026-11-05。本页是待实施的具体接入合同，不代表新源场已成为游戏世界规则。现状与证据以 [HANDOFF](../../../status/handoff.md)、[BASELINE](../../../status/baseline.md)、[FEATURES](../../../status/features.md) 为准；空间/冷热/五行概念以 [环境规范](../../../../design/proposals/environment.md) 和 [施工与空间](../../../../design/systems/construction_and_space.md) 为准。本合同不覆盖普通场同通道取最大值、欧氏圆形衰减、同类一堆一源、人物及随身物五行暂缓等已定规则。

实施状态：F2a-1已完成少量显式格/已知目标段的实际温度owner及独立存读，见[证据](../../../qa/20261105_actual_temperature_state.md)；源变更事务和完整调度仍未完成，不能把这一步标为整个F2a或Main替换完成。

后续F2a-2已完成纯目标段编译与O(1)下一边界查询，见[证据和误差/成本界](../../../qa/20261105_temperature_segments_and_budget.md)。实际温度16384格整批prepare/commit约198/500ms，故当前逐格对象表示不作为密集世界的最终运行承诺；先解决紧凑/有界处理，再接Main。完整调度、源事务和房间仍未完成。

F2a-3同一owner已改packed块和封存候选，128²提交降至约0.02ms，512²独立组件也通过有限守卫；大批prepare/快照仍慢且近1GiB，见[QA](../../../qa/20261105_packed_temperature_state.md)。接续须减少大字典物化并实现真正保cursor的预算准备；不能把现有整批格数budget当自动续算。无论近远区都只提交完整候选，不清欠算、不用未知环境值冒充中性。

F2a-4已接按块packed输入与槽预算续算，最多64块候选统一发布，三种预算/取消/恢复通过，见[证据](../../../qa/20261105_bounded_temperature_preparation.md)。剩余先接真实物件/场投影候选与共同时间/受体，不能继续扩无依赖的隔离功能。大世界root复制、结束/释放和高异质边界同步成本仍需按实际接入负载验证；快照仍为全量v1物化。

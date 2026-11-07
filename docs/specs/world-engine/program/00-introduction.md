# 世界装配与创作工具：范围

详细接入与工具合同；未接入部分为候选，不代表实现证据。领域职责见[顶层框架](../../../engineering/architecture/05-framework-domains.md)，建设依赖与完成标准见[基础建设计划](../../../plans/foundation-priorities.md)。

当前授权和停点只看[HANDOFF](../../../status/handoff.md)；[旧执行记录](../../../archive/specifications/world_engine_execution.md)只描述当时。新地图先采用平面地块，高差/坡道/三维暂缓；历史证据不追改，运行版本按[有限兼容与退役政策](../../../engineering/compatibility.md)，只维护当前实现。

本目录说明七个框架如何绑定内容、装配世界和接入工具。实际代码见[ARCHITECTURE](../../../engineering/architecture.md)，接入与缺口见[技术总表](../../../status/technical-status.md)，操作见[FEATURES](../../../status/features.md)，构建证据见[BASELINE](../../../status/baseline.md)。

[环境与空间规格](../foundation.md)描述源场/响应、结构反馈、原物账实一致、兼容与性能，具体算法属于相应框架内部。[研究与理论依据](../../../../design/research/world_engine_references.md)区分公开工程经验、数值方法与项目自定义的仙侠规则。

**暂缓的高度研究**：[高度方案](../../../../design/proposals/elevation.md)与[案例](../../../../design/research/elevation_and_world_topology.md)保留以供以后选择；地表高度场、坡道、崖壁、高度感知传播和多层均不纳入当前平面基础。已有高度样本不追改，旧档仅在声明支持范围内恢复/转换，不要求永久保留原解释器。大陆与球形大地图是未来选项。

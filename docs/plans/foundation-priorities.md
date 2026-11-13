# 当前实施计划

授权与停点在[HANDOFF](../status/handoff.md)，已实现能力在[FEATURES](../status/features.md)，性能事实在[BASELINE](../status/baseline.md)。本页只安排当前工作，不登记历轮完成过程。

## 当前方向

优先把现有框架变成可持续试玩的游戏，以用户游玩反馈决定下一项。基础内核、生活/建筑/植物/战斗/交往/有限地区已形成可体验闭环；人物装备和格子背包也已接入。实现范围与尚未具备的玩法只维护在FEATURES。

目前没有排定的下一功能，回到试玩讨论后选择主题；不自动继续精确极限搜索或重写框架。

## 后续选题方式

- 按玩家遇到的体验缺口选择一个可观察出口，定位所属[顶层领域](../engineering/architecture/05-framework-domains.md)，沿[当前owner](../engineering/architecture.md)扩展。
- 新增密集计算时按[计算接入](../engineering/execution-batches.md)选适合的路径；小型低频功能直接实现即可。
- 性能按[开发循环](../engineering/workflow/testing.md)做相关档位的历史对照，以功能价值与成本决定保留/调整。

多控/编队、自动物流、完整社会/修仙内容、无限世界与远区LOD仍是后续候选，没有自动施工顺序。[产品层次](roadmap.md)描述长期愿景，design候选中的详细验收表不作为每次开发的前置。

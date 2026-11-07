# 当前代码架构与边界：存读提交边界

## 存读提交边界

兼容方向见[当前版本与历史退役](../compatibility.md)：只维护一套当前运行模型/写档格式，历史输入仅在明确范围内转换后进入当前模型。本节记录代码实际存在的入口，不为多代迁移或旧生成器提供永久保留承诺。

[WorldSessionSnapshot](../../../scripts/runtime/world_session_snapshot.gd)在共同时刻捕获联合快照，独立候选先恢复各域，再核跨域来源/成本/位置/占用；成功后才替换活世界与呈现引用。[SessionSaveSchema](../../../scripts/persistence/session_save_schema.gd)校验根版本并明确拒绝旧环境档，[SnapshotValues](../../../scripts/persistence/snapshot_values.gd)处理JSON值，[SimSaveStore](../../../scripts/persistence/save_store.gd)负责文件备份/原子替换。

当前收尾代码写根52、区域43和含来源定义的内容包2；旧根不伪造Q到场响应的迁移。具体边界见[兼容性](../compatibility.md)与[环境合同](../world-environment-contract.md)。历史没有的知识、交易、物件和经历不能由新开局补造；当前墙门/人物位置不能证明过去的见证。同毫秒次序只能用已有序号/半开区间证明，不声称完整历史重演。围合、占地索引、缓存和纹理可重建，不作为另一份存档真值。

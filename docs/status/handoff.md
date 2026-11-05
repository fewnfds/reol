# 当前接续

核对：2026-11-05。**文档重构、分支审计、基础优先级收束已完成**。停在等待用户逐项排定下一基础包；不继续旧世界开发 Goal，不自动实施后续游戏功能。

## 本轮范围

1. 按固定设计、候选设计、工程、计划、现状、证据和历史分类，拆分大页并核验引用。
2. 解释远端五个及本地额外实验分支；只审计，不删除、合并或切换。
3. 基于实际代码提出依赖有序的小工作包，交由用户逐项排定。

本轮已完成分类/拆分、链接/锚点/目录/大小校验及分支和代码现状审计，Python 定向 20 项通过；检查器一次原生只读审查无发现。等待用户决定下一包。旧 Goal 已由用户取消；旧执行计划中的 active/下一包均失效。

## 保留的游戏半成品

起点为 `codex/world-engine` / `bbd4303eb2ae477015dd1d9a40b170562c40a4d8`。本轮开始时以下四个文件有未提交环境源/接收区/潮汐相关改动，**未在本轮测试或入库**：

- `scripts/sim/environment_field_cache.gd`
- `scripts/sim/environment_temperature_state.gd`
- `tests/sim/test_environment_field_cache.gd`
- `tests/sim/test_environment_temperature_state.gd`

本轮已在忽略的 `logs/doc_reorganization_20261105/protected.json` 记录 SHA256，收尾核对字节未变。恢复开发时先检查实际 diff，不据文档把 WIP 当已验实现。

## 最重要的实际边界

- 普通 Main 仍用旧 Q 热；新源场、温度状态和 GPU 服务尚属隔离候选。
- 查询/库存/器物/村落动作已有有限路径，通用物品生成、位置转移、堆拆与动作合同尚未完成。
- 因此优先补通用基础接缝，不再为温石或争环扩专用玩法；建议范围见 [基础优先级](../plans/foundation-priorities.md)。

当前功能看 [features](features.md)，版本/CI看 [baseline](baseline.md)，分支看 [branches](branches.md)。不在接续页复制完整规则或逐包测试历史。

## 提交与验证

文档/必要文档检查调整单独提交；不包含上述游戏 WIP，不改第三方、fixture 或原日志。文档整理不启动引擎。CI 只在真实提交检查点查询一次，不轮询、不派等待代理；本轮具体结果见 [QA](../qa/20261105_documentation_reorganization.md)。

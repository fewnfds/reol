# 当前接续

核对：2026-11-05。用户排定的第一阶段详细实施文档与首包 A（对象、能力和空间合同）**已完成**。停在包边界等待用户排定 B；不自动连做，不恢复旧世界开发 Goal，不扩玩法。首包完成不等于第一阶段完成。

## 本轮交付

- [详细阶段方案](../plans/world-foundation/README.md)：A–E 的输入、接口、验收、性能与停止点；顺序由 [基础优先级](../plans/foundation-priorities.md)统一。
- [对象与空间接口](../engineering/object-query-contract.md)：RegionalSimulation 公共只读入口读取人/鸟/大兽/器物/库存/有限资源/结构的原状态；能力声明、来源滞后和时间欠算分开；不创造第二份实体状态。
- 显式引用集空间快照支持多格/非矩形与分层、包含关系、有预算查询；只代表捕获时刻与所给集合，跨世界变更必须重建。全局revision/live索引更新、生成移除、转移和堆拆仍待后续包。
- 基准区分真实小世界接口与合成262144引用索引；不把后者当已持久化实物数量、NPC容量或FPS。

## 代码与验证

主包 `0dc5c998f1897f7c0a2ef77ab3c97eb6a251c7cc`，一次原生Sol/custom只读审查发现占地大整数缩窄溢出；修复提交 `98a65663e325d2a56279fcf99af2c4d991e25a81`，定向268项通过。修复后的完整check在独立detached检出通过 **249组/97864断言/0失败**，覆盖精确代码SHA，不包含环境WIP。首次导入因1 GiB硬限触发WebP失败的原日志保留，2 GiB新缓存导入验证后重跑通过，未修改产品凑绿。详见 [首包QA](../qa/20261105_world_object_contract.md)。

临时验证检出已核绝对路径、HEAD并保留原日志后正常移除；当前只有项目根工作树。相关本机日志和保护哈希在忽略目录 `logs/world_foundation_contract/`，不入库。

## 保留的游戏半成品

以下四份环境改动来自旧任务；本轮开始/结束SHA256一致，未提交、未混入隔离回归，恢复时先看实际diff：

- `scripts/sim/environment_field_cache.gd`
- `scripts/sim/environment_temperature_state.gd`
- `tests/sim/test_environment_field_cache.gd`
- `tests/sim/test_environment_temperature_state.gd`

普通 Main 仍旧Q热，新环境场/GPU隔离候选没有在本包接管。不要因共同查询入口存在，就将资源点称作独立植物或将数量条目当成唯一实例。

## 下一次开发

建议用户排定包 B：沿原所有者做受控创建/移除及地面—携带—容器位置变更，接局部变更通知与索引失效，再进入数量/动作合同。先明确当前可写原域和版本，不为某个宝物加专用剧情或功能。

本轮按完整SHA `42b0aa7aa6b3abe00904b73fffe8a991772be451`核过CI41973719759成功。代码/窄修/收尾文档一起推送后不另查CI；新远端head结果留到下一真实提交检查点，不主动等待、不派等待代理。版本证据看 [baseline](baseline.md)，玩法范围看 [features](features.md)。

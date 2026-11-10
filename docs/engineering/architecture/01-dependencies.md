# 当前代码架构与边界：依赖方向

本页为现存Demo的实现参考；重构目标由[执行规格](../../specs/world-engine/execution.md)定义。逻辑职责/有效规则不绑定下列class、数据结构或调用链。

## 依赖方向

顶层领域和跨域交接统一见[领域归属](05-framework-domains.md)。本页描述代码层依赖；`sim/runtime/persistence/ui`是技术分层，七个框架是领域分工，两者不互相替代。现有class可以承担某个领域的状态所有权或向其他领域提供适配，不能因文档重分领域复制原状态。

```text
main / 场景装配
  输入与UI → runtime命令适配 → sim规则/过程/状态
                ↓                 ↓
          世界/人物呈现       data定义与开局
                ↘ persistence快照/迁移/文件边界
```

纯模拟不依赖HUD或祖先 `Node` 路径。运行适配负责绑定/命令与投影，不另存身体、库存或社会余额。当前业务autoload为`GameClock`，第三方另有MCP helper；通用存读由`SimSaveSession`及纯数据参与者管线组成，未新增业务autoload或全量ECS。

现有部分领域持有[参与索引](../sparse-execution.md)，登记成员、活动和到期/变脏工作；原领域负责规则及提交。该接口用于定位旧实现，新结构可以更换数据与工作选择机制；接入程度见[技术起点](../../status/technical-status.md)。

普通`RegionalSimulation.environment_fields`指向`SimWorldEnvironmentFields`，由它作为室外实际温度及五行响应的唯一环境域。存档 `local_heat` 数据键经 snapshot codec 映射到该字段，内容定义的 `ReolContentDB.local_heat` 则是独立热设备参数。来源来自原实物，缓存只保存可重建投影；[普通世界环境合同](../world-environment-contract.md)说明边界。当前验收与接入范围见[BASELINE](../../status/baseline.md)，当前任务见[HANDOFF](../../status/handoff.md)。

普通环境域组合温度、五行响应、气候背景及目标编译组件，并复用同一共同时间；它不持有第二份实物。独立GPU/开发会话仍是不同范围的计算或测试接口，不代表普通主局已有GPU开关或后台加速。

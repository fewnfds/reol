# 当前代码架构与边界：依赖方向

## 依赖方向

```text
main / 场景装配
  输入与UI → runtime命令适配 → sim规则/过程/状态
                ↓                 ↓
          世界/人物呈现       data定义与开局
                ↘ persistence快照/迁移/文件边界
```

纯模拟不依赖HUD或祖先节点路径。运行适配负责绑定/命令与投影，不另存身体、库存或社会余额。当前业务autoload为`GameClock`，第三方另有MCP helper；未创建全量EventBus/ECS/EntityRegistry/SaveManager。

普通`RegionalSimulation.local_heat`指向`SimWorldEnvironmentFields`，由它作为室外实际温度及五行响应的唯一环境域；`local_heat`是保留的调用名称，不是并行运行的旧Q求解器。来源来自原实物，缓存只保存可重建投影；[普通世界环境合同](../world-environment-contract.md)说明边界。当前验收与接入范围见[BASELINE](../../status/baseline.md)，当前任务见[HANDOFF](../../status/handoff.md)。

普通环境域组合温度、五行响应、气候背景及目标编译组件，并复用同一共同时间；它不持有第二份实物。独立GPU/开发会话仍是不同范围的计算或测试接口，不代表普通主局已有GPU开关或后台加速。

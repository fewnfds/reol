# 工程地图

现行模拟内核位于 `scripts/sim/kernel/`，场景入口是 `scenes/main.tscn`。按改动涉及的领域查阅。

| 要查的内容 | 正文 |
|---|---|
| 运行架构、事实写入者与显示边界 | [运行架构](architecture.md) · [领域职责](architecture/05-framework-domains.md) |
| 查询范围、批处理、线程与结果采用 | [计算接入](execution-batches.md) · [复杂度与扩展范式](simulation-costs.md) |
| 共同时间、倍率与精度 | [运行与精度](simulation-pacing.md) |
| 玩法规则、因果和周期实验 | [模拟设计与实验方法](simulation-methods.md) |
| 兼容性和存档 | [存档支持](compatibility.md) |
| 运行、导出、短检查与性能采样 | [工具命令](tooling/usage.md) · [按需验证](workflow/testing.md) |
| 编辑器与技能 | [工具配置](tooling/setup.md) |
| 当前构建和实测 | [状态入口](../status/README.md) |

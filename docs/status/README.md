# 当前项目记忆

这些文件由agent主动读取，不按文件名自动注入，也不定义新的全局要求。

- [HANDOFF](handoff.md)：当前授权/停点、必要未完成项和受保护工作。完成或改变方向时覆盖旧状态。
- [BASELINE](baseline.md)：已核实版本、关键测量和对应来源。不同SHA/负载的结果不混用。
- [FEATURES](features.md)：现有操作能力，子页按玩法查询，不复制性能表或任务队列。

旧technical-status与branches已并入以上入口，不再分别维护同义总表；实际Git指针仍以Git为准。历史结果只在[archive](../archive/README.md)查，稳定约束只在[constraints](../engineering/constraints.md)维护。

# 代码入口

当前目录和事实写入者统一查[运行架构](architecture.md)。`scripts/sim/kernel`处理世界，`scripts/presentation`处理Godot画面/输入，`scripts/entities/humanoid_appearance.gd`解释已保留资源，`scripts/sim/execution/batch_execution.gd`封装引擎线程池。

场景只有`scenes/main.tscn`，导出只有Windows Demo；`tools/godot.py`统一运行/短检查/导出，`tools/benchmark.py`运行有界release采样。第三方addon不属于世界内核，不在重构中手改。旧世界和旧压力/试游启动器已移除，Git的a493bf0保留重建前实现。

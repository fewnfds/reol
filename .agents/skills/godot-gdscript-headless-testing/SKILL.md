---
name: godot-gdscript-headless-testing
description: 排查Reol短headless检查的错误退出、挂起、异步或导入问题。
---

# Headless短检查排错

验证范围和命令沿[开发循环](../../../docs/engineering/workflow/testing.md)与[usage](../../../docs/engineering/tooling/usage.md)；本技能不创建CI或新增回归流程。现有入口为`tests/smoke.gd`和`tools/godot.py`，通常直接修相关检查即可。

- 新class、资源或移动路径不被识别时按需import；不在每轮测试前重复导入。
- `push_error()`和GDScript运行错误不自动让进程非零退出。SceneTree检查显式`quit(1)`；每项返回bool并核对true，防止异常中断被当成通过。启动器同时识别错误输出。
- `_initialize()`早于autoload和节点就绪。依赖活场景时延后执行；外部SceneTree脚本可在就绪后从root取autoload，避免预加载整条运行依赖时找不到singleton。
- 裸`assert()`失败可能在执行到quit前中断函数。首个真实错误优先处理，进程设置短上限，超时记为失败而不是继续拉长等待。
- 计时器/异步检查需要已进入树及明确的终止条件；`await process_frame`让场景就绪，不用长sleep等待猜测结果。
- 收集stdout和stderr，区分引擎退出、脚本失败与超时；等待同一有界进程，不定时轮询日志。

headless能验证规则/工具路径，不能证明画面帧时或GPU采用。短smoke也不能证明完整世界与存档行为；本次改到相关边界时再选具体场景核对。

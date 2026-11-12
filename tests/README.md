# 当前短检查

`python tools/godot.py test`运行`kernel_smoke.gd`；边界与覆盖范围只查[验证方式](../docs/engineering/workflow/testing.md)。旧全玩法测试和CI已退役。

`tool_smoke.py`只在修改Python进程启动/超时时使用。性能用真实release短窗口，不用smoke通过数量代表容量。

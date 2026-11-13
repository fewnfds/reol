# 当前短检查

`python tools/godot.py test`运行`kernel_smoke.gd`；边界与覆盖范围只查[验证方式](../docs/engineering/workflow/testing.md)。旧全玩法测试和CI已退役。

`tool_smoke.py`只在修改Python进程启动/超时时使用。性能用真实release短窗口，不用smoke通过数量代表容量。

`ui_smoke.gd`按需单独运行，约数秒核对实际GUI输入、数量取放、工具取消/旋转、连续主图/小地图坐标、迷雾详情与窗口缩放，不加入kernel默认套件。图形运行将本机截图写入忽略的`logs/ui-smoke/`；不冒充全玩法人工游玩。

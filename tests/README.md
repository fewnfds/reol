# 当前短检查

`python tools/godot.py test`运行`kernel_smoke.gd`；边界与覆盖范围只查[验证方式](../docs/engineering/workflow/testing.md)。旧全玩法测试和CI已退役。

`tool_smoke.py`只在修改Python进程启动/超时时使用。性能用真实release短窗口，不用smoke通过数量代表容量。

`ui_smoke.gd`按需单独运行，约数秒核对实际GUI输入、ItemList数量取放、工具取消/旋转、连续主图/小地图坐标、迷雾详情、人物事件与百分比缩放确认，不加入kernel默认套件。图形运行将本机截图写入忽略的`logs/ui-smoke/`，缩放探针不写用户偏好；不冒充全玩法人工游玩。

`experience_smoke.gd`按需单独运行，针对普通/压力场源分离、冷热耐受/小数余量、危险中禁止恢复、战斗不吃耐受、死亡顺序、有界个人日志与存读做短反例，不扩大kernel默认套件。

# 当前验证方式

验证服务本次行为与真实性能，不按次数评价进展。旧CI、分片聚合与全玩法长回归已退役，不恢复门禁。

`python tools/godot.py test`执行`kernel_smoke.gd`及它调用的小型`feature_smoke.gd`、`sight_smoke.gd`、`equipment_smoke.gd`。512人/120步核对串并行资源守恒与合法身体位置；独立求路队列允许不同起步时刻，不把跨worker全未来相同当断言。其余小反例覆盖存读/中断、设施/环境、战斗共同提交、社会交互、观察/冻结记忆/失联、地区旅行及装备的原子位置/真实属性/缓存恢复。默认15秒进程上限，正常约十秒；容量另用release窗口，不把smoke扩成负载矩阵。

`feature_smoke`另调用短小的`tile_smoke`，复用同一世界核对自然生境、低草覆盖/取消、树桩清场/木料守恒、地板与盆栽分层和恢复、满背包清场落物、家具四向占地/外观与存读。`navigation_smoke`核对两体型窄道/转角、同格落点/原地停止、改令、在途恢复、动态墙/邻格身体、排队和时间折线扫掠，不建立另一套负载矩阵。

新脚本/资源按需import；呈现改动实际观察，性能改动用同构建同负载release短窗。`python tools/check_structure.py --audit-code`辅助查当前链接/资源/入口，动态依赖仍需判断。`python tests/tool_smoke.py`只在Python进程/超时工具改动时使用。

命令语法只在[usage](../tooling/usage.md)，结果/局限只在BASELINE。自动交互探针要标明范围，不冒充完整手动游玩；真实窗口不互相重叠争用设备。运行期间做独立工作，只剩等待就等同一进程，不反复查询无变化。

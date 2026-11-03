# 当前小世界呈现等待验收

2026-11-03，P0同适配器对照。原完整游戏Goal继续active。

独立测量使用Python subprocess等待Godot进程：`Godot_v4.7.2-stable_win64.exe --path . --script res://tools/qa/profile_game.gd --resolution 1280x720 -- source_v11_present_default`，exit0。脚本从真实v11装配、同一窗口/适配器、暖机1200ms后各采120帧，实际运行1×，另有完整静态、隐藏地形和移除主场景对照。

最终报告：`logs/profile_source_v11_present_default.json`及同名log；前一独立对照 `logs/profile_source_v11_vsync.json`。硬件RTX3060，D3D12/Forward+，原生1280×720，已加载34区块。

| 场景 | VSync开中位 / p95 | VSync关中位 / p95 |
|---|---|---|
| 完整静态 | 31.269 / 33.544ms | 8.338 / 8.370ms |
| 真正1×生活 | 31.350 / 33.294ms | 8.340 / 8.381ms |
| 隐藏地形 | 31.283 / 33.678ms | 8.333 / 8.375ms |
| 空主场景 | 31.265 / 34.175ms | 8.334 / 8.364ms |

1×期间时钟分别前进3750ms/1000ms，与各120帧墙钟耗时相符。暂停时TIME_PROCESS可能是陈旧值，报告标记 `process_monitor_may_be_stale`，不将它误作CPU剖析结论。

据此仅修改项目默认：VSync0，最高120FPS。未改全局显卡/系统配置、渲染后端或模拟精度。run71新开局真实右移+Shift，从(16416,16416)到(16592.5,16416)，节点/原身体一致，体力92；23950ms暂停，实际120FPS。记录 `logs/presentation-controls-20261103.json`，截图 `logs/presentation-controls-visible-20261103.png`。run72新开局截图 `logs/presentation-new-opening-visible-20261103.png`，复核底部面板右边1264，处于1280宽窗口内，未为未复现问题改UI。

`python tools/godot.py check`：61组/2370断言/0失败，`logs/check-test-20261103-063554.log`。实机最新启动无项目错误。临时取证eval两次调用/缩进错误已完整停开重置，不是项目代码错误。开发工具输入不存在的sidestep action被拒绝，随后用实际KEY_SHIFT复核。

限制：仅当前小世界开发进程与当前显示环境。世界规模、正式玩家设置菜单、Windows独立包和发布硬件性能仍待做。

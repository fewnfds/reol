# 当前接续

2026-11-09：用户授权的共同时间过载降速已完成实现、验证、一次原生审查及主线整合。产品/永久测试`f4257e38a1665c08c8596028fe71c0cea0dbeab9`基于main `2c4ea10723d8140c5ae4b5f4c599f156d2ea6e5b`，开发分支`codex/adaptive-world-time`已快进合入main；最终指针以Git为准。后续只同步QA驱动和当前文档，不启动植物等新领域。

## 本包出口与证据

- `GameClock`与`ReolSimulationPacing`统一管理有限未来准入、玩家倍率/负载倍率及单调宿主计时，6ms合作式预算沿runtime/区域/内核步骤让出；原事件顺序、原状态、已受理欠算、显式目标与根53/区域44保持。
- 负载降速、逐渐恢复与显示插值/HUD/F3已接普通Main。没有无限现实时间追赶；旧原子回调和GPU阻塞仍无硬实时保证。
- 最终定向8组796检查/0失败；产品同SHA的[CI42542611182](https://github.com/fewnfds/reol/actions/runs/42542611182)已核completed/success，12片完整覆盖。一次Sol/custom原生只读审查退出0、无可确认修复问题，不重复整包审查或本机全套。
- 原生人工负载实际0.162×、帧间隔P95 17.600ms；移除后准入倍率恢复1×。同进程及完全停开250ms未来SHA一致，画面已查看；具体日志/负载/限制见[QA](../qa/20261109_simulation_pacing.md)，当前合同见[运行流速](../engineering/simulation-pacing.md)。

本包采用已通过的准确产品SHA CI；其后只有现有QA工具两处零时间续算迁入`advance_frame`及Markdown。后续推送SHA/run尚未登记，不冒称已绿；仅在下一次真实提交检查点核一次，不轮询或声称CI可唤醒聊天。上轮Actions Node24代码`dc2558b`的CI42539000023已核success并缓存。

## 后续范围与保护工作

下一领域开发仍先收敛会话规则/安全存读，再以植物接入生命周期、行动及观察；顺序和出口只见[原主计划](../plans/foundation-priorities.md)，本轮未启动这些功能。

`codex/field-contest`的`4e17c5c165cf8fca9ef884a111aa1c3ca35f445f`旧根43实验及stash `424f956d280fb390d17e1f6dd879f3614b51a430`均保持隔离，不应用、不删除。凭据、本机配置、日志与临时存档不入库。

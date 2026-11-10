# 当前接续

2026-11-10：用户授权先整合Git，再单独处理Demo简单问题和缓行诊断。通用SL、全局事件/植物、环境组合及第5阶段行动历史已快进整合main，最终生产/测试`0856effd4b2bb135c9bae8f25cccbba0e3def8e0`；集成点`7def7d2`已推送main。旧`codex/field-contest`与命名stash仍隔离，不删除/恢复。准确分支以Git及[分支状态](branches.md)为准。

## 本轮整合证据

前版`0a0b59a15088f53f762bec13bc20b9145923402b`的CI42674488111已核completed/failure：第5片旧感知直行断言、第11片休息界面漏认`sleep`，不是超时。两项本机原代码复现；收尾修复显示映射，并以相同已知线索、不同隐藏坐标的独立世界比较，允许合法绕墙且防止全知追踪。休息/服务运行2组88检查、最终感知108检查通过；不是完整回归。

0856eff仅两文件，一次Sol/custom原生静态主审因宿主命令故障接续同一会话`01a1c385-40f3-74f1-bac7-bb3cd069795e`，提供准确diff/源码完成，无可操作发现、退出0。日志`logs/unit-actions-integration-review-resumed.log`。主体原审查与原生停开证据不重复，见[行动QA](../qa/20261110_unit_actions.md)。

最终代码run **42750266714** / SHA `0856effd4b2bb135c9bae8f25cccbba0e3def8e0`在本次试玩修复提交检查点已核**completed/success**，完整CI通过。整合点7def7d2较该SHA仅Markdown差异。没有活测试或审查handle，没有GitHub结果→聊天自动回调；终态缓存复用，不轮询。

## 正在执行的Demo反馈

当前独立分支`codex/demo-playtest-fixes`，不混入已推送main的整合历史。已实现并原生验看：人身自动跟随及F恢复跟随、预置房间中心格未探索导致眼前外墙不画。后续缓行只补能采样定位原因的诊断，暂不改结算频率/预算。诊断入口与正式修复分开提交，不向规则代码散布临时print或测试负载。迷雾连续坐标呈现先按范围判断，不以简单提高逐格更新频率冒充平滑解决。

最近普通试玩`logs/run-20261110-111202.log`仅启动信息，无脚本报错或缓行过程数据；F3现有倍率/欠算/时钟耗时不落盘。此前旧QA普通短样本约0.51×，不是当前稳定负载结论。当前未连接可读Godot AI会话，不停止/覆盖用户正在玩的进程或存档。

根56/区域47/内容包3/环境5，只支持当前格式，旧原档保留。试玩操作见[体验链](features/playthroughs-and-gaps.md#第一次试玩建议)。本轮不自动开展第6阶段、完整战斗或发行工程；唯一建设计划仍为[foundation-priorities](../plans/foundation-priorities.md)。

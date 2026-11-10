# 当前接续

2026-11-10：本轮用户要求“先合并前阶段；简单Demo问题先修；缓行能定位即可；debug单独写”。已完成并推送，当前干净分支`codex/demo-playtest-fixes`；前阶段与本包分开，**本包未合main**。没有活测试/审查handle，不开CI等待器。详见[本包QA](../qa/20261110_demo_feedback.md)。

## 主线集成

通用SL、全局事件/植物、环境组合及第5阶段行动历史快进合入main `7def7d2f40e3584dfe6c455b6280d894a455a9e3`，其CI42751032965已核completed/success；最终游戏代码`0856effd4b2bb135c9bae8f25cccbba0e3def8e0`的CI42750266714也为success。旧CI42674488111的两项失败已先复现后修复：休息界面识别sleep，感知测试允许绕墙而以不同隐藏坐标同路径比较防全知；休息/服务2组88检查、最终感知108检查通过，一次Sol/custom静态主审完成。准确历史见[行动QA](../qa/20261110_unit_actions.md)。

旧`codex/field-contest`=`4e17c5c165cf8fca9ef884a111aa1c3ca35f445f`及命名stash`424f956d280fb390d17e1f6dd879f3614b51a430`保持隔离，不恢复/删除。当前根56/区域47/内容包3/环境5，只接受当前格式，旧原档保留。

## 本包交付

- 简单修复`87262ffe5216da2d88afe4a2e8ba87ec20dfa1db`：默认持续跟随人身，F一次恢复、方向键/中键自由平移；预置房间按格显示外墙，不因室内中心未知而整房不画，隐藏门/房名/室内仍不泄露。4组112检查、原生截图与跟随输入探针通过，一次Sol/custom静态主审无发现。同SHA CI **42751769110 completed/success**。
- 独立诊断主体`fff597619bcd89ced71eb186543e4effd116c8fa`，审查修复最终`aa4f1a1fb893ed908281deda81fc2696659b3ea6`：`python tools/diagnose_demo.py --seconds 120`启动可玩新进程，自动有界采样、关闭落盘，采样停止后继续玩。代码只在tools/diagnostics和QA入口，普通Main不加载；不改频率、预算、规则或存档。报告为logs/demo-profile-*.json及同名JSONL，记录各原结算步骤、运行层剩余、倍率/欠算及迷雾/加载标记。
- 一次Sol/custom静态主审的等候CPU漏计P2已先红后绿修复；同一会话`01a1c39c-9879-7d40-bc24-a4c57dee682e`完成后退出。独立QA存档250ms整个world/clock/motion未来在包装/加载新内核后相同，结束恢复全部原Callable。headless有界smoke和原生20秒及最终2秒均通过；没有注册额外永久Main慢组。

20秒原生样本约0.829×、最低rate0.269，开局加载后约9秒恢复1×，后段每现实秒约1000游戏毫秒。较重callback包括consider:clothing、previous:environment_fields、field_opportunities；这只是带诊断开销的开局样本，不能认定用户移动/交互缓行根因。记录路径及范围在QA；下一次可用诊断入口实际试玩。连续坐标迷雾仍未实现，本轮没有用提高逐格频率代替它。

## 最终待验与后续

最终诊断代码run **42753794423**已在本次文档提交检查点一次查找登记，headSha精确为aa4f1a1，观测**pending**，完整CI待验。下个真实提交点用`python tools/ci.py status --run 42753794423 --sha aa4f1a1fb893ed908281deda81fc2696659b3ea6`核一次；前版工具run42752959149先前in_progress，不能继承为最终通过。无时间轮询，无GitHub结果→聊天自动回调；已终态旧run复用缓存。

后续按用户试玩反馈推进；本包不自动合main，不启动第6阶段、完整战斗或发行工程。唯一建设计划仍为[foundation-priorities](../plans/foundation-priorities.md)。

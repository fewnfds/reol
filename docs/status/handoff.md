# 当前接续

2026-11-10：当前`codex/demo-slowdown-fix`承接严重缓行修复，补用户要求的原生FPS显示。顶部常显FPS、帧间隔/2秒窗峰值及世界流速，F3保留详情；一组17检查及真实画面/按键/暂停只读验证通过。实测渲染约110–120FPS，但玩家位置仅约20次/秒变化，明确缺少显示插值，不能用开局流速近1×证明流畅/规模达标。本次不改移动规则。FPS最终代码`ac3dca32ffd8b3e6b7eda47c4efb756c8941e473`已推送，一次Sol/custom原生静态主审无可操作发现，完整CI待验；前Demo包均未合main，没有活引擎或测试handle。详见[QA](../qa/20261110_demo_feedback.md#fps显示与呈现频率核对)。

## 主线集成

通用SL、全局事件/植物、环境组合及第5阶段行动历史快进合入main `7def7d2f40e3584dfe6c455b6280d894a455a9e3`，其CI42751032965已核completed/success；最终游戏代码`0856effd4b2bb135c9bae8f25cccbba0e3def8e0`的CI42750266714也为success。旧CI42674488111的两项失败已先复现后修复：休息界面识别sleep，感知测试允许绕墙而以不同隐藏坐标同路径比较防全知；休息/服务2组88检查、最终感知108检查通过，一次Sol/custom静态主审完成。准确历史见[行动QA](../qa/20261110_unit_actions.md)。

旧`codex/field-contest`=`4e17c5c165cf8fca9ef884a111aa1c3ca35f445f`及命名stash`424f956d280fb390d17e1f6dd879f3614b51a430`保持隔离，不恢复/删除。当前根56/区域47/内容包3/环境5，只接受当前格式，旧原档保留。

## 本包交付

- 简单修复`87262ffe5216da2d88afe4a2e8ba87ec20dfa1db`：默认持续跟随人身，F一次恢复、方向键/中键自由平移；预置房间按格显示外墙，不因室内中心未知而整房不画，隐藏门/房名/室内仍不泄露。4组112检查、原生截图与跟随输入探针通过，一次Sol/custom静态主审无发现。同SHA CI **42751769110 completed/success**。
- 独立诊断主体`fff597619bcd89ced71eb186543e4effd116c8fa`，审查修复最终`aa4f1a1fb893ed908281deda81fc2696659b3ea6`：`python tools/diagnose_demo.py --seconds 120`启动可玩新进程，自动有界采样、关闭落盘，采样停止后继续玩。代码只在tools/diagnostics和QA入口，普通Main不加载；不改频率、预算、规则或存档。报告为logs/demo-profile-*.json及同名JSONL，记录各原结算步骤、运行层剩余、倍率/欠算及迷雾/加载标记。
- 一次Sol/custom静态主审的等候CPU漏计P2已先红后绿修复；同一会话`01a1c39c-9879-7d40-bc24-a4c57dee682e`完成后退出。独立QA存档250ms整个world/clock/motion未来在包装/加载新内核后相同，结束恢复全部原Callable。headless有界smoke和原生20秒及最终2秒均通过；没有注册额外永久Main慢组。

## 严重缓行修复

`WorldContinuityRuntime`在完整时钟发布时集中捕获canvas，普通观察者不再反复构建；暂停/可见性/读档仍立即更新。植物捕获复用一次运行/视野上下文。`SimWorldEnvironmentFields`复用原批处理handle，按16格工作项、内核同一宿主截止条件续算，完成后才放行后续领域。`ReolSimulationPacing`按250ms游戏时间窗口的累计工作/时长估算，避免1ms边界将固定发布成本放大；保留已受理欠算和恢复斜率。衣着先筛当前有资格的决策，再计算一次选择。未改6ms预算、业务频率、阶段顺序或存档格式，临时探针均在忽略的logs。

用户96秒样本0.808×、最低rate0.093、缓行49.536秒、时钟最大97.893ms。最终同一5秒headless负载CPU3179→2282ms（约-28%）；90秒原生自动人身0.986×、缓行4.764秒、时钟最大17.645ms、帧P95 14.057ms；30秒真实Input移动39格、0.968×、无world_errors，截图已查。用户操作样本与无人输入样本不混作严格同路径。环境callback仍有14.293ms，加载及来源/房间/拓扑仍含同步原子部分，不声称6ms硬实时或满密度验收。

定向5组344、4组426、调速1组20检查均通过，短片段误降速反例先红后绿；环境预算1恢复与无界字段锚点及后续未来完全一致，内核域内截止条件/后续阶段不早跑、pending旧画面和暂停同毫秒刷新已覆盖。审查主体081b56c在同一会话`01a1c3bd-2195-7081-b187-a6a694f8b1c7`静态核查完成，P2灵体读档flora回调仍绑旧owner已修；真实save/load反例先失败、修复后1组42检查通过。准确日志见QA。

## 最终待验与后续

原诊断aa4f1a1的CI42753794423及缓行修复最终生产/测试`b364870e5ddc92f3c3de2d689fcf3e2755e8d67d`的CI **42757726701**已核completed/success，完整回归通过。FPS最终代码`ac3dca32ffd8b3e6b7eda47c4efb756c8941e473`已推送；其CI **42759378487**在本次真实文档提交点一次发现为**in_progress**，headSha精确相符，当前FPS包完整CI待验。下次真实提交点用`python tools/ci.py status --run 42759378487 --sha ac3dca32ffd8b3e6b7eda47c4efb756c8941e473`核一次，不继承旧版绿色。无时间轮询，无GitHub结果→聊天自动回调。

FPS包在原生会话`01a1c3d0-baff-7801-b6f0-12057b2d7ba6`完成一次静态主审；日志`demo-fps-review.log`，未另启引擎/测试。当前待补的移动显示插值与人口规模验收归原行动呈现/共同运行框架，本包只提供真实可见指标，未启动这些后续代码。

后续按用户试玩反馈推进；本包不自动合main，不启动第6阶段、完整战斗或发行工程。唯一建设计划仍为[foundation-priorities](../plans/foundation-priorities.md)。

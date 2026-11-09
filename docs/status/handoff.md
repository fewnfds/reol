# 当前接续

2026-11-10：用户授权唯一主计划第5阶段**完整单位行动与交互**，希望尽快形成可试玩Demo。当前分支`codex/unit-actions-integration`，起点`337ea13e6bfb89321d2fda9eef26f5612dc65cd9`；实现及定向/原生验收已完成，准备提交与一次原生静态主审，完整回归待最终SHA。移动、接近、占用、中断及共同时间由工作/交互/战斗复用，各域持原效果与成本；本阶段不包含完整致死战斗、掉落及平衡。不自动合main。

已接原生AStar2D、连续路线受阻重评、共同动作投影/终态/取消及原services库存搬运。恢复7组2277检查、运行接缝9组822检查、最新搬运/建筑/战斗5组449检查通过；普通Main及独立停开检查点/交付未来一致，有限工作→战斗和气弹已验。根56/区域47。最终表单原生/独立停开均退出0、无失败，时间和停止按钮可用。无活测试/审查handle，无CI等待器；主审期间不改目标提交，修复另步。

第4阶段最终HEAD的CI已核：SHA `337ea13e6bfb89321d2fda9eef26f5612dc65cd9` / run `42659346260` **completed/failure**，11片通过，test(1)失败。真实首错为`test_world_persistence`恢复后local_heat的两个initial浮点末位漂移，本包沿原owner已修并定向验证，未放宽断言；诊断在`logs/environment-ci-42659346260-failed.log`和同名artifact目录。终态已有缓存，不再轮询。

## 前阶段承接证据

原`SimWorldEnvironmentFields`接建筑/岩地材质传播、覆顶房间均温及分合连续性、库存/携物/箱体来源、手动/格路实际跨格时刻、植物自然/人工照明及原codec恢复校验。复用Godot场景/signal/呈现、原结算/事件/空间/通用SL，没有第二份原物、房温或世界引擎。当前根55/区域46/环境5/composed_fields_v1，内容包3；旧根1–54明确拒绝，原fixture/用户档保留。

doctor/import、修复后22组3761检查定向、普通Main及独立停开同未来通过；6株180帧P95 16.753ms，不代表密集整机目标。一次Sol/custom主审两项P2已修并补反例，详见[本包QA](../qa/20261109_environment_composition.md)。主体完整check曾3600秒超时并有失败；不能算当前整包完整通过。

前阶段证据不等于本轮第五阶段通过。不要推送后立即查找/轮询，不运行`ci.py wait`。当前没有CI→聊天自动回调，不声称会唤醒。

唯一建设计划仍为[foundation-priorities](../plans/foundation-priorities.md)。第五阶段已获本轮用户授权；第六阶段共同认识不是自动扩域授权，不恢复旧Goal/队列，不重复整包模型审查。

## 承接证据与保留

事件/植物最终生产`45f140b90aa1fb6d4adbf3d028efac12ae25aa9c`、测试`13d675e6f49be9ebe42a3bd958d9d8ff3be6266b`，CI42596694569在本包提交检查点复用completed/success缓存，256组126555检查；不验证本轮环境代码。通用SL最终生产`d682e030a5e28dfd04a5101bb5f826e37958422b`已在本分支历史。

main保持`f63844b3cd18f92624f58de3749b1fbbcdd32fdd`。旧`codex/field-contest`=`4e17c5c165cf8fca9ef884a111aa1c3ca35f445f`和stash`424f956d280fb390d17e1f6dd879f3614b51a430`保持隔离；不改用户配置/凭据。

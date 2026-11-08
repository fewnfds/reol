# 当前接续

2026-11-09：当前共同结算阶段已完成实现、审查修复、完整验证及代码推送，证据和当前状态已同步。`codex/settlement-kernel`基于main `a4fb83a6c29e3203bf71fc1c1f950afe4906830b`；最终产品代码`d99ac6492ad5dbe5ba1af5bcc00171b5753c28e4`，最终测试提交`38606ea342f09e5aadcb50112df6620ddafbe10f`。分支已推送、尚未合并，不启动植物等新领域。

## 阶段出口

- `SimSettlementKernel`编译阶段/依赖、查询原owner的到期边界并保留预算游标；`SimWorldSettlement`装配40个步骤、8个阶段。原状态归各领域，接口及限制见[共同结算合同](../engineering/settlement-contract.md)。`SimFacilityUse`按实际活动项续算，其余旧原子回调未自动可抢占，不能据此保证全世界单帧工作上限。
- 普通停止入口、施工通知/呈现、FAILED终态及导入失败短路已修。`d99ac6`进一步让`CommittedWorldCanvas`在完整公共时钟发布时同步捕获，延后的`_draw`只回放；pending/FAILED的即时命令notice与世界事实分开。内部索引即时失效保留，帧间合法旧档仍由独立候选恢复，根53/区域44不变。
- 完整12片终态通过：251组、125351检查、0失败，12个包装器退出0、覆盖聚合退出0，1554份输入身份前后一致。产品、注册表与共享fixture未变；三个独立suite修正按Git差异和选组核定影响，受影响4/7/9片完整重跑，未受影响报告有明确复用依据。交付证据目录为`logs/settlement-close-delivery-full-20261109/`，详细版本/报告归属只见[本包QA](../qa/20261108_settlement_kernel.md)。
- Python完整73项、最终6组定向782检查/0失败，原生Main停开同未来、施工部分/完整发布，以及预算1连续公共时钟/画布一致验证均已完成。原内核主要审查及收尾差异审查已完成，2个有效P2已修并验证，不重复审查整包。普通开局帧时仅为声明样本，不是密集世界或16GB整机验收。

## 待集成与CI限制

`codex/settlement-kernel`已推送，本阶段在声明范围内收尾。不再启动相同本机回归或自动合并main。CI已配置12片，推送后的对应SHA结果及真实GitHub墙钟仍待验；本机完整通过不冒充远端结果。只在真实提交检查点核CI，不启动推送后轮询。

下一完整领域仍是**植物实例与自然过程**，当前不启动。七领域＋共同合同方向、接入检查和框架出口统一见[唯一主计划](../plans/foundation-priorities.md)；成熟项目依据归[现有研究页](../../design/research/colony_sim_architecture.md)，不另建施工队列。

## 主线与保护工作

建筑及共同空间已在main，证据见[BASELINE](baseline.md)。此前主线`eb330ee9c38fa3a5cc72004372ddeefd70409b1e`的[CI42473540525](https://github.com/fewnfds/reol/actions/runs/42473540525)已核completed/success；不重查，也不把它当当前分支CI。

`codex/field-contest`的`4e17c5c165cf8fca9ef884a111aa1c3ca35f445f`旧根43实验及stash `424f956d280fb390d17e1f6dd879f3614b51a430`均保持隔离，不应用、不删除；来源见[分支页](branches.md)。Context7认证使用环境变量及Git忽略配置，仓库不含key。

当前无待接续的本地长验证；目前也没有GitHub完成后自动唤醒聊天的回调。

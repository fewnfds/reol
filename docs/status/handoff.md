# 当前接续

2026-11-07：用户授权完成世界引擎必须收尾、验收后合并main并推送，然后停止开发讨论流程。现有同范围Goal active；实施分支 codex/world-engine-finish，工作树 logs/world_engine_finish/dev。首代码 `d3b67a59ea11a87c4482da239649f87944cee609` 已提交/推送；原根工作区四WIP与备份哈希一致，不混本包。

普通Main已用唯一 SimWorldEnvironmentFields，旧Q不再普通运行；调度目录、原物/材料/设备来源事务、人体/野药消费者、当前联合存档52/区域43/bundle2已接。旧根1–51明确拒绝，不改原档；旧开发双场会话已禁止绑定。完整范围看[计划](../plans/world-foundation/finish-and-merge.md)、[合同](../engineering/world-environment-contract.md)。房温/隔热、携物场/尾迹、GPU玩家开关不在本包。

已验：doctor4.7.2；主要新场/保存边界/既有引物3组761断言0失败；四组业务676断言0失败；普通Main双独立进程环境/实物/在途及继续结果相同；单3060真实F8/材料五行截图与600帧普通联合负载完成；Python57项通过。新源仍同步局部事务，生成/材料操作约0.22秒卡顿边界已记录。详情见[本包QA](../qa/20261107_world_engine_finish.md)。

主要原生Sol/custom静态审查已完成（目标d3b67a5，logs/finish-native-review.log），3个有效发现：注册测试仍用旧Q接口、有限设备stored_q未按启停历史核对、末1Q光照仍额定值。主代理已修生产校验/尾光和对应测试；无第二整包模型审查。

完整check-02因上述真实问题主动停止，不算通过；已暴露 artifact_heat_methods 的默认JSON小数截断、climate_background 的旧瞬时气温期待、demo强求远区必惰性，两者业务测试已按新连续场移植，前者采用与正式文件相同的full_precision。另修历史local_conditions混用今日场与过去背景的问题，过去查询明确unknown。最终修复回归状态见下一段。

定向修复全部通过：review-fixes-01 3组409断言、review-fixes-02 7组1623断言、review-fixes-05 2组436断言，均0失败。强来源存读验证另修真实装配缺口：候选的_contained派生索引尚未重建，来源装配改为一次读取原受管身份，不能漏掉固定容器中的受管实物。最初强来源fixture绕过生命周期的错误也已改成真实受控生成；没有删除坏候选校验。当前修复提交 `50af9b687c05ab7a63f122aa6d4cc8c877ea595c` 已推送。完整check-03已结束：238组通过/22断言失败/124683断言，另有武器测试失败后的脚本错误，不可合并。失败集中为漏退役v40成功重放、测试活场后插物/迟绑定地图、StringName新键及借用未告知看守。只修相应测试装配，不放宽生产候选校验；主代理统一定向后再完整验收。

本包首代码远端CI已登记run42334182609，完整SHA d3b67a59ea11a87c4482da239649f87944cee609，在本次真实提交检查点为in_progress；不轮询。后续修复产生新SHA，不能沿用旧版CI证据。修复提交50af9b6的CI本次真实检查点登记run42335595169，完整headSha匹配、in_progress，留待下次提交检查；main仍未合并。

用户最新存档提问已核实并调研：当前是世界状态快照，使用Godot内置FileAccess/JSON，不重放全部事件。官方能力和两个插件取舍已录入[存读边界](../engineering/architecture/04-persistence.md)；不安装插件或重写格式。暂停→结清当前步→保存→恢复是可采用的简洁操作，当前save_game仍忙则拒绝，未自动编排。四原WIP已核哈希后保存命名stash `424f956d280fb390d17e1f6dd879f3614b51a430`，逐字备份与元数据仍在logs/world_engine_finish/protected-wip；不自动应用到新主线。

子代理测试整理已结束；功能文档代理仅改status/features。旧算法/旧根成功迁入测试退役及当前替代业务见[登记](../qa/legacy-environment-regressions.md)。先前原文完整见[历史接续](../archive/status-20261107-before-field-finish.md)，不自动沿旧性能Goal扩任务。

定向current-fixes-01：屋顶、地形、当前借用3组1530断言0失败；借用单次诊断证实看守警告升级取消任务，测试改为复用真实当面解释借条后再开始。私交/武器和共用fixture已修为普通开局先装配实物再激活场；私交与共用连续性在02各自通过，03武器/原物2组267断言0失败。下一步在已提交当前修复上最终完整check，不能沿用03的失败结果合并。

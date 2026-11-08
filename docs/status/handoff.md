# 当前接续

2026-11-08：用户最新明确要求在可停点暂停，准备切换模型继续。当前不启动新开发、审查、推送或后续测试分片；保留本轮共同结算框架和CI12片工作。当前`codex/settlement-kernel`基于main的`a4fb83a6c29e3203bf71fc1c1f950afe4906830b`；实现提交`79d4543c532b5fc1e0a99dbd8b804b71ea6f6d38`完成一次原生审查，最终生产代码为`b29385c30dc72e8942eef803d781e526e4093986`，测试fixture适配提交为`68fa8d38c5dbafdb13974d42f4dcbb527dc4ede6`；本包未推送，也未合入main。

## 本轮范围与接续

- `SimSettlementKernel`编译阶段及依赖、查询原owner的到期边界并保留工作预算耗尽时的游标；`SimWorldSettlement`按原同刻规则装配40个步骤、8个阶段。身体、库存、环境及共同时间各归原owner。[共同结算合同](../engineering/settlement-contract.md)记录接口、顺序和限制，已有[唯一主计划](../plans/foundation-priorities.md)原位补充横向框架。
- `RegionalSimulation`和普通runtime接入部分边界续算：未结清时不发布时钟，外部行动、共同对象查询及保存/恢复受保护；`SimFacilityUse`按真实活动工作逐项续算。根53/区域44格式未改。其他旧领域原子回调及内部大循环尚未自动可续算，不能据此宣称全世界单帧工作有上限。
- 修复代码`b29385c`的原生Main预算1与不限预算整个未来一致，完整停止游戏进程后重新加载的checkpoint及随后5000毫秒未来一致。RTX3060普通开局原生600帧间隔P95 15.126ms、P99 15.529ms，测量结束无积压；只证明该样本，细节见[本包QA](../qa/20261108_settlement_kernel.md)。
- 实现提交已有5组定向测试730检查/0失败。一次Sol/custom审查发现2项P2：跨续算观察通知可能丢失、设施外部取消绕过部分边界屏障；均已修复，相关两组203检查/0失败且包装器退出码0。修复保留视图baseline与地区通知债直到完整发布，成功load清除派生观察标记；同类外部取消屏障已沿18个领域19个公开入口及`RegionalSimulation.interrupt_occupation`接齐，内核内取消仍可执行。
- CI已由4片改为12片，覆盖聚合及漏片反例验证通过；Python完整72项通过，GitHub真实耗时待验。首轮地理fixture假设同步完成而失败，保留日志后已修；长跨度领域/存读fixture明确无界host预算，地理样本继续以默认预算有界续算，专项时钟预算仍为1。
- 已按用户最新要求暂停。最终测试提交`68fa8d38c5dbafdb13974d42f4dcbb527dc4ede6`的1/12、2/12、3/12均完整通过、包装器退出0；3/12结束后已无当前测试/引擎/审查进程，4–12片未启动。协调器仅因用户暂停而停止，当前worker自然完成，`pause-boundary.json`记录退出0。
- 恢复时复用`logs/settlement-kernel-shards-final-20261108/`前三片原证据；从4/12起按同一测试代码继续顺序check，各片使用唯一报告路径并保留包装器退出，最后`python tools/check_test_reports.py logs/settlement-kernel-shards-final-20261108 --shards 12`聚合。原一次性编排脚本从第1片开始且拒绝覆盖，不能直接重跑；应明确续跑4–12片。未完成其余9片与完整覆盖聚合前不称全套通过。
- 后续仍需处理若有失败、补最终QA/状态并推送`codex/settlement-kernel`；不自动合并main、不重复整包模型审查、不启动CI轮询。当前只有暂停证据文档收尾；产品、测试均已提交，未推送。

## 主线与保护工作

建筑阶段已合入main；准确建筑代码`d00bac954b69cab096d580db002fb04013fa2543`的250组/126290检查/0失败与同SHA CI42457788038 success记录见[BASELINE](baseline.md)。此前主线`eb330ee9c38fa3a5cc72004372ddeefd70409b1e`的[CI42473540525](https://github.com/fewnfds/reol/actions/runs/42473540525)已在本轮真实提交准备检查点一次核completed/success；它不证明当前结算内核包已通过。

`codex/field-contest`的`4e17c5c165cf8fca9ef884a111aa1c3ca35f445f`旧根43实验及stash `424f956d280fb390d17e1f6dd879f3614b51a430`均保持隔离，不应用、不删除；来源见[分支页](branches.md)。Context7认证使用环境变量及Git忽略配置，仓库不含key。

本地长验证只剩等待时由一次工具编排持有同一handle到终态，模型不按时间续查、数PASS或估进度。CI仅在真实提交准备检查点集中核一次，推送后不立即查询/等待；目前没有GitHub完成后自动唤醒聊天的回调。

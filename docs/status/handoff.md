# 当前接续

2026-11-08：用户授权实现共同结算框架，参考Godot和成熟模拟项目，以可扩展、性能和原领域所有权为边界；最新追加建议是增加CI并行分片以缩短等待。当前`codex/settlement-kernel`基于main的`a4fb83a6c29e3203bf71fc1c1f950afe4906830b`；实现提交`79d4543c532b5fc1e0a99dbd8b804b71ea6f6d38`已完成一次原生审查，修复尚待提交；本包未推送，也未合入main。

## 本轮范围与接续

- `SimSettlementKernel`编译阶段及依赖、查询原owner的到期边界并保留工作预算耗尽时的游标；`SimWorldSettlement`按原同刻规则装配40个步骤、8个阶段。身体、库存、环境及共同时间各归原owner。[共同结算合同](../engineering/settlement-contract.md)记录接口、顺序和限制，已有[唯一主计划](../plans/foundation-priorities.md)原位补充横向框架。
- `RegionalSimulation`和普通runtime接入部分边界续算：未结清时不发布时钟，外部行动、共同对象查询及保存/恢复受保护；`SimFacilityUse`按真实活动工作逐项续算。根53/区域44格式未改。其他旧领域原子回调及内部大循环尚未自动可续算，不能据此宣称全世界单帧工作有上限。
- 修复前原生Main预算1与不限预算的整个未来一致，完整停止游戏进程后重新加载的checkpoint及随后5000毫秒未来一致。RTX3060普通开局原生600帧间隔P95 17.348ms、P99 21.257ms，测量结束无积压；只证明该样本，细节见[本包QA](../qa/20261108_settlement_kernel.md)。
- 实现提交已有5组定向测试730检查/0失败。一次Sol/custom审查发现2项P2：跨续算观察通知可能丢失、设施外部取消绕过部分边界屏障；均已修复，相关两组203检查/0失败且包装器退出码0。修复保留视图baseline与地区通知债直到完整发布，成功load清除派生观察标记；外部设施取消被拒绝，内核内取消仍可执行。
- CI已由4片改为12片，覆盖聚合及漏片反例验证通过；Python完整72项通过，真实GitHub耗时待验。还需固定修复代码SHA，在该代码上重新验证原生Main完整停开及12片顺序完整check/覆盖聚合，记录证据后提交、推送。具体工具进程和待验点随执行更新。

## 主线与保护工作

建筑阶段已合入main；准确建筑代码`d00bac954b69cab096d580db002fb04013fa2543`的250组/126290检查/0失败与同SHA CI42457788038 success记录见[BASELINE](baseline.md)。此前主线`eb330ee9c38fa3a5cc72004372ddeefd70409b1e`的[CI42473540525](https://github.com/fewnfds/reol/actions/runs/42473540525)已在本轮真实提交准备检查点一次核completed/success；它不证明当前结算内核包已通过。

`codex/field-contest`的`4e17c5c165cf8fca9ef884a111aa1c3ca35f445f`旧根43实验及stash `424f956d280fb390d17e1f6dd879f3614b51a430`均保持隔离，不应用、不删除；来源见[分支页](branches.md)。Context7认证使用环境变量及Git忽略配置，仓库不含key。

本地长验证只剩等待时由一次工具编排持有同一handle到终态，模型不按时间续查、数PASS或估进度。CI仅在真实提交准备检查点集中核一次，推送后不立即查询/等待；目前没有GitHub完成后自动唤醒聊天的回调。

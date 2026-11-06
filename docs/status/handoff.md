# 当前接续

核对：2026-11-06。用户已授权[环境初建有限优化](../plans/environment-object-loop/cold-build.md)，在`logs/environment_cold_build/dev`干净检出实施，无活动Goal。采用来源块逐通道局部上界，保留原整数场规则和候选；四份原WIP未纳入。6组定向10039断言0失败；同参数128²来源装配616.837→680.920ms、CPU基础场14040.694→2750.896ms，工作量36053348→8856520。512²递增规模正在验收，最终完整回归与一次原生审查尚待完成；不提前宣称全包通过。

此前[成熟模拟游戏调研](../../design/research/large_simulation_optimization.md)已完成；本包只落实CPU基础场初建，不扩存档格式、普通Main、携行/房间或玩法。大档编码/校验/I/O优化仍为后续独立候选，不自动连做。

此前[来源候选与大档内存优化](../plans/environment-object-loop/optimization.md)已按限定范围完成并停下讨论。最终代码`8ce9e031e03d706285a5bce2b5657ec4bf30d22e`（首代码992acf0）已整合/推送到`codex/world-engine`，四份原WIP字节不变、不纳入验收。14组定向25944断言0失败；一次Sol/custom原生静态审查P2已修。收尾提交检查点一次核得对应[CI42181067921](https://github.com/fewnfds/reol/actions/runs/42181067921)为completed/success、完整headSha一致：268组/134155断言/0失败，Python57项通过；本机不再重复整套。

最终512²、262142真实材料堆+1实物、半径16、32次单源变更与独立候选完整存读通过，同10GiB守卫内峰工作集5.734GiB（采样private5.884GiB）。单变更p50 0.244s/p99 0.350s，比旧p99 3.634s明显下降；累计CPU成本仍不足以代表20Hz大量携源。文件217.8MB，写137.3s、读85.1s、stage103.5s、重建599.4s；环境初建576.9s，来源/基础缓存占550.9s，仍很慢。首轮新文件在原物恢复OOM的失败保留，随后原账本材料紧凑回执才使同守卫复测通过，不提高预算凑绿。目标编译、packed列、流式文件及中断恢复合同见[接口](../engineering/environment-response-contract.md)，完整证据看[优化QA](../qa/20261106_environment_optimization.md)。

最终代码RTX3060真实渲染、两进程完整停开到同一9000ms未来，以及64²基础目标GPU全格参考/局部变化均通过。30份代码指纹一致。所有引擎/审查/基准已结束；隔离检出`logs/environment_optimization/dev`日志保全到`logs/environment_optimization/validation-artifacts/`后移除，不维持第二套运行模型。普通Main仍用旧Q；携行、材料环境事务、房间、生物后果未扩。

本包后停点：后续先讨论来源/基础缓存全域初建和大档加载速度，而非直接扩玩法或宣布普通接管。多件同强源持续移动的吞吐、16GB整机全系统负载仍未验；不自动沿旧Goal/旧QA连做。

## 前包与证据入口

本轮起点为d4ea4df；此前连续响应功能代码98e7135/0d8c035已验，失败和限制保留在[前包QA](../qa/20261105_environment_response.md)，不将其中“下一步/未优化”理解为本轮仍未实施。普通Main与开发会话的区别仍适用；新优化实际范围按本页首段、BASELINE及本轮QA解读。

## 已完成基线与边界

- 第一阶段A–E按声明范围完成：原身体/物品/库存/账本与整数毫秒唯一，统一对象/空间查询、受控生成/位置/数量、耗时动作、候选存读、普通Main离返/完全停开及有限规模出口。见[联合出口QA](../qa/20261105_world_foundation_exit.md)。大型动态体仅1/4/8，不外推全世界NPC。
- A1真实地面来源投影 `8bf7aa2a012af393fbc1b96fea6220aa18825833` 完整check255组/98618断言0失败；后续CI42008084331准确SHA成功。
- A2a来源缓存修复 `3636dc37ea498fa1f57c1d970fca6e50289aff93` 完整check257组/99000断言0失败；CI42026400068准确SHA成功。
- GPU接入修复 `9b3e724ce7e405d01b885e9b3e477b8afa09b226` 独立检出完整check258组/107976断言0失败，1105.781s，无ERROR/SCRIPT ERROR；一次Sol/custom审查的无关背包转账重启计算问题已修。3060的10案例6144格43008通道通过。512²满密度/半径16基础目标CPU20.65s、GPU0.616s，来源装配仍7.4s，不是Main FPS或动态每50ms全图更新证据。见[计算QA](../qa/20261105_environment_ground_compute.md)。

原性能/失败/审查证据在各QA链接及 `logs/environment_a1/`、`logs/environment_a2/`、`logs/environment_ground_gpu/`；历史独立检出已保全日志后移除。GPU修复SHA最近一次真实方案提交检查点只查到无匹配run，不称CI通过；本机同SHA已完整验收。CI只在真实提交检查点查一次，未终态留待下次，不按时间轮询。

## 必须保护的原WIP

原始SHA256在主工作区 `logs/world_lifecycle/protected.json`。下列四份不属于本包，保持字节不变，不混入提交或准确SHA回归：

- `scripts/sim/environment_field_cache.gd`
- `scripts/sim/environment_temperature_state.gd`
- `tests/sim/test_environment_field_cache.gd`
- `tests/sim/test_environment_temperature_state.gd`

本包只复用它们已提交的HEAD接口。若未来需要修改，先重述范围并明确保护/整合办法，不能偷偷纳入已有草稿。

## 当前概念与后续边界

- 方格地图/建造＋原人物权威子格位置＋按格环境缓存；不恢复全对象强制格心/移动纯动画结论。未来携源可按权威跨格时刻切换，实际驻留留下环境残留；当前只做到期瞬时转移，不假称走路尾迹。
- 五行逐通道max；冷热单signed等级，两侧max相减映射当地背景；五行火不等于热。实际值按共同时间建立/消散，残留不是复制来源，同类数量不放大辐射。规则在[环境](../../design/rules/environment.md)。
- 首包开发会话封闭访问原world；原公开对象不是通用隔离API。等待期间仅最后完整view可见，保存busy，已执行边界阶段不重跑。普通Main、完整过载治理、材料拆并、携物整体遮掩/中和、房间、生物后果仍未接。
- 普通存档schema51/区域42保持；开发验收快照不等于正式普通存档迁入。失败候选不改活世界，历史版本按[兼容政策](../engineering/compatibility.md)有限退役。

下一步由本包实际测量和讨论决定，不从旧Goal/历史QA自动连做。当前不宣称完整游戏、45–60分钟切片或Windows独立发行已完成。

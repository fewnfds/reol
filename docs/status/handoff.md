# 当前接续

核对：2026-11-05。[静止地面来源连续响应包](../plans/environment-object-loop/response-ground.md)功能接缝已实现并完成声明范围的因果/画面/小档验证，准确代码完整回归通过；**候选吞吐和512²存读出口未达标**，不能称全部规格完成。现在停止报告讨论，不自动进入Main、房间、携行或玩法。无活动Goal、测试、基准或审查进程。

## 当前工作与检出

主工作区 `codex/world-engine`；起点 `333f6f50b628a4e45269f038affbb733f92fe42b`。代码已分阶段接回原分支：`98e713590f29348c94823674bc58618162ec53bf`及修复`0d8c03545d9e6f4b3094cb725b14eb14a1bb3f23`，文档另提交；最新HEAD/推送以Git为准。为保护四份原WIP，在忽略目录 `logs/environment_response/dev` 干净检出实施和验收；日志保全到`logs/environment_response/validation-artifacts/`后移除此自建检出，不维持第二套长期实现。

本包代码已接上：五通道实际影响owner、温度/五行目标续接、单实物来源/原位置/响应联合候选、到期动作pending/取消、共同事件边界续算、封闭开发会话和独立验收快照。普通Main仍由旧Q负责冷热。合同见[接口](../engineering/environment-response-contract.md)，实际范围/性能与原错误见[QA](../qa/20261105_environment_response.md)。

一次Sol/custom只读审查发现GroundCache.step_move错误预算失败未取消底层候选P2，已修到0d8c035；六组定向348断言0失败，工具Python57项通过。修复准确SHA独立检出一次完整check **264组/108331断言/0失败**，约1099s且无SCRIPT ERROR/ERROR，31份代码指纹前后不变。RTX3060真实渲染中观察到旧处消散、新处建立；两进程完整退出恢复到相同9000ms未来通过。首次跨进程失败是验收脚本默认JSON精度损失，已使用项目canonical_json保留完整精度；不是删除断言或改存档规则。

64²/128²近满格半径16、32次单源事件及存读已验；CPU单来源候选约3.5–3.7s，不得包装成顺畅实时搬物。512²联合JSON解析超过10GiB自建进程预算，输出mem null后在约1009s由主代理核准路径/PID停止，保留失败记录。修复SHA的512²纯计算32次通过：262142真实材料堆+1实物、激活264.520s、变更p99 3.634s、峰工作集3.837GiB。现GPU只加速已验基础目标，不加速联合候选。采用16GB整机/单3060目标，模块几百MB守卫不是游戏预算。后续讨论应先解决候选重复搜索及紧凑分块存读，再谈普通接管，不自动沿旧计划扩玩法。

主代理统一启动测试/基准/审查。长运行保留同一session由工具层等终态；不轮询日志数PASS、不派等待代理。实际活handle仅属本聊天当前工具状态；接续前先核进程，不重复启动。

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

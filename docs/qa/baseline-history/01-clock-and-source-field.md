# 验证基线历史分卷 01

> 历史记录：下文的版本、权限、下一步和 CI 状态只描述记录时，不代表现状。当前证据见[基线](../../status/baseline.md)。

# 构建、兼容与验证基线

核对：2026-11-05。本页只维护“哪个版本有什么证据”，不管理Goal或下一任务；授权/停点见[HANDOFF](../../status/handoff.md)，可玩范围见[FEATURES](../../status/features.md)。当前是M2系统原型，完整游戏及45–60分钟切片未验收。

## 已验代码基线

### F2b接缝：共同时间先结算后发布

2026-11-05，普通Main的GameClock已绑定原世界执行器，实际完成后才公布时间；预算不足保留帧债/显式目标，自动行程按真实子边界投影。保存拒绝欠算，提交期间加载先拒绝；未切换普通旧Q。时钟/世界提交与相关规则定向、原生在途保存的两独立进程同未来已有证据，完整范围及最终计数见[QA](../20261105_clock_world_commit.md)；完整回归待最终SHA。

### F2a-5：源场/实际温度联合候选

2026-11-05，Cache来源变更候选与原温度bulk在同一同步栈联合提交，pending/cancel/过期不提前改活场；Cache/服务53551项、Response/温度1616项和协调器266项均0失败，真实GPU原服务12案例仍通过。独立两进程重建源投影与温度未来相同。2048²实插4194304来源、仅两端2块/512格变更，场工作1024时p99为0.828ms、目标输入17格p99为0.970ms；不是419万完整实物、整图变化或Main容量。具体范围、首个QA数字比较错误与原日志见[QA](../20261105_source_temperature_transition.md)。当前Main仍旧Q，真实物件/时间/受体切换未完成，完整回归待最终SHA。

### F2a-4：按块输入与预算续算

2026-11-05，同一温度owner新增最多64块的packed批量准备，resume预算耗尽保cursor，完成后统一发布，取消/错误不改活状态；Response/State1607项与段编译138项0失败，原v1两进程未来不变。128²三种预算结果相同，256槽冷resume p95/p99为0.734/0.833ms，变后提交0.064ms；已有巨量root/高异质边界和Main/GPU/原物联合事务未验，不能当全世界帧预算。准确成本/同步残项见[QA](../20261105_bounded_temperature_preparation.md)，完整回归待最终SHA。

### F2a-3：分块温度与候选发布

2026-11-05，同一隔离温度owner改packed块与私有候选，Response/State593项、目标段138项均0失败；v1两独立进程的原检查点/未来散列保持一致。16384格首次commit约0.02ms，变化提交约0.1–0.7ms；512²262144温度格及1%/10%/全部变化在30秒/1GiB守卫内完成，但整批prepare/快照仍为秒级、工作集近950MB，尚无自动分片预算/Main/联合世界容量结论。准确范围、稀疏与不利结果见[QA](../20261105_packed_temperature_state.md)，完整回归待推送SHA。

### F2a-2：气候/tide目标段与边界索引

2026-11-05，隔离目标段编译138项0失败；Response＋索引化State456项0失败。按真实天气/气候与固定全局格点切段，额外边界不重采tide，等阶冷热跳过无效边界。16384格的下一边界p99由17.789ms降至0.001ms；完整prepare/commit仍约198/500ms，未证明密集动态温度可用。代码与精度理论/成本原始证据见[F2a-2 QA](../20261105_temperature_segments_and_budget.md)。尚未接Main、完整调度/真实来源事务或房间；完整回归待最终SHA。

### F2a-1：实际温度状态与独立存读

2026-11-05，已知目标段的实际温度状态已实现；Response可跳过积分，两组378断言0失败。源场目标演示A移B的旧格回归/新格建立及等阶冷热抵消；全精度JSON与两独立进程3格/12点未来散列相同，失败恢复和预算不足不改原状态。它不是原物/源场/温度联合事务，也未接Main、完整气候/tide调度或房间。当前逐格对象/边界扫描尚无密集动态温度容量结论。准确日志/散列/范围见[F2a证据](../20261105_actual_temperature_state.md)。完整回归待本包推送SHA；前推送08c8b1d/run41958840430在本提交准备仅发现in_progress，不轮询。

### F1：紧凑缓存与可选GPU服务

2026-11-05，隔离cache＋CPU/GPU调度器已实现：35180项定向0失败，真实RTX3060原生12案例/7636格/53452通道与F0一致。512²整图GPU包含setup/传输/校验/发布约160ms，1%变后166ms；CPU同密集参照初建约9.7秒。2048²已有4194304来源且128²局部窗口通过，整图GPU曾触1GiB上限失败，不能称全图容量通过。普通Main12人开局180帧运行p95/p99=13.473/24.764ms，非稠密环境或战斗验收。准确硬件、口径、失败、日志及未接入限制见[F1证据](../20261105_field_compute_acceleration.md)；尚未替换主游戏旧热模型，也未新增有效玩家GPU设置。完整回归仍留最终SHA CI。

### F0：新源场纯规则与F1查询基线

2026-11-05，隔离七通道max场、整数圆核、等级温度表、共享环境潮汐和单段响应已实现；五组8110断言0失败。512²实插262144来源的有界基准已测，1024点基础查询641.975ms、潮汐5.335ms、工作集峰443617280B；它揭示字典查询瓶颈，不证明全场重建、实际物品/Main/房间或FPS。准确范围、原始日志与观察面板审查修复见[源场基础证据](../20261105_source_field_foundation.md)。F1紧凑缓存与F2普通运行替换仍待验；完整回归以最终SHA CI为准。

### 恢复实施：器物选择窄修复验

2026-11-05，新Goal准备实际提交时核对`c40c5573457f06d65b11bade434f7e05de72065a`/run41929130480缓存终态failure，并取得完整artifact。234组通过/1组失败/33748断言，唯一失败仍为相机变换后的剑/珠重叠点击，未发现其他引擎错误；不将旧SHA失败当作新源场结果。当前可见命中循环选择的3文件窄修已在新工作区复验：首次组合在30秒限额时中止，规则/潮汐及weapon_items_runtime已完成且无失败，intrinsic组未完成不计通过（`logs/source-field-initial-focus.json`）。只接续未完成的intrinsic_light_runtime/local_light_runtime/weapon_items三组，564断言0失败、25.058秒/417034240B，未见引擎错误（`logs/object-stack-remaining-focus.json`）。合计器物4组660断言，未重跑已经完成的组；此前原生图标/点击证据仍见暂停包记录，窄修不改世界模型。准确修复SHA和原生审查随后登记，最终完整回归交对应SHA CI。

| 版本/工作包 | 证据 | 适用边界 |
|---|---|---|
| `66be8833b2aea3d4a53a7758325a108ba925e0ed` F2a-1/2与前序 | [CI 41962215415](https://github.com/fewnfds/reol/actions/runs/41962215415) completed/success，源候选提交准备由主代理按完整SHA核对 | 覆盖已知段实际温度、气候/tide编译及边界索引、F1及前序；不覆盖后来的packed/bulk/源候选 |
| `99eb91ce311a7e0df798dda3795baf6d857464e6` W1b地理气温及前序 | [CI 41916383335](https://github.com/fewnfds/reol/actions/runs/41916383335) completed/success，230组/32690断言/0失败；C1c-1b实际提交准备核对完整SHA与artifact | 覆盖W1b及此前世界包；不覆盖后来W2b-1固有光和C1c-1b历史证据解耦 |
| `12f4cf9b5d968e290c5e955601b0ea1ca1ff0388` W2b-0固定火石光与前序世界包 | [CI 41913715806](https://github.com/fewnfds/reol/actions/runs/41913715806) completed/success，227组/29794断言/0失败；W2b-1实际提交准备核对完整SHA与artifact | 覆盖C1热场/固定源、W1a日照、P1a寻路和W2b-0及其前序；不覆盖W1b地理气温或W2b-1固有光 |
| `73b765cf533006ca4c90149b55b8f937554dc584` C1a-1共享背景及前序修复 | [CI 41859915825](https://github.com/fewnfds/reol/actions/runs/41859915825) completed/success，C1a-2审查修复实际提交准备核对完整SHA | 覆盖C1a-1与前序A/B/C0及金额包；不覆盖C1a-2固定参考 |
| `62c1aa7589e272d1770a75e90aa3e29fc439d9d6` 地表编辑/活接触及历史投影修复 | [CI 41838689908](https://github.com/fewnfds/reol/actions/runs/41838689908) completed/success，B1a修复提交准备时核对完整SHA | 覆盖此前A0/B0代码；不覆盖后来的B1a及其修复 |
| `945891cc977a60ecb9a499574b33784da9f5cca1` 首屏/会话引用修复 | [CI 41766949005](https://github.com/fewnfds/reol/actions/runs/41766949005) completed/success，2026-11-04通过`tools/ci.py`终态缓存核对完整SHA | 当前游戏稳定起点；四套定向266断言和原生截图见[首屏QA](../20261104_world_view_continuity.md) |
| `a29314667f6a743fd3177b0a5190c810c2b6650b` 私人器物交换 | [CI 41762510648](https://github.com/fewnfds/reol/actions/runs/41762510648)：180组、17180断言、0失败，CHECK PASSED | 一环固定报价的有限样本，非通用市场；[QA](../20261104_private_exchange.md) |
| `0804c70c385306c592df1d06b39aa0a8c357ff5a` 引物包与旧档断言修正 | [CI 41755190941](https://github.com/fewnfds/reol/actions/runs/41755190941)：175组、16695断言、0失败，CHECK PASSED | 后来的修复不可沿用此绿色；[QA](../20261104_drawing_ring.md) |

更早通过/失败、修复与日志原文见[整理前基线](https://github.com/fewnfds/reol/blob/8c3deaa972f932e999167b61ea6b166b928cfe5f/docs/archive/documentation_consolidation_20261104/docs/BASELINE.md)及[QA索引](../README.md)。只认具体SHA和验证范围；旧失败数量不作为当前失败，旧成功也不覆盖新代码。
